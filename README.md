# Anthology iOS

Companion iPhone app for [Anthology](https://github.com/michaellomuscio/anthology) on macOS.
View and control Claude Code sessions from your phone.

## Requirements

- Xcode 16+
- iOS 17+ device or simulator
- Anthology 0.2.0+ on your Mac
- [Tailscale](https://tailscale.com) on both devices for use away from your Wi-Fi (free)

## Build

```bash
brew install xcodegen
xcodegen generate
xed .
```

Or build from the command line:

```bash
xcodebuild -scheme Anthology -destination 'generic/platform=iOS Simulator,name=iPhone 16'
```

## Architecture

Files are flat under `Anthology/`. Xcode project regenerates from `project.yml`.

```
Anthology/
├── AnthologyApp.swift          App entry; injects BridgeStore
├── Models/                     Codable mirrors of the bridge protocol
├── Networking/
│   ├── BridgeClient.swift      WebSocket task wrapper, request/response, heartbeat
│   ├── BridgeStore.swift       @MainActor ObservableObject for SwiftUI
│   └── PairingClient.swift     POST /pair
├── Storage/
│   ├── KeychainStore.swift     Bearer token (one slot per paired Mac)
│   └── ServerStore.swift       Server metadata in UserDefaults
└── Views/
    ├── ContentView.swift       Pairing ↔ SessionList router
    ├── PairingView.swift       Manual + QR pairing
    ├── QRScannerView.swift     AVFoundation camera
    ├── SessionListView.swift
    ├── SessionDetailView.swift
    ├── TerminalContainerView.swift   SwiftTerm bridge
    ├── StatusDot.swift
    └── SettingsView.swift
```

The bridge protocol is documented at
`anthology/docs/bridge-protocol.md` in the Mac repo.
