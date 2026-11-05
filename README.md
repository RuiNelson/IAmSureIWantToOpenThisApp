# I Am Sure I Want To Open This App

A macOS app for opening apps that haven't been notarized, by removing the `com.apple.quarantine` attribute.

## Why

macOS adds the `com.apple.quarantine` attribute to everything you download. Before a quarantined app opens, Gatekeeper checks that it's signed and notarized by Apple. Plenty of legitimate software isn't: open-source projects, indie tools, internal builds, older apps. For those, macOS shows *“can't be opened because Apple cannot check it for malicious software”* or *“is damaged and can't be opened. You should move it to the Trash.”*

Getting past that means a trip to **System Settings ▸ Privacy & Security ▸ Open Anyway** for every app, or running `xattr -dr com.apple.quarantine` in Terminal. This app does the same thing with a drag and drop or a right-click in Finder.

> [!WARNING]
> Removing quarantine skips Gatekeeper's check. Only do it for apps and files you trust, from a source you know.

## Features

- **Free and open source**, and the app itself is notarized
- **Finder Quick Action**: right-click any app or file and choose *Let me open this App*
- **Drag and drop** several apps, files or folders at once; everything inside them is cleared too
- **Works on read-only disk images**: if an item can't be changed in place, it offers to copy it somewhere writable and clear the copy
- **Shows a per-item result**, including what was already clear and what failed
- **Available in 24 languages**
- **Native**: written in Swift and SwiftUI with Liquid Glass, no dependencies

## Requirements

macOS 26 Tahoe or later.

## Installation

Download the latest version from [Releases](https://github.com/RuiNelson/IAmSureIWantToOpenThisApp/releases), unzip it and move **I am sure I want to open this App** to your Applications folder. Open it once and confirm that you understand the risks.

## Usage

- **Drag and drop**: drop apps or files onto the window, or use **File ▸ Select Files...** (⌘O).
- **Dock**: drop items on the app's Dock icon.
- **Finder**: right-click the items and choose **Quick Actions ▸ Let me open this App**.

### Enabling the Finder Quick Action

The Quick Action comes with the app but macOS may leave it off until you turn it on:

1. Open the app once, so macOS registers its extension.
2. In Finder, right-click any file and choose **Quick Actions ▸ Customize...**
3. Turn on **Let me open this App**.

It then appears under **Quick Actions** in Finder's right-click menu and in the Preview pane (**View ▸ Show Preview**).

## Building from source

Open `I am sure/I am sure.xcodeproj` in Xcode 26 or later and run the **I am sure I want to open this App** scheme, or from Terminal:

```bash
xcodebuild -project "I am sure/I am sure.xcodeproj" -scheme "I am sure I want to open this App" -configuration Debug build
```

You'll need to set your own development team and App Group identifier to sign it.

## License

[GPL-2.0](LICENSE)
