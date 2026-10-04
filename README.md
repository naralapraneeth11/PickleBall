# PickleBall

Pickleball and padel for iPhone and Apple Watch: score on your wrist or
type it in later, friends confirm every result, and the Belt goes to
whoever beats the holder. Friends only. Nothing is ever public.

Setting up the backend: **[docs/SETUP.md](docs/SETUP.md)** · Launch steps:
**[docs/LAUNCH_CHECKLIST.md](docs/LAUNCH_CHECKLIST.md)** · Store listing:
**[docs/APP_STORE.md](docs/APP_STORE.md)** · Security review:
**[docs/SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md)**.

## Layout

```
Packages/CourtKit/            Shared Swift package (phone, Watch, widget), Foundation only
  Core/                       Team, Sport, PlayerID / PlayerRef / Lineup
  Engine/                     SportEngine protocol + engines, MatchScorer (rally log, undo by replay)
  Sync/                       Phone ⇄ Watch rally-event protocol (SyncMessage, MatchReplica)
  Journal/                    Watch-owned scoring: operation journal, receipts, grants, MatchCoordinator
  Health/                     Heart-rate zones, WorkoutReport
  Insights/                   MatchResult, head-to-head, partners, form line, serve stats
  Social/                     Belts, call outs, score entry, drama, Replays, Feed rules,
                              crowd taps, team shuffle, share cards, usernames, content filter,
                              squad ladder, nudges, belt widget snapshot
  Insights/ (also)            Levels per sport, season recap
  Tournaments/                Round robin, King of the Court, Americano, Mexicano,
                              knockout and double elimination brackets, pools, standings
  LiveActivity/               Live Activity payload + attributes
  DesignSystem/               Palette, sport themes, press style, haptics, court art, sport switch
Packages/CourtNet/            Backend client (iPhone only)
  CourtNetCore/               Wire rows, chat events, match upload/download, offline outbox,
                              invite links, the SocialAPI protocol (Foundation only)
  CourtNet/                   SocialAPI over the Supabase Swift SDK, Realtime, Sign in with Apple
supabase/
  migrations/                 Schema, row-level security, functions, storage, Realtime
  ci-tests/                   Runs the migration on plain Postgres and tests every policy
PickleBall/                   iPhone app (Xcode synchronized folder), String Catalog (en/es/pt-BR/it)
  App/                        Entry point, sign-in gate, five tabs
  Social/                     Social: session, friends, squads, chats, matches, Feed, live, cache
  Launch/                     Telemetry (daily ping, MetricKit), nudges, belt widget bridge
  Model/                      SwiftData records, stores, player directory
  Scoring/                    MatchCenter, live scoreboard, match setup, Live Activity
  Connectivity/               WatchConnectivity (phone side)
  Features/                   Account, Play, Chats, Me (Profile), Tournament, Feed, Stats, Settings
Pickleball watch Watch App/   Watch app: scoring, setup, workout + heart-rate zones, crowd taps
ScoreActivityWidget/          Live Activity / Dynamic Island, and the Belt widget
web/                          Cloudflare Pages site: invite links, live scoreboard, privacy, terms, support
```

## The app

Five tabs, opening on **Play**:

| Play | Chats | Me | Tournaments | Feed |
| --- | --- | --- | --- | --- |
| Start a Watch or phone match, enter a score, results to confirm, call outs, upcoming matches, friends live | Friend and squad chats with the belt pinned on top, friends, requests, squads and their ladder | Your player card: form line, level per sport, record, belts, trophy case, season recap, settings | Round robin, King of the Court, Americano, Mexicano, knockouts and pools, with brackets and a live page to share | Replays across the top, friends' Serves below |

## How scoring works

- Scoring is per rally. The UI records "team A won the rally" and the engine works out points, side-outs, server number, serve rotation and end changes.
- Each engine (`PickleballSideOutEngine`, `PickleballRallyEngine`, `PadelEngine`) is a set of pure functions over value-type state. `MatchScorer` folds the rally log through the engine; undo replays the log without its last rally.
- The rally log is persisted in SwiftData after every rally and uploaded with the match, so any score, stat, head-to-head or Replay can be rebuilt from it.
- Scores typed in later are checked against the format (`ScoreEntry`) before they're saved.

## Phone ⇄ Watch sync

**Watch-owned matches** (started on the Watch, or handed over from the iPhone) use the journal protocol in `CourtKit/Journal`. The Watch is the only device that can add to the match. Each tap becomes an operation with a match ID, event ID, owner device, authority epoch and a sequence number that only goes up. The Watch saves it to disk before it buzzes. Operations go to the iPhone in batches (right away when it's reachable, otherwise as one queued transfer). The iPhone saves them in order and replies with a receipt for the highest sequence it holds with no gaps. It asks for anything missing and parks operations for a match it doesn't know yet until the manifest arrives. Duplicates are ignored and conflicting operations never replace saved ones. The Watch resends until the receipt covers the whole match, so disconnects, crashes and late delivery lose nothing and count nothing twice. Several finished matches can wait on the Watch. Done hides a result but never deletes it.

Handing a match from the iPhone goes draft → "Ready on Watch" (only once the Watch has saved it) → the player taps Start → scoring grant → the Watch accepts. After Start, the iPhone doesn't take scoring back on a timeout. Only a cancel the Watch accepts (before any rally) returns it. Physical-device acceptance tests are in [docs/WATCH_DEVICE_TESTS.md](docs/WATCH_DEVICE_TESTS.md).

**Phone-owned matches** use the older protocol. The phone is the **host** and owns the rally log. The Watch is a **client**: its taps show immediately and go to the host as intents. The host accepts an intent only if it was made on top of the host's current log. If two people tap the same rally on two devices at once, the host rejects the duplicate, so the rally counts once. Devices send rally events, never score snapshots, and both replay the same log through the same engine. Crowd taps from friends reach the Watch as `crowd` messages and play at most one chant every few seconds.

## Accounts, sharing and privacy

- Sign in with Apple is required. A player's ID is their account ID; guests are IDs too and can claim their matches with a link.
- Every result is confirmed by the other side (`save_match` / `confirm_match`). The Belt is never stored: `BeltLedger` folds confirmed matches, so every phone derives the same holder.
- Row-level security is the only privacy layer: friends see friends; squads see their squad; Serves are friends only. `supabase/ci-tests` checks each rule as real users.
- Offline first: every screen reads a local cache; results, confirmations, messages and Returns go through an outbox that sends in order when there's signal.
- Report, block and a content filter everywhere people can post; photos and videos are checked with SensitiveContentAnalysis on the device.

## Tests

```sh
swift test --package-path Packages/CourtKit     # engines, sync, belts, formats, drama…
swift test --package-path Packages/CourtNet     # wire format, outbox, invite links
supabase/ci-tests/run.sh                        # schema + policies on Postgres (Docker)
```

CI (`.github/workflows/ci.yml`) runs all three on Linux and builds the iPhone app (with the Watch app and widget) and the Watch app on macOS.
