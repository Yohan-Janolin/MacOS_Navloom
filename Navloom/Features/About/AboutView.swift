import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                VStack(spacing: 0) {
                    row("Author", AppInfo.authorName)
                    Divider()
                    row("Version", String(localized: "\(AppInfo.version) (build \(AppInfo.build))"))
                    Divider()
                    row("Release date", AppInfo.releaseDate.formatted(date: .long, time: .omitted))
                    Divider()
                    linkRow("GitHub repository", AppInfo.repositoryName, url: AppInfo.repositoryURL)
                    Divider()
                    linkRow("Report a problem", String(localized: "Open an issue"), url: AppInfo.newIssueURL)
                }
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                disclaimer
            }
            .frame(maxWidth: 520)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text(verbatim: "Navloom"))
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(verbatim: "Navloom")
                .font(.largeTitle.bold())
                .foregroundStyle(LinearGradient(colors: [Brand.coral, Brand.violet],
                                                startPoint: .leading, endPoint: .trailing))
            Text("Tools to keep your bookmarks in shape")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Disclaimer", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Navloom is provided “as is”, without any warranty. It modifies your browser's files. A backup is created before every write, but the author can't be held responsible for any data loss or other damage. You use it at your own risk.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value).textSelection(.enabled)
        }
        .padding(.vertical, 10)
    }

    private func linkRow(_ title: LocalizedStringKey, _ label: String, url: URL) -> some View {
        LabeledContent(title) {
            Link(destination: url) { Text(verbatim: label) }
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    AboutView()
}
