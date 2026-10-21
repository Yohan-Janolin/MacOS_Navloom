import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                section("Tools") {
                    ToolCard(feature: .faviconSync,
                             text: String(localized: "Fetches the missing icons (favicons) of your bookmarks and writes them into the browser. The browser must be closed when writing."))
                    ToolCard(feature: .twins,
                             text: String(localized: "Finds bookmarks pointing to exactly the same URL and deletes the ones you check. The browser must be closed, and bookmark sync turned off (see below)."))
                    ToolCard(feature: .ghosts,
                             text: String(localized: "Opens each bookmark to spot the ones whose page no longer exists (page not found, domain gone, redirect to the home page) and deletes the ones you check. The scan can run with the browser open; to delete, it must be closed and bookmark sync turned off (see below). Double-click a result to test it in your browser."))
                    ToolCard(feature: .echo,
                             text: String(localized: "Replicates the bookmarks of one browser (the source) to another (the target), with their icons, which browsers import poorly. Two modes: add the missing bookmarks, or full copy, which makes the target identical to the source (anything not in the source is deleted). The comparison runs with the browsers open; to write, the target must be closed and its bookmark sync turned off (see below). Backups are created beforehand."))
                    ToolCard(feature: .ferry,
                             text: String(localized: "Gathers the open tabs of all your browsers in a single list, grouped by window (with the profile when there are several, and the Opera and Vivaldi workspaces), with search and a text export. Check tabs, workspaces or windows to reopen them in another browser, keeping the window layout (and one window per workspace, since workspaces can't be recreated). Optionally, the original tabs are closed afterwards, only if their copy is found in the target; Opera refuses to close those in its other workspaces. The first time, macOS asks you to allow Navloom to control each browser. Private windows are hidden by default."))
                    ToolCard(feature: .backups,
                             text: String(localized: "Lists the backups created before each write, by tool (FaviconSync, Twins, Ghosts, Echo), and lets you restore one of them."))
                }

                section("Limitations") {
                    InfoCard(systemImage: "globe", tint: Brand.sky,
                             title: String(localized: "Supported browsers"),
                             text: String(localized: "\(supportedBrowsers). Arc isn't supported, nor are Safari or Firefox, which don't use the same bookmark format."))
                    InfoCard(systemImage: "person.crop.circle.badge.exclamationmark", tint: Brand.coral,
                             title: String(localized: "Chrome and Google Account bookmarks"),
                             text: String(localized: "When Chrome saves bookmarks “in your Google Account” (Settings › In your Google Account › Bookmarks), it stores them in a separate file. Navloom reads them: FaviconSync, Twins and Ghosts take them into account, with a cloud icon. But they can never be checked, because Chrome would restore them from the server: delete them by hand in Chrome. Only your local bookmarks can be deleted from Navloom. If you turn off the Bookmarks option in Chrome, it hides the account bookmarks and Navloom ignores them too (based on the setting Chrome writes in its preferences)."))
                    InfoCard(systemImage: "lock.shield.fill", tint: .orange,
                             title: String(localized: "Full Disk Access"),
                             text: String(localized: "On macOS 27, Chrome, Edge and Brave (stable versions) protect their data: until Navloom has Full Disk Access, they don't appear in the list of browsers. Open System Settings › Privacy & Security › Full Disk Access, add Navloom with the “+” button, turn it on, then relaunch Navloom. The other browsers don't need it. Navloom only reads bookmarks, icons and a few settings (profile names, sync status)."))
                    InfoCard(systemImage: "power", tint: .orange,
                             title: String(localized: "Browser closed"),
                             text: String(localized: "Navloom modifies the browser's files, which the browser would overwrite when it quits. Quit it completely (Cmd + Q) before writing. Every write is preceded by a backup."))
                }

                section("Twins / Ghosts / Echo - Trouble with sync") {
                    syncGuide
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text(verbatim: "Navloom"))
    }

    /// Liste tirée de la liste des navigateurs connus : elle ne peut pas être oubliée à l'ajout d'un navigateur.
    private var supportedBrowsers: String {
        DiskAccess.joinedNames(ChromiumBrowser.known.map(\.name))
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(verbatim: "Navloom")
                .font(.largeTitle.bold())
                .foregroundStyle(LinearGradient(colors: [Brand.coral, Brand.violet],
                                                startPoint: .leading, endPoint: .trailing))
            Text("Tools to keep your browser bookmarks in shape")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var syncGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Why sync gets in the way", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("When bookmark sync is on, the browser brings back at launch the bookmarks Navloom deleted. So Twins and Ghosts refuse to delete, and Echo refuses to write to the target, while it's on. Navloom can't turn it off for you: it's set in the browser, with your account.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            Text("With Vivaldi")
                .font(.subheadline.bold())
            VStack(alignment: .leading, spacing: 8) {
                step(1, "In Vivaldi, open Settings › Sync and uncheck “Bookmarks”.")
                step(2, "Quit Vivaldi (Cmd + Q), then delete your duplicates or dead links with Navloom.")
                step(3, "To turn bookmark sync back on without bringing back the deleted bookmarks: go back to Settings › Sync and click “Reset Remote Data”. This erases the data stored by Vivaldi and your encryption password, and signs you out.")
                step(4, "Sign back in, set your encryption password again (you can reuse the same one), then check “Bookmarks” again.")
            }

            Text("Navloom reads the sync status in every supported browser. For Chrome, Google Account bookmarks are in a separate file: only full sync blocks deletion (see “Limitations”).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.orange.gradient, in: Circle())
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
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
