import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                VStack(spacing: 0) {
                    row("Auteur", AppInfo.authorName)
                    Divider()
                    linkRow("Contact", AppInfo.authorEmail, url: AppInfo.mailURL)
                    Divider()
                    row("Version", "\(AppInfo.version) (build \(AppInfo.build))")
                    Divider()
                    row("Date de release", AppInfo.releaseDate.formatted(date: .long, time: .omitted))
                    Divider()
                    linkRow("Dépôt GitHub", "Yohan-Janolin/Navloom", url: AppInfo.repositoryURL)
                    Divider()
                    linkRow("Signaler un problème", "Ouvrir une issue", url: AppInfo.newIssueURL)
                }
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                disclaimer
            }
            .frame(maxWidth: 520)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Navloom")
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Navloom")
                .font(.largeTitle.bold())
                .foregroundStyle(LinearGradient(colors: [Brand.coral, Brand.violet],
                                                startPoint: .leading, endPoint: .trailing))
            Text("Des outils pour entretenir tes favoris")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Avertissement", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Navloom est fourni « tel quel », sans aucune garantie. Il modifie des fichiers de ton navigateur. Une sauvegarde est créée avant chaque écriture, mais l'auteur ne peut pas être tenu responsable d'une perte de données ou de tout autre dégât. Tu l'utilises à tes risques.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value).textSelection(.enabled)
        }
        .padding(.vertical, 10)
    }

    private func linkRow(_ title: String, _ label: String, url: URL) -> some View {
        LabeledContent(title) {
            Link(label, destination: url)
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    AboutView()
}
