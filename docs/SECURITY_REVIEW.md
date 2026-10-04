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

## Release audit fixes (migration 3 and app)

An outside release-readiness audit (October 2026) found the problems
below. Each is fixed and has a regression test: SQL ones in
`supabase/ci-tests/30_hardening_test.sql`, sync ones in
`Packages/CourtKit/Tests/CourtKitTests/MatchReplicaOrderingTests.swift`.

| # | Problem | Fix |
|---|---|---|
| A1 | Profile save and live publishing used upserts that write read-only id columns, so a new user couldn't create a profile | Update without ids, insert only when there's no row (profiles, live matches) |
| A2 | Finishing on the Watch while the phone couldn't hear it threw away the queued rallies | End requests carry unacknowledged taps; the host applies them before ending; the Watch keeps and resends unconfirmed finishes |
| A3 | An older score snapshot could overwrite a newer one | Host revisions (session epoch + counter); clients ignore anything older and re-request on gaps |
| A4 | Signing in as someone else relabelled the previous player's matches | Matches and workouts belong to an account on the phone; signed-out matches move to an account only when the person says they're theirs |
| A5 | Workout and heart-rate data uploaded automatically onto a row friends and squads can read, and kept after deletion | Never uploaded with a match; a check constraint keeps `matches.workout` empty; existing values wiped |
| A6 | A guest could be created already claimed by someone else | Insert policy requires `claimed_by is null` |
| A7 | Blocking didn't hide messages and chat photos in a shared squad | Message and chat-photo reads exclude anyone blocked either way; squad results stay visible to the squad (said in the block dialog) |
| A8 | The server accepted malformed matches, and one bad row stopped everyone's match list loading | `validate_match` checks rules, sport, sides, players, scores, dates and size; the app skips unreadable rows instead of failing |
| A9 | The app's own Realtime channel was public, so "Private channels only" would silently stop live updates | The channel is private with a policy; join failures are retried and shown; squad members and Replays are published |
| A10 | Account deletion couldn't list avatars, didn't page, didn't revoke Sign in with Apple, and left data on the phone | `delete-account` Edge Function (service role, paginated Storage cleanup, Apple revocation); app fallback pages too; the phone removes that account's matches, workouts and cache |
| A11 | "Confirm" showed as final before the server agreed | The match shows "your answer is on its way" until the server's status arrives; share cards and belts wait for it |

Reliability fixes from the same audit: matches and chat history are read
page by page with no cap; becoming friends or joining a squad triggers a
full re-read that also drops matches no longer visible; deleted or
moderated messages disappear from open chats; failed sends wake up on
their own at the retry time; failed disk writes are reported instead of
swallowed.
