<p align="center">
  <img src="Design/Navloom-icon.svg" width="128" alt="Navloom icon" />
</p>

<h1 align="center">Navloom</h1>

<p align="center">
  <a href="https://github.com/Yohan-Janolin/MacOS_Navloom/releases/latest"><img src="https://img.shields.io/github/v/release/Yohan-Janolin/MacOS_Navloom?label=version&color=A78BFA" alt="Latest version" /></a>
  <img src="https://img.shields.io/badge/macOS-14.6%2B-1C1B33?logo=apple&logoColor=white" alt="macOS 14.6+" />
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-universal-60A5FA" alt="Universal app" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2DD4BF" alt="MIT License" /></a>
</p>

<p align="center">
  🇬🇧 English · <a href="README.fr.md">🇫🇷 Français</a>
</p>

---

Navloom is a small toolbox to keep your browser bookmarks and tabs in shape on macOS.

It brings back missing favicons, finds duplicates and dead links, copies bookmarks from one browser to another with their icons, and gathers the open tabs of all your browsers in one place to move them around. Everything happens on your Mac, in a native interface, with a backup before every change.

Navloom works with Chromium-based browsers (Chrome, Edge, Brave, Vivaldi, Opera…) and is available in English and French.

## 📸 Screenshots

<p align="center">
  <img src="docs/screenshots/home.png" width="800" alt="Navloom home screen" />
</p>

| FaviconSync | Twins | Ghosts |
|:---:|:---:|:---:|
| <img src="docs/screenshots/faviconsync.png" width="260" alt="FaviconSync" /> | <img src="docs/screenshots/twins.png" width="260" alt="Twins" /> | <img src="docs/screenshots/ghosts.png" width="260" alt="Ghosts" /> |
| **Echo** | **Ferry** | **Backups** |
| <img src="docs/screenshots/echo.png" width="260" alt="Echo" /> | <img src="docs/screenshots/ferry.png" width="260" alt="Ferry" /> | <img src="docs/screenshots/backups.png" width="260" alt="Backups" /> |

## ✨ Features

### ⭐ FaviconSync — missing favicons

After switching browsers, importing bookmarks or a browser glitch, many bookmarks end up without an icon. FaviconSync finds the bookmarks of a profile that have no favicon, fetches the icons from the websites (`favicon.ico`, then the icons declared in the page) and writes them into the browser's icon database.

- The analysis changes nothing; you review the results before writing.
- Results are sorted into three tabs: **fetched**, **no favicon** (the site really has none) and **failures** (timeout, server error…), with the reason for each.
- A text report can be exported.
- **Limitations:** the browser must be fully closed (Cmd + Q) to write. Some sites can't be reached without being signed in, or only declare their icon through JavaScript or SVG: those stay without an icon. Bookmarks pointing to devices on your local network require the *Local Network* permission.

### 🟦 Twins — duplicates

Twins groups the bookmarks that point to **exactly** the same URL and lets you delete the copies you check.

