# Security policy

## Reporting a vulnerability

Please **do not** open a public GitHub issue for a security report. Instead,
open a [private security advisory](https://github.com/michaellomuscio/anthology-ios/security/advisories/new) on this repo.

Include:

- A description of the issue
- Steps to reproduce on a clean simulator install
- Impact: what an attacker can do, what trust boundary they cross
- Your name / handle if you'd like credit in the fix's release notes

You'll get a response within ~5 business days.

## Supported versions

Only the latest TestFlight build is supported. Older builds may have known
issues that have since been patched.

## Threat model

The iOS app pairs with one Mac at a time and stores a long-lived bearer
token in iOS Keychain. The token is the only thing standing between an
attacker on the same network as the Mac and remote control of that Mac's
Claude sessions.

### Trust assumptions

- iOS itself is trusted (sandbox, Keychain, code signing)
- The Apple ID signing the build is trusted
- The paired Mac is trusted by the iOS user
- The network layer between iOS and the Mac (Tailscale's WireGuard, or
  trusted LAN) provides confidentiality — the WebSocket is plaintext

### In scope (please report)

- Bearer token leak from Keychain to disk, logs, or screen capture
- Pairing-code disclosure beyond the QR / manual entry flow
- WebSocket message injection by anyone other than the paired Mac
- iOS app crash that leaks credentials in a crash report
- Information leak via push-notification payload
- Cross-device session impersonation

### Out of scope

- iOS jailbreak scenarios
- Apple Push Notification Service compromise
- Compromise of the paired Mac (the Mac is trusted; if it's compromised,
  this app's behavior on it isn't a meaningful threat boundary)

## Reproducible builds

The Xcode project is regenerated from `project.yml` via XcodeGen. The
`.xcodeproj` is gitignored. Anyone with the source can rebuild the same
binary by running `xcodegen generate && xcodebuild …`. Code signing is
configured per-team via a gitignored `local.xcconfig` file.
