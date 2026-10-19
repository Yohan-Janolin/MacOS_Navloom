import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                section("Les outils") {
                    ToolCard(feature: .faviconSync,
                             text: "Récupère les icônes (favicons) manquantes de tes favoris et les écrit dans le navigateur. Le navigateur doit être fermé au moment d'écrire.")
                    ToolCard(feature: .twins,
                             text: "Retrouve les favoris qui pointent sur exactement la même URL et supprime ceux que tu coches. Le navigateur doit être fermé, et la synchro des favoris désactivée (voir plus bas).")
                    ToolCard(feature: .ghosts,
                             text: "Ouvre chaque favori pour repérer ceux dont la page n'existe plus (page introuvable, domaine disparu, redirection vers l'accueil) et supprime ceux que tu coches. La recherche peut se faire navigateur ouvert ; pour supprimer, il doit être fermé et la synchro des favoris désactivée (voir plus bas). Double-clic sur un résultat pour le tester dans ton navigateur.")
                    ToolCard(feature: .echo,
                             text: "Réplique les favoris d'un navigateur (la source) vers un autre (la cible), avec leurs icônes, que les navigateurs importent mal. Deux modes : ajouter les favoris manquants, ou copie complète, qui rend la cible identique à la source (ce qui n'y est pas est supprimé). La comparaison se fait navigateurs ouverts ; pour écrire, la cible doit être fermée et sa synchro des favoris désactivée (voir plus bas). Des sauvegardes sont créées avant.")
                    ToolCard(feature: .ferry,
                             text: "Rassemble en une seule liste les onglets ouverts de tous tes navigateurs, regroupés par fenêtre (avec le profil quand il y en a plusieurs, et les espaces d'Opera), avec une recherche et un export texte. Lecture seule : rien n'est fermé ni modifié. La première fois, macOS te demande d'autoriser Navloom à contrôler chaque navigateur. Les fenêtres de navigation privée sont masquées par défaut.")
                    ToolCard(feature: .backups,
                             text: "Liste les sauvegardes créées avant chaque écriture, par outil (FaviconSync, Twins, Ghosts, Echo), et permet de restaurer l'une d'elles.")
                }

                section("Limites") {
                    InfoCard(systemImage: "globe", tint: Brand.sky,
                             title: "Navigateurs pris en charge",
                             text: "\(supportedBrowsers). Arc n'est pas supporté, pas plus que Safari ou Firefox, qui n'utilisent pas le même format de favoris.")
                    InfoCard(systemImage: "person.crop.circle.badge.exclamationmark", tint: Brand.coral,
                             title: "Chrome et les favoris du compte Google",
                             text: "Quand Chrome enregistre les favoris « dans ton compte Google » (Réglages › Dans votre compte Google › Favoris), il les range dans un fichier à part. Navloom les lit : FaviconSync, Twins et Ghosts les prennent en compte, avec une icône nuage. Mais ils ne sont jamais cochables, car Chrome les remettrait depuis le serveur : supprime-les à la main dans Chrome. Seuls tes favoris locaux se suppriment depuis Navloom. Si tu désactives l'option Favoris dans Chrome, il masque ceux du compte et Navloom les ignore aussi (d'après le réglage que Chrome écrit dans ses préférences).")
                    InfoCard(systemImage: "lock.shield.fill", tint: .orange,
                             title: "Accès complet au disque",
                             text: "Sur macOS 27, Chrome, Edge et Brave (versions stables) protègent leurs données : tant que Navloom n'a pas l'accès complet au disque, ils n'apparaissent pas dans la liste des navigateurs. Ouvre Réglages Système › Confidentialité et sécurité › Accès complet au disque, ajoute Navloom avec le bouton « + », active-le, puis relance Navloom. Les autres navigateurs n'en ont pas besoin. Navloom ne lit que les favoris, les icônes et quelques réglages (noms de profils, état de la synchro).")
                    InfoCard(systemImage: "power", tint: .orange,
                             title: "Navigateur fermé",
                             text: "Navloom modifie les fichiers du navigateur, qui les réécrirait à sa fermeture. Quitte-le complètement (Cmd + Q) avant d'écrire. Chaque écriture est précédée d'une sauvegarde.")
                }

                section("Twins / Ghosts / Echo - Problème avec la synchronisation") {
                    syncGuide
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Navloom")
    }

    /// Liste tirée de la liste des navigateurs connus : elle ne peut pas être oubliée à l'ajout d'un navigateur.
    private var supportedBrowsers: String {
        let names = ChromiumBrowser.known.map(\.name)
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " et " + last
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Navloom")
                .font(.largeTitle.bold())
                .foregroundStyle(LinearGradient(colors: [Brand.coral, Brand.violet],
                                                startPoint: .leading, endPoint: .trailing))
            Text("Des outils pour entretenir les favoris de ton navigateur")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var syncGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pourquoi la synchro gêne", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Quand la synchro des favoris est active, le navigateur remet au lancement les favoris que Navloom a supprimés. Twins et Ghosts refusent donc de supprimer, et Echo d’écrire dans la cible, tant qu’elle est active. Navloom ne peut pas la couper à ta place : elle se règle dans le navigateur, avec ton compte.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            Text("Avec Vivaldi")
                .font(.subheadline.bold())
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Dans Vivaldi, ouvre Réglages › Synchronisation et décoche « Signets ».")
                step(2, "Quitte Vivaldi (Cmd + Q), puis supprime tes doublons ou tes liens morts avec Navloom.")
                step(3, "Pour réactiver la synchro des favoris sans faire revenir les favoris supprimés : retourne dans Réglages › Synchronisation et clique sur « Réinitialiser les données distantes ». Cela efface les données stockées chez Vivaldi, ton mot de passe de chiffrement et te déconnecte.")
                step(4, "Reconnecte-toi, redéfinis ton mot de passe de chiffrement (tu peux reprendre le même), puis recoche « Signets ».")
            }

            Text("Navloom lit l'état de la synchro dans tous les navigateurs pris en charge. Pour Chrome, les favoris du compte Google sont dans un fichier séparé : la synchro complète est la seule à bloquer la suppression (voir « Limites »).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.orange.gradient, in: Circle())
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToolCard: View {
    let feature: Feature
    let text: String

    var body: some View {
        InfoCard(systemImage: feature.systemImage, tint: feature.tint, title: feature.title, text: text)
    }
}

private struct InfoCard: View {
    let systemImage: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SidebarIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HomeView()
}
