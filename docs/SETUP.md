# Setting up the backend

PickleBall's accounts, friends, chats, belts, tournaments and Feed run on
[Supabase](https://supabase.com). Scoring works without it; everything
social needs it. This takes about 15 minutes.

## 1. Create the Supabase project

1. Sign in at supabase.com and create a project. Pick a region near your
   players and save the database password somewhere safe.
2. When it's ready, open **Project Settings → API** and note:
   - the **Project URL** (`https://xxxx.supabase.co`)
   - the **anon public** key

The anon key is designed to ship inside apps: row-level security, not the
key, decides what each signed-in user can see. Never put the
`service_role` key in the app.

## 2. Create the database

Open **SQL Editor → New query**, paste the whole of
`supabase/migrations/20260927000000_social_core.sql`, and run it.

Or, with the Supabase CLI:

```sh
supabase link --project-ref xxxx
supabase db push
```

This creates every table, row-level security policy, function, the
`avatars` (public) and `media` (friends-only) storage buckets, and turns
on Realtime for the tables the app listens to.

> Don't run anything in `supabase/ci-tests/` against your project. Those
> files fake parts of Supabase for CI and would break sign-in.

## 3. Turn on Sign in with Apple

In the Apple Developer portal:

1. **Identifiers → App IDs → ME.PickleBall**: enable **Sign In with
   Apple**. (Xcode's automatic signing usually does this when it sees the
   entitlement.)

In Supabase, **Authentication → Sign In / Providers → Apple**:

1. Enable Apple.
2. Under **Client IDs**, add the app's bundle ID: `ME.PickleBall`.
3. Save. (The app signs in natively with an identity token, so the
   Services ID, key and redirect URL are only needed if you later add Sign
   in with Apple on the web.)

## 4. Give the app its keys

1. Copy `Secrets.example.plist` to `PickleBall/Secrets.plist`.
2. Fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
3. Build and run. `PickleBall/Secrets.plist` is git-ignored.

Without `Secrets.plist` the app still builds and scores matches on the
device, and shows the original onboarding instead of sign-in.

## 5. Invite links (optional but recommended)

Friend, squad and guest-claim links shared outside the app open a small
page with "Open in PickleBall" and "Get PickleBall" buttons:

1. In GitHub: **Settings → Pages → Build and deployment**: deploy from the
   `main` branch, `/docs` folder.
2. Your page is `https://<your-username>.github.io/PickleBall/invite/`.
3. Put that URL in `INVITE_PAGE_URL` in `Secrets.plist`.
4. When the app is on TestFlight or the App Store, set the "Get
   PickleBall" link in `docs/invite/index.html`.

Without it, links use the `pickleball://` scheme, which works between
people who already have the app.

## 6. Capabilities to check in Xcode

The app target's entitlements already include:

- **Sign in with Apple**
- **HealthKit** (Apple Watch workouts)
- **Sensitive Content Analysis**: checks photos on the device before
  they're posted or shown. It only runs when a person has turned on
  Sensitive Content Warning (or Communication Safety) in Settings;
  reporting and blocking always work.

If Xcode reports a provisioning error, open **Signing & Capabilities**
and let it register the capabilities for your team.

## Checking it works

1. Sign in on two phones (or a phone and a simulator) with two Apple IDs.
2. Search one username from the other and send a friend request.
3. Enter a score between you. The other phone gets it under **Play →
   Confirm**; confirm it. The chat now shows the belt.

## Moderation

Reports land in the `reports` table (**Table Editor → reports**). Review
them regularly; App Store Guideline 1.2 expects a way to act on
objectionable content. To remove content, delete the row in `messages`,
`serves`, `returns` or `replays`; to remove a person, delete their user in
**Authentication → Users**.

## Tests

```sh
supabase/ci-tests/run.sh    # schema, policies and functions on Postgres (needs Docker)
```

CI runs this on every push, along with the CourtKit and CourtNet tests
and the iOS and watchOS builds.
