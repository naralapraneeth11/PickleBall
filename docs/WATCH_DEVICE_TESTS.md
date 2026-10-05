# Apple Watch scoring — device test plan

Watch-owned scoring has to be validated on a **physical, paired iPhone and
Apple Watch** before rollout. Simulators can't reproduce Bluetooth drops,
background suspension, low-power delivery delays or a real crash. CI only
proves that the CourtKit protocol (journal, receipts, gaps, epochs, inbox,
retention) and the build are correct.

Run every scenario on a TestFlight build with the Watch app installed from
that build. Record pass/fail, device models, OS versions and anything
unexpected.

## Setup

- iPhone on iOS 26, Apple Watch on watchOS 26, paired, both on the same
  TestFlight build.
- Signed in on the iPhone. Open the Watch app once so it gets preferences.
- For "offline": put the iPhone in Airplane Mode with Bluetooth **off**,
  or leave it in another room (out of Bluetooth range).
- For "kill": force quit the Watch app (hold the side button → swipe the app
  away), or restart the Watch.

## What "pass" means everywhere

- No rally counted twice and none lost: the iPhone history matches the
  Watch's final score rally by rally (open the match on the iPhone and check
  the rally count).
- While scoring is on the Watch, the iPhone never accepts a scoring tap for
  that match. It shows "This match is scored on your Apple Watch."
- The Watch's sync line reads "Saved on Watch · sync pending" until the
  iPhone confirms, then "Synced to iPhone".

## A. Watch-only scoring

| # | Steps | Expected |
|---|-------|----------|
| A1 | Start a singles match on the Watch with the iPhone nearby. Score 15 rallies, undo twice, finish. | Score buzzes on every tap. The iPhone shows the match live (read-only) and then in history with the same score. The Watch shows "Synced to iPhone". |
| A2 | Repeat A1 with the iPhone **offline** for the whole match. | The Watch scores normally and shows "sync pending". When the iPhone comes back, the match appears in history within a minute of opening either app. |
| A3 | Score 10 rallies offline, **kill** the Watch app, relaunch. | The same match reopens at the same score. Keep scoring, finish, reconnect: the full history arrives. |
| A4 | Score 10 rallies, **restart the Watch**, relaunch the app. | Same as A3. |
| A5 | Pause, try tapping a rally, Resume. | Rally buttons don't count while paused. Resume continues. |
| A6 | Tap × → End without saving. | The match is dropped on the Watch. The iPhone doesn't save a result (an abandoned record at most). |
| A7 | Wearer on team B (put yourself on the right side). | The "US" label is on team B. Winning as team B shows victory. |

## B. Disconnects mid-match

| # | Steps | Expected |
|---|-------|----------|
| B1 | iPhone nearby, score 5 rallies. Go offline, score 10. Come back, score 5, finish. | The iPhone ends up with exactly 20 rallies. |
| B2 | Toggle Bluetooth off/on every few rallies for a 30-rally match. | No duplicates or gaps on the iPhone. |
| B3 | Score offline, then **force quit the iPhone app** before reconnecting. Reconnect and open the iPhone app. | The match arrives once the iPhone app runs. |
| B4 | Finish offline, then wait 30 minutes with the Watch app in the background before reconnecting. | It arrives after reconnecting (background delivery may wait until an app is opened). |

## C. Several matches before syncing

| # | Steps | Expected |
|---|-------|----------|
| C1 | iPhone offline. Play and finish 3 short matches on the Watch, tapping Done after each. | The Watch idle screen says "3 matches waiting for iPhone". Done never deletes. |
| C2 | Reconnect. | All 3 matches appear in iPhone history in order with the right scores. The waiting count goes to 0. |
| C3 | Repeat C1 with 5 matches and kill the Watch app between matches. | Same as C2. |

## D. Handing a match from the iPhone

