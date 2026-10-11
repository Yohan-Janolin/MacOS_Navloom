# Navloom

<p align="center">
    <img src="https://github.com/Yohan-Janolin/MacOS_Navloom/blob/main/Design/Navloom-icon.svg" width="128" alt="Navloom" />
</p>

[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![macOS 26+](https://img.shields.io/badge/macOS-26_%28Tahoe%29-000000?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![macOS 27+](https://img.shields.io/badge/macOS-27_%28Golden%20Gate%29-000000?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## 💡 Overview

Navloom is a set of tools for Web Browsers on MacOS.

> [!IMPORTANT]
> **Sync Issues:** When Chrome saves bookmarks to your Google account (Settings > In your Google account > Bookmarks), it stores them in a separate file. Navloom reads them: FaviconSync, Twins, and Ghosts include them, marked with a cloud icon. However, they cannot be selected for deletion, as Chrome would simply restore them from the server; you must delete them manually within Chrome. Only your local bookmarks can be deleted via Navloom. If you disable the Bookmarks option in Chrome, it hides the account-based bookmarks, and Navloom ignores them as well (based on the setting Chrome writes to its preferences).

> [!IMPORTANT]
> **Full Disk Access:** On macOS, Chrome, Edge, and Brave (stable versions) protect their data: unless Navloom has Full Disk Access, they do not appear in the list of browsers. Open System Settings > Privacy & Security > Full Disk Access, add Navloom using the "+" button, enable it, and then relaunch Navloom. Other browsers do not require this. Navloom only reads bookmarks, icons, and a few settings (profile names, sync status).

> [!NOTE]
> **Supported Web Browsers:**
>   - Chromium
>   - Google Chrome, Google Chrome Beta, Google Chrome Canary
>   - Microsoft Edge, Microsoft Edge Beta, Microsoft Edge Dev, Microsoft Edge Canary
>   - Brave, Brave Beta, Brave Nightly
>   - Vivaldi, Vivaldi Snapshot
>   - Opera, Opera Air, Opera GX, Opera Developer

## ✨ Features

- **FaviconSync:** Retrieves missing icons (favicons) for your bookmarks and writes them to the browser. The browser must be closed during the writing process.
- **Twins:** Find the bookmarks that point to exactly the same URL and delete the ones you select. The browser must be closed, and bookmark synchronization disabled (see below).
- **Echo:** It compares a browser's favorites with those of one or more other browsers and adds them—along with their icons—to the destination browser. Backups are created beforehand.
- **Ghosts:** Open each bookmark to identify those where the page no longer exists (page not found, domain gone, redirect to homepage) and delete the ones you check. You can perform the search while the browser is open, but to delete items, the browser must be closed and bookmark synchronization disabled (see below). Double-click a result to test it in your browser.

## 📦 Getting Started

To build your own copy of the app, please follow the steps below.

### 🚀 Prerequisites

- A Mac running **macOS 14 Sonoma or later**.
- **Xcode 15 or later**.
- An Internet connection to access DeepSeek.
- At least one of the supported Web Browser.

### 🛠️ Build your own copy

1. **Clone the repository:**

    Clone the repository wherever you want.
   ```bash
   git clone https://github.com/Yohan-Janolin/MacOS_Navloom.git
   ```

2. In the `MacOS_Navloom` folder, open **`Navloom.xcodeproj`** in Xcode.
3. In the Xcode toolbar, select the **Navloom** scheme and the **My Mac** destination.
4. To build without launching the app, choose **Product > Build** or press **⌘B**.
5. To build and launch the app, choose **Product > Run** or press **⌘R**.  
    The first build may take a little while. Indexing or App Intents warnings that do not prevent Xcode from reporting **Build Succeeded** can be ignored.
6. Choose **Product > Show Build Folder in Finder**
7. Then open **Products/Debug/Navloom.app**.
8. Move **Navloom.app** to you **Application** folder.



