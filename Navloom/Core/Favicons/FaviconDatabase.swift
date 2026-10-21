import Foundation
import SQLite3

/// "Copie ces données, ne garde pas mon pointeur" (constante SQLite)
private nonisolated let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

nonisolated enum FaviconDatabaseError: LocalizedError {
    case open(String)
    case query(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): String(localized: "Couldn't open the Favicons database: \(message)")
        case .query(let message): String(localized: "SQLite error: \(message)")
        }
    }
}

/// Accès à la base SQLite `Favicons` d'un navigateur Chromium.
/// Un `actor` sérialise les accès : aucune requête ne tourne sur le thread principal.
///
/// Écriture : le navigateur doit être fermé (il verrouille sa base).
actor FaviconDatabase {
    private var handle: OpaquePointer?

    init(url: URL, writable: Bool) throws {
        var db: OpaquePointer?
        let status: Int32

        if writable {
            status = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil)
        } else {
            // immutable=1 : lecture même si le navigateur est ouvert (contourne le verrou)
            status = sqlite3_open_v2(url.absoluteString + "?immutable=1", &db,
                                     SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        }

        guard status == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? String(localized: "unknown error")
            sqlite3_close(db)
            throw FaviconDatabaseError.open(message)
        }
        handle = db
    }

    deinit {
        sqlite3_close(handle)
    }

    // MARK: - Lecture

    /// Toutes les URLs de pages qui ont déjà une favicon (comparaison sur l'URL exacte).
    func urlsWithFavicon() throws -> Set<String> {
        let stmt = try prepare("SELECT page_url FROM icon_mapping")
        defer { sqlite3_finalize(stmt) }

        var urls = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 0) {
                urls.insert(String(cString: text))
            }
        }
        return urls
    }
    
    /// Nombre de pages associées à une favicon (sert à décrire une sauvegarde).
    func mappingCount() throws -> Int {
        let stmt = try prepare("SELECT COUNT(*) FROM icon_mapping")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw lastError }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - Copie entre navigateurs (Echo)

    /// L'icône d'une page par page : pour chaque URL qui en a une, l'URL de l'image et ses bitmaps.
    /// Les pages sans icône (ou dont les bitmaps sont vides) sont absentes du résultat.
    func favicons(forPages pageURLs: [String]) throws -> [String: StoredFavicon] {
        let stmt = try prepare("""
            SELECT f.id, f.url, b.width, b.image_data
            FROM icon_mapping m
            JOIN favicons f ON f.id = m.icon_id
            JOIN favicon_bitmaps b ON b.icon_id = f.id
            WHERE m.page_url = ? AND f.icon_type = 1
              AND b.image_data IS NOT NULL AND LENGTH(b.image_data) > 0
            ORDER BY f.id, b.width
            """)
        defer { sqlite3_finalize(stmt) }

        var result: [String: StoredFavicon] = [:]
        for pageURL in pageURLs where result[pageURL] == nil {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, pageURL, -1, sqliteTransient)

            // Une page peut pointer sur plusieurs icônes : on garde la première, avec tous ses bitmaps.
            var chosenID: Int64?
            var iconURL = ""
            var bitmaps: [FaviconBitmap] = []

            var status = sqlite3_step(stmt)
            while status == SQLITE_ROW {
                let iconID = sqlite3_column_int64(stmt, 0)
                if chosenID == nil {
                    chosenID = iconID
                    if let text = sqlite3_column_text(stmt, 1) { iconURL = String(cString: text) }
                }
                if iconID != chosenID { break }

                let width = Int(sqlite3_column_int(stmt, 2))
                let count = Int(sqlite3_column_bytes(stmt, 3))
                if count > 0, let bytes = sqlite3_column_blob(stmt, 3) {
                    bitmaps.append(FaviconBitmap(size: width, png: Data(bytes: bytes, count: count)))
                }
                status = sqlite3_step(stmt)
            }
            guard status == SQLITE_ROW || status == SQLITE_DONE else { throw lastError }

            if chosenID != nil, !bitmaps.isEmpty {
                result[pageURL] = StoredFavicon(iconURL: iconURL, bitmaps: bitmaps)
            }
        }
        return result
    }

    // MARK: - Icônes des onglets ouverts (Ferry)

    /// Une icône pour chaque préfixe d'URL (« https://github.com/ ») : celle de n'importe quelle
    /// page qui commence ainsi. Sert de repli quand l'URL exacte d'un onglet n'est pas dans la base.
    /// Retourne le plus grand bitmap ne dépassant pas 64 pixels (sinon le plus petit disponible).
    func anyFavicon(forPrefixes prefixes: [String]) throws -> [String: Data] {
        let stmt = try prepare("""
            SELECT b.width, b.image_data
            FROM icon_mapping m
            JOIN favicons f ON f.id = m.icon_id
            JOIN favicon_bitmaps b ON b.icon_id = f.id
            WHERE m.page_url LIKE ? ESCAPE '\\' AND f.icon_type = 1
              AND b.image_data IS NOT NULL AND LENGTH(b.image_data) > 0
            ORDER BY m.icon_id, b.width
            LIMIT 8
            """)
        defer { sqlite3_finalize(stmt) }

        var result: [String: Data] = [:]
        for prefix in prefixes where result[prefix] == nil {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            let pattern = Self.escapedForLike(prefix) + "%"
            sqlite3_bind_text(stmt, 1, pattern, -1, sqliteTransient)

            var bitmaps: [FaviconBitmap] = []
            var status = sqlite3_step(stmt)
            while status == SQLITE_ROW {
                let width = Int(sqlite3_column_int(stmt, 0))
                let count = Int(sqlite3_column_bytes(stmt, 1))
                if count > 0, let bytes = sqlite3_column_blob(stmt, 1) {
                    bitmaps.append(FaviconBitmap(size: width, png: Data(bytes: bytes, count: count)))
                }
                status = sqlite3_step(stmt)
            }
            guard status == SQLITE_ROW || status == SQLITE_DONE else { throw lastError }

            if let best = Self.bestBitmap(bitmaps) {
                result[prefix] = best.png
            }
        }
        return result
    }

    /// Le plus grand bitmap ne dépassant pas `maxSize` pixels, sinon le plus petit de tous.
    nonisolated static func bestBitmap(_ bitmaps: [FaviconBitmap], maxSize: Int = 64) -> FaviconBitmap? {
        let small = bitmaps.filter { $0.size <= maxSize }
        if let best = small.max(by: { $0.size < $1.size }) { return best }
        return bitmaps.min(by: { $0.size < $1.size })
    }

    /// Neutralise les jokers de LIKE (`%` et `_`) présents dans une URL.
    nonisolated static func escapedForLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    /// Identifiant d'une icône déjà présente (même URL d'image, avec au moins un bitmap), pour la
    /// réutiliser au lieu d'en créer une seconde.
    func iconID(forIconURL iconURL: String) throws -> Int64? {
        let stmt = try prepare("""
            SELECT id FROM favicons
            WHERE url = ? AND icon_type = 1
              AND EXISTS (SELECT 1 FROM favicon_bitmaps b
                          WHERE b.icon_id = favicons.id
                            AND b.image_data IS NOT NULL AND LENGTH(b.image_data) > 0)
            LIMIT 1
            """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, iconURL, -1, sqliteTransient)

        switch sqlite3_step(stmt) {
        case SQLITE_ROW: return sqlite3_column_int64(stmt, 0)
        case SQLITE_DONE: return nil
        default: throw lastError
        }
    }

    // MARK: - Transactions

    func begin() throws { try execute("BEGIN TRANSACTION") }
    func commit() throws { try execute("COMMIT") }
    func rollback() { try? execute("ROLLBACK") }

    // MARK: - Écriture

    /// Insère une icône + ses bitmaps, retourne l'icon_id.
    func insertIcon(sourceURL: String, bitmaps: [FaviconBitmap]) throws -> Int64 {
        guard !bitmaps.isEmpty else { throw FaviconDatabaseError.query(String(localized: "no bitmap to write")) }

        let iconStmt = try prepare("INSERT INTO favicons (url, icon_type) VALUES (?, 1)")
        defer { sqlite3_finalize(iconStmt) }
        sqlite3_bind_text(iconStmt, 1, sourceURL, -1, sqliteTransient)
        try stepUntilDone(iconStmt)

        let iconID = sqlite3_last_insert_rowid(handle)

        // Le format de date de Chromium : microsecondes depuis le 1er janvier 1601
        let chromiumEpochOffset: Int64 = 11_644_473_600_000_000
        let now = Int64(Date().timeIntervalSince1970 * 1_000_000) + chromiumEpochOffset

        for bitmap in bitmaps {
            let stmt = try prepare("""
                INSERT INTO favicon_bitmaps (icon_id, image_data, width, height, last_updated)
                VALUES (?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, iconID)
            bitmap.png.withUnsafeBytes { buffer in
                _ = sqlite3_bind_blob(stmt, 2, buffer.baseAddress, Int32(buffer.count), sqliteTransient)
            }
            sqlite3_bind_int(stmt, 3, Int32(bitmap.size))
            sqlite3_bind_int(stmt, 4, Int32(bitmap.size))
            sqlite3_bind_int64(stmt, 5, now)
            try stepUntilDone(stmt)
        }
        return iconID
    }

    /// Associe une page à une icône.
    func insertMapping(pageURL: String, iconID: Int64) throws {
        let stmt = try prepare("INSERT INTO icon_mapping (page_url, icon_id, page_url_type) VALUES (?, ?, 0)")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, pageURL, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 2, iconID)
        try stepUntilDone(stmt)
    }

    // MARK: - Utilitaires SQLite

    private var lastError: FaviconDatabaseError {
        .query(String(cString: sqlite3_errmsg(handle)))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw lastError
        }
        return stmt
    }

    private func stepUntilDone(_ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError }
    }
}

/// L'icône d'une page, telle qu'elle est rangée dans une base Favicons.
/// `FaviconBitmap.size` est la largeur lue dans la base ; `png` contient les octets d'origine
/// (Chromium y range du PNG, mais Echo ne le suppose pas : voir `EchoEngine`).
nonisolated struct StoredFavicon: Sendable {
    let iconURL: String
    let bitmaps: [FaviconBitmap]
}