| # | Steps | Expected |
|---|-------|----------|
| D1 | Set up a match on the iPhone, tap "Score on Apple Watch" with the Watch app open. | The sheet reads "Getting your Watch ready…", then "Ready on Watch" (only after the Watch saved it). The Watch shows "Ready from iPhone". |
| D2 | Tap Start on Watch (on the iPhone). | The sheet reads "Scoring on Watch". The Watch shows the score. The iPhone can't score it. |
| D3 | Like D1, but tap "Start on Watch" on the **Watch** instead. | The iPhone sheet moves to "Scoring on Watch". |
| D4 | Tap Start on Watch with the Watch **unreachable**. | The sheet stays on "Starting on Watch…", even after closing and relaunching the iPhone app. Phone scoring doesn't come back by itself. When the Watch gets the grant, it starts. |
| D5 | In D4, tap "Take the match back" before the Watch gets the grant, then bring the Watch back. | The Watch accepts the cancel (no rally scored) and the iPhone clears the handoff. |
| D6 | Start on Watch, score 1 rally, then tap "Take the match back" on the iPhone. | The Watch refuses. The iPhone says "Your Watch has already started scoring this match." and keeps showing it on the Watch. |
| D7 | Watch already scoring match X; hand match Y from the iPhone and Start. | The iPhone says "Your Watch is busy with another match." Match X continues untouched. |
| D8 | Watch app not installed. | The sheet says so and offers scoring on the iPhone instead. |

## E. Accounts and versions

| # | Steps | Expected |
|---|-------|----------|
| E1 | Play a Watch match while account A is signed in on the iPhone. Before it syncs, sign out and sign in as B. Reconnect. | The match doesn't appear for B. Sign back in as A: it appears. |
| E2 | Update the iPhone app mid-match (TestFlight), keep scoring on the Watch. | Nothing lost. |
| E3 | Update the Watch app mid-match (a match started on the previous build). | The match moves into the journal at the same score. |

## F. Stress

| # | Steps | Expected |
|---|-------|----------|
| F1 | Tap rallies as fast as possible for 60 taps. | Every tap is counted once, in order. |
| F2 | Watch storage nearly full. | If a save fails, the Watch shows "Couldn’t save on this Watch…" and the score doesn't change. It never shows a score that wasn't saved. |
| F3 | Low Power Mode on both devices for A2 and C1. | Same results, delivery may be slower. |

## G. Workout (HealthKit)

| # | Steps | Expected |
|---|-------|----------|
| G1 | Deny Health access on the Watch, then play a match. | Scoring works normally. Workout settings say Health access is off. No workout in Health. |
| G2 | Workout settings → Record workout off ("Score only"). Play a match. | No HealthKit session (no green workout icon). The match syncs as usual. |
| G3 | Indoor court on, play a pickleball match. | Health → Workouts shows one Pickleball workout, marked Indoor. |
| G4 | Play with the iPhone nearby and the scoreboard open on it. | The iPhone shows heart rate and calories under the score with a "… ago" time that stays within about 10 s. |
| G5 | Pause the match on the Watch for 2 minutes, resume, finish. | The workout's duration in Health leaves out the pause. The iPhone line shows Paused while paused. |
| G6 | Mid-match, force quit the Watch app (the workout keeps running), relaunch. | The same workout continues (one workout in Health, not two). The score is the same. |
| G7 | Finish a match and force quit the Watch app while "workout details finishing" shows. | On relaunch the iPhone still gets the summary. There's at most one workout in Health for the match. |
| G8 | Start Apple's Workout app during a PickleBall match. | The Watch says "Workout recording stopped; scoring continues." Scoring carries on and the match syncs. Whatever was recorded is saved. |
| G9 | Restart the Watch mid-match. | The match reopens at the same score. A new workout starts; nothing is counted twice in the match. |
| G10 | Play 3 matches in a row. | Exactly 3 workouts in Health, one per match, each with its summary on the iPhone. |

## Sign-off

Rollout needs **all of A–E and G passing on at least two Watch models** (one
older, e.g. Series 6/SE, and one current), plus F1 and F2. Open an issue
for any failure with the device logs (Settings → Privacy → Analytics Data)
and the steps.
