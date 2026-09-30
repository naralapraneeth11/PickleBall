# Security review (before real users)

Reviewed every table, policy, function and storage rule in
`supabase/migrations/20260927000000_social_core.sql`, thinking like a
signed-in user with the anon key and a copy of the app's requests. Fixes
are in `20261001000000_launch.sql`; each has a test in
`supabase/ci-tests/20_launch_test.sql`.

| # | Finding | Risk | Fix |
|---|---|---|---|
| F1 | A guest's creator could `update players set claimed_by = <anyone>` | Hand your guest's matches (and belts) to someone else | Only `display_name` is updatable; claims go through `redeem_invite` |
| F2 | `confirm_match(events)` posted any JSON as a chat event | Forged "result"/"call out" events in someone's chat | Only `belt` events, at most 6, under 4 KB, stamped with the match |
| F3 | `save_match` trusted `fixture_id` / `callout_id`; added fixtures could carry a `match_id` | Attach a result to another squad's tournament or someone's call out | Fixture must belong to the tournament, call out must involve you; fixtures insert unlinked and only with entrants |
| F4 | `create_callout` trusted `challengers` and `squad_id` | Call out on someone else's behalf, into a squad you're not in | Caller must be a challenger, partner a friend, squad a squad you're in |
| F5 | `complete_tournament` crowned anyone | Trophies for outsiders | Champions must be entrants |
| F6 | Update policies covered every column (profiles, squads, fixtures, replays, live matches) | Rewrite ownership, bookkeeping, un-expire Replays | Column-level update grants; Replays start unsaved and expire within 25 h; saving goes through `save_replay` |
| F7 | Chat photos were readable by all of the sender's friends | Private DM photos visible outside the chat | `<user>/chat/<conversation>/…` readable only by that chat's members |
| F8 | Crowd taps went over a public Realtime channel | Anyone with the anon key could spam taps into a match | Private channel `crowd-<match>` with a Realtime Authorization policy (who can see the live match) |
| F9 | No cap on outgoing friend requests | Request spam | 50 pending at a time |
| F10 | No way to stop an abusive account | — | Bans: `bans` table, restrictive RLS on every write, `assert_active()` in RPCs, Auth `banned_until` + sessions revoked |

Checked and fine: profiles aren't listable (search is an RPC returning a
minimal card); blocked users disappear from every read; internal helpers
live in the unexposed `private` schema and the write-steps aren't
executable by clients; `anon` can only call `public_scoreboard`, `ping`
and `report_crash`; the public scoreboard exposes first names only and no
account IDs; analytics and crash tables are write-only and hold no
account link.

**Before launch, in the Supabase dashboard:** enable "Realtime → Private
channels only",
set Auth rate limits to defaults, and run the Security Advisor (it should
report nothing).
