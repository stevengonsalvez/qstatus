Q-Status Menubar (Prototype Scaffold)

This is the initial scaffold for a native macOS menu bar app that monitors Amazon Q CLI usage by reading the local SQLite database at `~/.aws/q/db/q.db` in a read-only, non-invasive way.

Status: Menubar app scaffold. Running via SwiftPM now sets `NSApp.setActivationPolicy(.accessory)`, so it behaves like a proper menu bar app (no Dock icon). For distribution, create an Xcode app target and set `LSUIElement=1` in Info.plist, then sign/notarize.

Run (dev):

```
cd q-status-menubar
swift run QStatusMenubar
```

Notes:
- Runs as a true menu bar app in SwiftPM via accessory activation policy; an Xcode target with `LSUIElement` is recommended for release builds.
- DB access is read-only and points to `~/Library/Application Support/amazon-q/data.sqlite3`.
- Notifications are suppressed when running as SwiftPM to avoid UNUserNotificationCenter crash in non-bundled contexts.

Xcode menubar target (recommended for release):
1) Open `q-status-menubar/Package.swift` in Xcode.
2) File → New → Target… → macOS → App. Name: `QStatusMenubar`.
3) In the new target’s Info, add `Application is agent (UIElement)` = YES.
4) Add a new `Info.plist` if needed; ensure `LSUIElement` is set to `1`.
5) Add the Swift files from `Sources/App` and `Sources/Core` to the target.
6) In Signing & Capabilities, set your team and bundle ID.
7) Build & Run. The app will appear only in the menu bar.
