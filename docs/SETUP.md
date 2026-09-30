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

Open **SQL Editor → New query** and run each migration, in order:

1. `supabase/migrations/20260927000000_social_core.sql`
2. `supabase/migrations/20261001000000_launch.sql` (security fixes,
   moderation, anonymous launch numbers, share links, new tournament formats)

Enable the `pg_cron` extension first (**Database → Extensions**) so old
usage pings are purged automatically.

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

## 5. The web site (invite links, live scoreboards, privacy policy)

`web/` is a static site for Cloudflare Pages: invite links, the live
scoreboard behind share links, the privacy policy, terms and support.

1. Cloudflare → **Workers & Pages → Create → Pages → Connect to Git**.
2. Build command `bash web/build.sh`, output directory `web`.
3. Environment variables: `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
   `APP_STORE_URL`, `SUPPORT_EMAIL` (optional `ANDROID_URL`).
4. Put the site's address in `SITE_URL` in `Secrets.plist`.

Without it, invite links use the `pickleball://` scheme (works between
people who have the app) and live sharing is off.

## 6. Capabilities to check in Xcode

The app target's entitlements already include:

- **Sign in with Apple**
- **HealthKit** (Apple Watch workouts)
- **App Groups** `group.ME.PickleBall` (app and widget: the belt widget
  reads its data from the shared container)
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

Make yourself an admin (after signing in once):

```sql
insert into private.admins (user_id)
select id from auth.users where email = 'you@example.com';
```

Then **Me → Settings → Moderation** in the app shows the report queue
(dismiss, remove the content, or ban the author), the ban list, and the
launch numbers: top countries, weekly return rate and crashes.

## Tests

```sh
supabase/ci-tests/run.sh    # schema, policies and functions on Postgres (needs Docker)
```

CI runs this on every push, along with the CourtKit and CourtNet tests
and the iOS and watchOS builds.
