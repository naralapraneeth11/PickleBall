# Launch checklist: what you set up

Everything in the code is done or in progress on the branch. These are the
steps only you can do, in the order that unblocks the most. Tick them off
as you go.

> Note on media: the spec says "R2 media". The app stores photos and videos
> in **Supabase Storage** (buckets `avatars` and `media`), and account
> deletion removes them there. You don't need Cloudflare R2.

## 1. Supabase (about 30 minutes)

- [ ] Create the project at supabase.com. **Region: Central EU (Frankfurt)**:
      Spain, Portugal and Italy are the likely first markets and GDPR prefers
      EU hosting. Save the database password somewhere safe.
- [ ] **Project Settings → API**: copy the **Project URL** and the **anon public**
      key. (Never put the `service_role` key in the app or the web site.)
- [ ] **Database → Extensions**: enable `pg_cron` (for the 13-month telemetry
      purge). `citext` and `pgcrypto` are turned on by the migration.
- [ ] Run the migrations **in order** in the SQL editor (or with
      `supabase db push`):
  1. `supabase/migrations/20260927000000_social_core.sql`
  2. `supabase/migrations/20261001000000_launch.sql`
- [ ] Never run anything from `supabase/ci-tests/` against the real project:
      it replaces `auth.uid()` for testing.
- [ ] **Authentication → Providers → Apple**: turn it on. For a native iOS app
      only the bundle ID `ME.PickleBall` is needed under "Client IDs". (The
      Services ID and secret key are only needed for web sign-in, which we don't use.)
- [ ] **Authentication → Rate Limits**: leave the defaults.
- [ ] **Realtime → Settings**: turn on **"Private channels only"** (crowd taps
      use a private channel now).
- [ ] **Storage**: check that the `avatars` (public) and `media` (private) buckets
      exist. The migration creates them.
- [ ] Make yourself an admin. Sign in to the app once, then run:
      ```sql
      insert into private.admins (user_id)
      select id from auth.users where email = 'YOUR-APPLE-ID-EMAIL';
      -- or, if you hid your email from Apple: find your id in Authentication → Users
      ```
      Moderation then shows up in the app under Me → Settings.
- [ ] **Advisors → Security Advisor**: run it. It should report nothing
      critical.

## 2. Secrets for the app (5 minutes)

Without this file the app runs in scoring-only mode: Chats, Tournaments and
the Feed show "Needs the PickleBall server", and QR codes, Serves and
Returns can't be made. That's what you see in the simulator today.

- [ ] Copy `Secrets.example.plist` to `PickleBall/Secrets.plist` and fill in:
      `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SITE_URL` (your Cloudflare Pages
      address, step 4). The file is git-ignored.

## 3. Apple Developer (about 30 minutes)

- [ ] Apple Developer Program membership (99 USD a year), team `3A8H924A89`.
- [ ] **Identifiers → App IDs**: for `ME.PickleBall` turn on **Sign in with
      Apple**, **HealthKit**, **App Groups** (`group.ME.PickleBall`) and
      Push Notifications (optional, for later). For
      `ME.PickleBall.ScoreActivity` (the widget) turn on **App Groups** with the
      same group. Xcode's automatic signing can do this for you the first time
      you build to a device.
- [ ] Create the App Group `group.ME.PickleBall` if Xcode hasn't already. The
      belt widget reads its data from there.
- [ ] Build and run on your own iPhone once: sign in, create a profile, score a
      match, add the Belt widget, and check Settings → Nudges.

## 4. Cloudflare Pages: the web site (15 minutes)

- [ ] Cloudflare account (free) → **Workers & Pages → Create → Pages → Connect
      to Git** → this repository.
- [ ] Build settings: **Framework preset** None · **Build command**
      `bash web/build.sh` · **Build output directory** `web` · **Production branch** `main`.
- [ ] **Environment variables** (Production and Preview):
  - `SUPABASE_URL`: same as the app
  - `SUPABASE_ANON_KEY`: same as the app
  - `APP_STORE_URL`: your TestFlight public link now, the App Store link later
  - `SUPPORT_EMAIL`: an address you actually read
  - `ANDROID_URL`: leave empty (the banner tells Android visitors "on the way")
- [ ] Deploy, then open `https://<project>.pages.dev/privacy/`, `/terms/`,
      `/support/` and check them.
- [ ] Put that address in `SITE_URL` in `Secrets.plist` (step 2). Share links,
      invite links and the in-app privacy and terms links all use it.
- [ ] Optional: a custom domain (Pages → Custom domains).

## 5. App Store Connect (about an hour)

Copy the texts from `docs/APP_STORE.md` (being written).

- [ ] Create the app: name, primary language English (U.S.), bundle ID
      `ME.PickleBall`, SKU. Category **Sports**, secondary **Health & Fitness**.
- [ ] **Localizations**: add Spanish (Spain), Spanish (Mexico), Portuguese
      (Brazil), Portuguese (Portugal) and Italian, and paste the translated name,
      subtitle, description, keywords and promotional text.
- [ ] **Privacy Policy URL**: `https://<site>/privacy/` · **Support URL**: `https://<site>/support/`.
- [ ] **App Privacy** (privacy labels), answered as in `docs/APP_STORE.md`:
      no tracking. *Linked to you* (App Functionality): name, user ID, photos or
      videos, messages, other user content, fitness, health, coarse location
      (court tags). *Not linked to you* (Analytics): crash data, performance
      data, product interaction, device ID.
- [ ] **Age rating**: answer "Infrequent/Mild" for nothing; say **Yes to
      user-generated content with moderation** (report, block and a reviewed
      queue). Expected rating: **13+**.
- [ ] **Sign in with Apple** needs no extra review notes. In **App Review
      Information**, give a demo account (see step 6) and explain that results
      need a friend to confirm them.
- [ ] Screenshots: 6.9" iPhone (required), plus Apple Watch. English first,
      then es/pt/it.

## 6. TestFlight beta, about 50 outside testers (1 to 2 weeks)

- [ ] Archive in Xcode (Product → Archive) → Distribute → App Store Connect.
- [ ] **TestFlight → Internal testing**: add yourself, and install and smoke-test.
- [ ] Make two demo accounts (two Apple IDs) that are friends, so the reviewer
      can confirm a match.
- [ ] **External testing** group "Beta": fill in "What to test" (in
      `docs/APP_STORE.md`), submit for Beta App Review (usually 1 day).
- [ ] Turn on the **public link** and share it with about 50 players in 2 or 3
      countries (a Spanish padel club, an Italian padel group, a US pickleball
      group). Put the link in `APP_STORE_URL` on Cloudflare.
- [ ] Each week: open Moderation → Numbers in the app for crashes, countries and
      return rate, and read TestFlight feedback.

## 7. Launch worldwide

- [ ] Fix whatever the beta found, then submit the build for App Review with all
      territories selected.
- [ ] After release: set `APP_STORE_URL` on Cloudflare to the App Store link and
      redeploy.
- [ ] **Done when**: 30 days after launch, Moderation → Numbers shows your top
      3 countries (last 30 days) and the weekly return rate.

## Good to know

- **Support email**: Apple and GDPR both expect a working contact. Use the
  same address in `SUPPORT_EMAIL`.
- **Legal pages** (`web/privacy`, `web/terms`) are written for this app but
  aren't legal advice; have someone check them before launch if you can.
- **Free tiers**: Supabase Free (500 MB database, 1 GB storage, pauses after a
  week without traffic; move to Pro, 25 USD a month, before launch so it never
  pauses), Cloudflare Pages Free (unlimited static traffic), MetricKit and the
  built-in pings (free, no third-party SDK).
