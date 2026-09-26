# PickleBall

Pickleball and padel scoring for iPhone and Apple Watch. Offline, no accounts: everything lives on the device.

## Layout

```
Packages/CourtKit/            Shared Swift package (phone, Watch, widget)
  Core/                       Team, Sport, PlayerID / PlayerRef / Lineup
  Engine/                     SportEngine protocol + engines, MatchScorer (rally log, undo by replay)
  Sync/                       Phone ⇄ Watch rally-event protocol (SyncMessage, MatchReplica)
  Health/                     Heart-rate zones, WorkoutReport
  Insights/                   MatchResult, head-to-head, partners, form line, serve stats
  LiveActivity/               Live Activity payload + attributes
  DesignSystem/               Palette, sport themes, press style, haptics, court art, sport switch
PickleBall/                   iPhone app (Xcode synchronized folder)
  App/                        Entry point, root, tab bar
  Model/                      SwiftData records, stores, player directory, legacy import
  Scoring/                    MatchCenter, live scoreboard, match setup, Live Activity controller
  Connectivity/               WatchConnectivity (phone side)
  Features/                   Home, Stats, Profile (form line, head-to-head), Tournament, Watch stats, Settings
Pickleball watch Watch App/   Watch app: scoring, setup, workout + heart-rate zones
ScoreActivityWidget/          Live Activity / Dynamic Island widget extension
```

## How scoring works

- Scoring is per rally. The UI records "team A won the rally" and the engine works out points, side-outs, server number, serve rotation and end changes.
- Each engine (`PickleballSideOutEngine`, `PickleballRallyEngine`, `PadelEngine`) is a set of pure functions over value-type state. `MatchScorer` folds the rally log through the engine; undo replays the log without its last rally.
- The rally log is persisted in SwiftData after every rally, so any score, stat or head-to-head record can be rebuilt from it.

## Phone ⇄ Watch sync

The device that starts a match is its **host** and owns the rally log. The other device is a **client**: its taps show immediately and go to the host as intents. The host accepts an intent only if it was made on top of the host's current log. If two people tap the same rally on two devices at once, the host rejects the duplicate, so the rally counts once. Devices send rally events, never score snapshots, and both replay the same log through the same engine.

## Players

Every player is a `PlayerID`: the device owner is a user, and people added at the court are guests. Names are display-only, so two people called "Alex" stay separate in history and head-to-head.

## Tests

```sh
swift test --package-path Packages/CourtKit
```

The engine tests replay real game transcripts rally by rally. CI (`.github/workflows/ci.yml`) runs them on Linux and builds the iPhone app (including the Watch app and widget) and the Watch app on macOS.
