# NotchLive

Shows your iPhone's Live Activities around the MacBook notch, like a Dynamic Island.

macOS already mirrors iPhone Live Activities into the menu bar. NotchLive takes the same data and draws it beside the camera housing instead: the compact leading view on the left of the notch, the compact trailing view on the right, and the expanded view below the notch when you hover.

## How it works

When an iPhone Live Activity is mirrored to the Mac, the iPhone sends a pre-rendered archive of every presentation of that activity (compact leading, compact trailing, minimal, expanded, Lock Screen). macOS stores it here:

```
~/Library/Group Containers/group.com.apple.chronod/chronod/remoteArchives/…/activities/*.activity-archive
```

NotchLive watches that folder with FSEvents, decodes the newest archive with the system's own decoder (`WidgetKit.ActivityArchivedViewCollection`, a non-public type), and places the resulting SwiftUI views around the notch using [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit).

Because it reads the archive rather than capturing the screen:

- No Screen Recording or Accessibility permission is needed.
- The app only does work when the iPhone sends an update.
- The views are the real ones designed by the iPhone app for the Dynamic Island, not a screenshot of the menu bar.

## Behaviour

- **No activity:** nothing is shown.
- **Activity running:** compact views sit on both sides of the notch.
- **Hover over the notch:** the expanded view opens below it. A faint power button in its corner quits the app.
- **Alerting update:** when the iPhone app marks an update as an alert (the signal that expands the Dynamic Island on iPhone), the expanded view opens by itself for 6 seconds.

NotchLive adds nothing to the menu bar and has no Dock icon.

## Requirements

- A MacBook with a notch.
- macOS 26 or later. Developed and tested on macOS 27.2 only.
- Xcode 27.2 (Swift 6.4) to build.
- iPhone Mirroring set up, with **System Settings → Notifications → Allow Live Activities from iPhone** turned on.

## Build and run

```sh
git clone https://github.com/ErcouldnT/NotchLive.git
cd NotchLive
swift run
```

## Limitations

- **Private API.** The archive format and the WidgetKit types used to decode it are undocumented. `PrivateInterfaces/` contains a hand-written Swift interface for them, and `ArchiveDecoding.swift` looks up a few symbols by mangled name. Any macOS update can break this, and the app cannot be distributed on the Mac App Store.
- Tested with a single app (SofaScore) so far. Nothing in the code is app-specific, but other apps are unverified.
- With several activities running, only the most recently updated one is shown.
- The system's own menu bar item stays where it is. Turning it off in System Settings would also stop the archives from arriving.
- Clicking the notch does not open the app in iPhone Mirroring.
- Activities created by Mac apps (macOS 27.3) are not shown, only ones mirrored from the iPhone.
- Apple silicon only (the call shim in `Sources/CShim` is arm64 assembly).

## Project layout

| Path | Purpose |
|---|---|
| `Sources/NotchLive/ActivityStore.swift` | Watches the archive folder and publishes the newest activity |
| `Sources/NotchLive/ArchiveDecoding.swift` | Decodes an archive into SwiftUI views with the system decoder |
| `Sources/NotchLive/NotchController.swift` | Notch states: hidden, compact, expanded |
| `Sources/CShim/shim.s` | Calls a Swift protocol-extension static method by symbol |
| `PrivateInterfaces/` | Hand-written interface for the non-public WidgetKit API |