- One copy of each group always stays unchecked: you can't delete all of them by mistake.
- A shortcut keeps the first bookmark of each group and checks the others.
- **Limitations:** the browser must be closed and its **bookmark sync turned off**, otherwise the browser would bring the deleted bookmarks back at its next launch (the steps for Vivaldi are on the app's Home screen). URLs that differ only slightly (`http`/`https`, `www`, trailing `/`) are *not* considered duplicates.

### 👻 Ghosts — dead links

Ghosts opens each bookmark to check whether its page still responds, and sorts the problems into three tabs:

- **Dead**: page not found (404/410) or domain that no longer exists;
- **To check**: timeout, server error, invalid certificate… no conclusion possible;
- **Redirected**: the page now leads to another site or to the home page.

Double-click a result to open it in your browser, then delete the ones you check. A text report can be exported.

- **Limitations:** the scan can run with the browser open, but deleting requires it to be closed with bookmark sync turned off (as for Twins). Some sites answer “not found” to visitors who aren't signed in even though the page exists for you: always check before deleting.

### 📡 Echo — copy bookmarks between browsers

Browsers import each other's bookmarks, but often lose or damage their icons. Echo replicates the bookmarks of a **source** browser into a **target** browser, with their icons, without downloading them again.

- **Add missing** mode: the target keeps all its bookmarks; only the ones it's missing are added, in the same folders.
- **Full copy** mode: the target becomes identical to the source (folders, order, names); target bookmarks that aren't in the source are deleted.
- Comparison options: URL missing anywhere in the target or only in the same folder, and URL variants to treat as identical (`http`/`https`, `www`, parameters `?…`).
- **Limitations:** one source and one target at a time. The comparison can run with the browsers open; to write, the target must be closed and its bookmark sync turned off. Non-web bookmarks (`vivaldi://`, `opera://`…) aren't copied.

### ⛴️ Ferry — open tabs

Ferry gathers the open tabs of all your running browsers in a single list, grouped by browser, window, profile and workspace (Opera and Vivaldi), with search and a text export.

- Check tabs, workspaces or whole windows to reopen them in another browser, keeping the window layout (or in a single window).
- Optionally, the original tabs are closed afterwards, **only** once their copy has been found in the target.
- Private windows are hidden by default and can be reopened in private browsing.
- **Limitations:** workspaces can't be recreated in the target: each one arrives in its own window. Opera refuses to close tabs that belong to a workspace other than the one shown: they are copied but stay open. The first time, macOS asks you to allow Navloom to control each browser.

### 💾 Backups

Every write is preceded by a backup of the browser file it modifies (the `Bookmarks` file and/or the `Favicons` database). The **Backups** screen lists them by tool and restores any of them in one click (the current state is itself backed up first).

- Default location: `~/Library/Application Support/Navloom/Backups` (can be changed in Settings).
- Old backups can be cleaned up automatically (by default, the last 10 “before write” and 5 “before restore” are kept, per profile and per tool). Extra backups go to the Trash, they aren't deleted permanently.

## 🧩 Compatibility

**macOS 14.6 (Sonoma) or later**, on Apple Silicon and Intel Macs.

| Browser | FaviconSync | Twins | Ghosts | Echo | Ferry |
|---|:---:|:---:|:---:|:---:|:---:|
| Google Chrome · Beta · Canary | ✅ | ✅ ¹ | ✅ ¹ | ✅ | ✅ |
| Microsoft Edge · Beta · Dev · Canary | ✅ | ✅ | ✅ | ✅ | ✅ |
| Brave · Beta · Nightly | ✅ | ✅ | ✅ | ✅ | ✅ |
| Vivaldi · Snapshot | ✅ | ✅ | ✅ | ✅ | ✅ ² |
| Opera · Developer · GX · Air | ✅ | ✅ | ✅ | ✅ | ✅ ² ³ |
| Chromium | ✅ ⁴ | ✅ ⁴ | ✅ ⁴ | ✅ ⁴ | ✅ |
| Arc | ❌ | ❌ | ❌ | ❌ | ❌ |
| Safari | ❌ | ❌ | ❌ | ❌ | ❌ |
| Firefox (and Zen, LibreWolf…) | ❌ | ❌ | ❌ | ❌ | ❌ |

1. Bookmarks saved **in your Google Account** are shown (with a cloud icon) but can't be deleted from Navloom: Chrome would restore them from its servers. Delete them in Chrome itself.
2. Workspaces are read and shown.
3. Tabs from a workspace other than the one shown can be copied but not closed (Opera refuses).
4. Chromium only appears once it has at least one bookmark (before that, it has no bookmarks file).

**Not compatible:** Arc (it doesn't store its bookmarks in the same format, and doesn't reload icons set from outside), Safari and Firefox-based browsers (different bookmark formats).

## 🔐 Required permissions

| Permission | Why | When |
|---|---|---|
| **Full Disk Access** | On recent macOS versions, Chrome, Edge and Brave (stable versions) protect their data folder. Without this access, they don't appear in Navloom. Other browsers don't need it. | At first launch, if one of these browsers is installed. Navloom explains how to grant it. |
| **Automation** (control of each browser) | Ferry reads the open tabs and opens new ones through AppleScript. | The first time Ferry reads or opens tabs in a given browser. |
| **Local Network** | FaviconSync and Ghosts need it to reach bookmarks pointing to devices on your network (router, NAS…). | When such a bookmark is checked. |

To grant Full Disk Access: **System Settings › Privacy & Security › Full Disk Access**, add Navloom with the **+** button, turn it on, then relaunch Navloom.

## 🔒 Privacy

Navloom collects nothing and sends nothing about you. There is no account, no analytics and no tracking. The only network requests are those of FaviconSync and Ghosts, sent directly to the websites of your own bookmarks to fetch their icons or check that they respond. Navloom only reads your bookmarks, your icons and a few browser settings (profile names, sync status).

## 📥 Installation

1. Download `Navloom-x.y.z.dmg` from the [latest release](https://github.com/Yohan-Janolin/MacOS_Navloom/releases/latest).
2. Open it and drag **Navloom** onto the **Applications** folder.
3. Launch Navloom from your Applications folder.

> [!WARNING]
> **Navloom isn't notarized by Apple.** It's signed with the author's own certificate, not with a paid Apple Developer account, so macOS blocks it the first time it's opened. This is expected; you only need to allow it once:
>
> 1. Open Navloom: macOS says it can't verify it. Click **Done**.
> 2. Open **System Settings › Privacy & Security** and scroll down to the **Security** section.
> 3. Next to the message about Navloom, click **Open Anyway**, then confirm with your password.
>
> On macOS 14 (Sonoma) you can instead Control-click the app and choose **Open**.
>
> If you prefer the Terminal: `xattr -dr com.apple.quarantine /Applications/Navloom.app`
>
> You can check that the download is genuine by comparing its SHA-256 checksum (`shasum -a 256 Navloom-x.y.z.dmg`) with the one given in the release notes.

## 🔄 Updating

Automatic updates will come in a future version. In the meantime, download the new DMG from the [releases page](https://github.com/Yohan-Janolin/MacOS_Navloom/releases) and replace the app in your Applications folder.

Your permissions (Full Disk Access, Automation) are kept from one version to the next, because every version is signed with the same certificate. Your settings and backups are kept too.

## 📝 Changelog

### 0.1.0
- First public version: FaviconSync, Twins, Ghosts, Echo and Ferry, backups and restore, English and French.

## 🛠️ Building from source

Requirements: a recent version of Xcode (the project uses the Xcode 27 format) and macOS 14.6 or later.

```bash
git clone https://github.com/Yohan-Janolin/MacOS_Navloom.git
cd MacOS_Navloom
open Navloom.xcodeproj
```

Choose the **Navloom** scheme and **My Mac**, then **Product › Run** (⌘R). Tests run with **Product › Test** (⌘U).

The project is signed with the author's certificate, which you don't have: in the target's **Build Settings**, set **Code Signing Identity** to **Sign to Run Locally** (or to your own certificate).

To build a DMG like the published ones, `scripts/make-dmg.sh` archives the app, checks its signature and creates the disk image. It needs [create-dmg](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`) and a signing certificate, whose name is set at the top of the script.

## 🤝 Contributing & issues

Bug reports, ideas and pull requests are welcome!

- **Found a bug?** [Open an issue](https://github.com/Yohan-Janolin/MacOS_Navloom/issues/new) with your macOS version, the browser concerned, what you did and what happened. An exported report or a screenshot helps a lot.
- **An idea or a browser to support?** Open an issue to discuss it first.
- **A pull request?** Keep it focused on one change, make sure the tests pass (⌘U), and add the French translation of any new text in `Localizable.xcstrings`.

## ⚠️ Disclaimer

Navloom modifies your browsers' files. It always creates a backup before writing, and it was built and tested with care, but it's provided **“as is”, without any warranty**. The author can't be held responsible for any data loss or other damage. Use it at your own risk, and keep your own backups of what matters to you.

Navloom isn't affiliated with Google, Microsoft, Brave, Vivaldi, Opera or any other browser vendor. Their names are used only to describe compatibility.

## 📄 License

Navloom is released under the [MIT License](LICENSE).
