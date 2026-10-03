import Foundation
import SQLite3

/// "Copie ces données, ne garde pas mon pointeur" (constante SQLite)
private nonisolated let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

nonisolated enum FaviconDatabaseError: LocalizedError {
    case open(String)
    case query(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): "Impossible d'ouvrir la base Favicons : \(message)"
        case .query(let message): "Erreur SQLite : \(message)"
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
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "erreur inconnue"
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

    // MARK: - Transactions

    func begin() throws { try execute("BEGIN TRANSACTION") }
    func commit() throws { try execute("COMMIT") }
    func rollback() { try? execute("ROLLBACK") }

    // MARK: - Écriture

    /// Insère une icône + ses bitmaps, retourne l'icon_id.
    func insertIcon(sourceURL: String, bitmaps: [FaviconBitmap]) throws -> Int64 {
        guard !bitmaps.isEmpty else { throw FaviconDatabaseError.query("aucun bitmap à écrire") }

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
