# PickleBall

Native **iOS + Apple Watch** PickleBall app (Xcode / SwiftUI + SpriteKit).

## Open in Xcode

1. Clone this repo
2. Open `PickleBall.xcodeproj`
3. Select your Team under Signing & Capabilities
4. Build & run on iPhone / Watch simulator or device

## Structure

| Path | Description |
|------|-------------|
| `PickleBall/` | iOS app target (entry + assets) |
| `Pickleball watch Watch App/` | watchOS companion |
| `*.swift` (root) | Screens, match logic, tournaments, Watch connectivity |
| `Onboarding/` | Onboarding flow |
| `PickleBallTests/` / `*UITests/` | Unit & UI tests |

## Notes

- Private repo for version control and backup
- Do not commit signing certificates or API secrets
- `xcuserdata` is gitignored (personal Xcode state)
