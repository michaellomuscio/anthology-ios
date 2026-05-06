# Contributing

## Setup

```bash
git clone <your-fork-url>
cd anthology-ios
brew install xcodegen
cp local.xcconfig.example local.xcconfig
# Edit local.xcconfig: set DEVELOPMENT_TEAM to your Apple Team ID
xcodegen generate
xed .
```

The Xcode project is **regenerated from `project.yml`**. The `.xcodeproj`
is gitignored — never commit it.

## Build from CLI

```bash
xcodebuild -project Anthology.xcodeproj \
  -scheme Anthology \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build
```

## Architecture

See the **Architecture** section of the [README](README.md). Key files:

- `Anthology/Networking/BridgeClient.swift` — WebSocket lifecycle
- `Anthology/Networking/BridgeStore.swift` — `@MainActor` ObservableObject
- `Anthology/Models/BridgeMessage.swift` — protocol mirrors

## What changes are welcome

- Bug fixes
- iOS-version compatibility improvements (target is iOS 17+)
- Accessibility improvements
- Performance fixes for terminal rendering on older devices
- Localization (currently English only)

## What probably won't be accepted

- Major architectural rewrites without prior discussion
- New third-party dependencies beyond SwiftTerm
- Anything that weakens the Keychain attribute on token storage

## Coding style

- Swift 5.9+ syntax
- Four-space indentation (matches Xcode default)
- Comments only when explaining *why*
- Prefer `@MainActor` for SwiftUI-touching code; explicit isolation for the rest
- Match the existing file's structure

## License

By contributing, you agree your changes are licensed under Apache 2.0.
