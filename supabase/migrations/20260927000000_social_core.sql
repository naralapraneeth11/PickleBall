-- PickleBall Phase 2: accounts, friends, squads, chat, confirmed matches,
-- call outs, squad tournaments, trophies, Replays and the friends-only Feed.
--
-- Design rules
--   • Friends only. Row-level security is the source of truth for who can
--     see what; the app never filters for privacy on its own.
--   • Players are IDs. A user's player ID is their auth user ID; guests
--     are rows in `players` that a user can later claim.
--   • Clients own derived logic (belts, standings, drama). The database
--     stores facts: who played, the score, the rally log, confirmations.
--   • Multi-row changes go through security-definer RPCs so each is one
--     transaction with one permission check.

create extension if not exists citext;
create extension if not exists pgcrypto;

-- Internal helpers (policy checks, triggers, shared RPC steps) live in
-- `private`, which PostgREST does not expose, so none of them is callable
-- as an API endpoint.
create schema if not exists private;

-- ─────────────────────────────────────────────────────────────────────────
-- Profiles and players
-- ─────────────────────────────────────────────────────────────────────────

create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  username      citext unique not null
                check (username::text ~ '^[a-z0-9_.]{3,20}$' and username::text !~ '^[._]|[._]$'),
  display_name  text not null check (char_length(display_name) between 1 and 40),
  avatar_path   text,
  sports        text[] not null default '{pickleball}'
                check (sports <@ array['pickleball','padel']::text[]),
  home_courts   jsonb not null default '[]'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Everyone who can appear in a match: users (id = profile id) and guests.
create table public.players (
  id            uuid primary key default gen_random_uuid(),
  kind          text not null check (kind in ('user','guest')),
  display_name  text not null check (char_length(display_name) between 1 and 40),
  created_by    uuid references public.profiles(id) on delete set null,
  claimed_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  check (kind = 'guest' or claimed_by is null)
);

create or replace function private.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger profiles_touch before update on public.profiles
  for each row execute function private.touch_updated_at();

-- A user's player row mirrors the profile.
create or replace function private.sync_user_player() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.players (id, kind, display_name, created_by)
  values (new.id, 'user', new.display_name, new.id)
  on conflict (id) do update set display_name = excluded.display_name;
  return new;
end $$;

create trigger profiles_player after insert or update of display_name on public.profiles
  for each row execute function private.sync_user_player();

-- ─────────────────────────────────────────────────────────────────────────
-- Friends, blocks, reports
-- ─────────────────────────────────────────────────────────────────────────

create table public.friendships (
  user_a        uuid not null references public.profiles(id) on delete cascade,
  user_b        uuid not null references public.profiles(id) on delete cascade,
  status        text not null check (status in ('pending','accepted')),
  requested_by  uuid not null references public.profiles(id) on delete cascade,
  created_at    timestamptz not null default now(),
  accepted_at   timestamptz,
  primary key (user_a, user_b),
  check (user_a < user_b),
  check (requested_by in (user_a, user_b))
);

create table public.blocks (
  blocker     uuid not null references public.profiles(id) on delete cascade,
  blocked     uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);

create table public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter     uuid not null references public.profiles(id) on delete cascade,
  target_type  text not null check (target_type in ('user','message','serve','return','replay','match')),
  target_id    uuid not null,
  reason       text not null check (char_length(reason) between 1 and 500),
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz
);

create or replace function private.is_blocked(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.blocks
    where (blocker = a and blocked = b) or (blocker = b and blocked = a)
  )
$$;

create or replace function private.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a is not null and b is not null and a <> b
     and not private.is_blocked(a, b)
     and exists (
       select 1 from public.friendships
       where user_a = least(a, b) and user_b = greatest(a, b) and status = 'accepted'
     )
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Squads
-- ─────────────────────────────────────────────────────────────────────────

create table public.squads (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (char_length(name) between 1 and 40),
  created_by       uuid references public.profiles(id) on delete set null,
  -- Crowd-tap rhythm only this squad can send: [{"ms":0,"strength":1.0},…]
  signature_chant  jsonb,
  created_at       timestamptz not null default now()
);

create table public.squad_members (
  squad_id   uuid not null references public.squads(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  role       text not null default 'member' check (role in ('owner','member')),
  joined_at  timestamptz not null default now(),
  primary key (squad_id, user_id)
);

create or replace function private.is_squad_member(s uuid, u uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.squad_members where squad_id = s and user_id = u)
$$;

create or replace function private.share_a_squad(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.squad_members m1
    join public.squad_members m2 on m1.squad_id = m2.squad_id
    where m1.user_id = a and m2.user_id = b
  )
$$;

-- Someone you can see: yourself, a friend, or a squadmate (never if blocked).
create or replace function private.can_see_user(viewer uuid, target uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select viewer = target
      or (not private.is_blocked(viewer, target)
          and (private.are_friends(viewer, target) or private.share_a_squad(viewer, target)))
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Invites: friend links / QR codes, squad links, guest claim links
-- ─────────────────────────────────────────────────────────────────────────

create table public.invites (
  token       text primary key default encode(gen_random_bytes(12), 'hex'),
  kind        text not null check (kind in ('friend','squad','guest_claim')),
  created_by  uuid not null references public.profiles(id) on delete cascade,
  target_id   uuid,            -- squad id or guest player id
  expires_at  timestamptz not null default now() + interval '30 days',
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────
-- Matches
-- ─────────────────────────────────────────────────────────────────────────

create table public.matches (
  id             uuid primary key,             -- generated on device
  sport          text not null check (sport in ('pickleball','padel')),
  rules          jsonb not null,               -- CourtKit MatchRules
  source         text not null check (source in ('watch','phone','entered')),
  created_by     uuid references public.profiles(id) on delete set null,
  status         text not null default 'pending'
                 check (status in ('pending','confirmed','disputed')),
  started_at     timestamptz not null,
  ended_at       timestamptz,
  winner_team    smallint check (winner_team in (0, 1)),
  match_score    smallint[] not null default '{0,0}',
  points         smallint[] not null default '{0,0}',
  units          jsonb not null default '[]'::jsonb,   -- [CompletedUnit]
  rally_winners  text,                          -- "ABBA…" when scored live
  rally_offsets  real[],                         -- seconds from start
  court          jsonb,                          -- {name, lat, lon, mapItemID}
  squad_id       uuid references public.squads(id) on delete set null,
  tournament_id  uuid,
  fixture_id     uuid,
  callout_id     uuid,
  workout        jsonb,                          -- Watch extras (creator's)
  confirmed_at   timestamptz,
  updated_at     timestamptz not null default now(),
  check (rally_winners is null or rally_winners ~ '^[AB]*$')
);

create trigger matches_touch before update on public.matches
  for each row execute function private.touch_updated_at();

create table public.match_participants (
  match_id      uuid not null references public.matches(id) on delete cascade,
  player_id     uuid not null references public.players(id) on delete cascade,
  team          smallint not null check (team in (0, 1)),
  slot          smallint not null check (slot in (0, 1)),
  confirmed_at  timestamptz,
  disputed_at   timestamptz,
  primary key (match_id, player_id),
  unique (match_id, team, slot)
);

create index match_participants_player on public.match_participants(player_id);
create index matches_updated on public.matches(updated_at);

create or replace function private.is_match_participant(m uuid, u uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.match_participants mp
    join public.players p on p.id = mp.player_id
    where mp.match_id = m and (p.id = u or p.claimed_by = u)
  )
$$;

-- Friends-only: a match is visible to its players, their friends, and the
-- squad it was played in.
create or replace function private.can_see_match(m uuid, viewer uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select private.is_match_participant(m, viewer)
      or exists (select 1 from public.matches where id = m and squad_id is not null
                 and private.is_squad_member(squad_id, viewer))
      or exists (
        select 1 from public.match_participants mp
        join public.players p on p.id = mp.player_id
        where mp.match_id = m
          and private.are_friends(viewer, coalesce(p.claimed_by, case when p.kind = 'user' then p.id end))
      )
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Chats
-- ─────────────────────────────────────────────────────────────────────────

create table public.conversations (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('direct','squad')),
  squad_id    uuid unique references public.squads(id) on delete cascade,
  user_a      uuid references public.profiles(id) on delete cascade,
  user_b      uuid references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  last_message_at timestamptz,
  unique (user_a, user_b),
  check ((kind = 'squad' and squad_id is not null and user_a is null and user_b is null)
      or (kind = 'direct' and squad_id is null and user_a < user_b))
);

create table public.messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.conversations(id) on delete cascade,
  sender_id        uuid references public.profiles(id) on delete set null,  -- null = event
  kind             text not null check (kind in ('text','photo','event')),
  body             text check (body is null or char_length(body) <= 2000),
  payload          jsonb,        -- events: {type:"result"|"belt"|"callout"|"replay", …}
  media_path       text,
  created_at       timestamptz not null default now()
);

create index messages_conversation on public.messages(conversation_id, created_at desc);

create or replace function private.is_conversation_member(c uuid, u uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.conversations cv
    where cv.id = c and (
      (cv.kind = 'direct' and u in (cv.user_a, cv.user_b)
        and not private.is_blocked(cv.user_a, cv.user_b))
      or (cv.kind = 'squad' and private.is_squad_member(cv.squad_id, u))
    )
  )
$$;

create or replace function private.bump_conversation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.conversations set last_message_at = new.created_at where id = new.conversation_id;
  return new;
end $$;

create trigger messages_bump after insert on public.messages
  for each row execute function private.bump_conversation();

-- ─────────────────────────────────────────────────────────────────────────
-- Call outs
-- ─────────────────────────────────────────────────────────────────────────

create table public.callouts (
  id            uuid primary key default gen_random_uuid(),
  created_by    uuid not null references public.profiles(id) on delete cascade,
  challengers   uuid[] not null,          -- player ids (1 or 2)
  challenged    uuid[] not null,          -- player ids (1 or 2)
  sport         text not null check (sport in ('pickleball','padel')),
  rules         jsonb not null,
  proposed_at   timestamptz,
  court         jsonb,
  status        text not null default 'pending'
                check (status in ('pending','accepted','countered','declined','completed','cancelled')),
  -- Last counter-offer: {proposed_at, court, by}
  counter       jsonb,
  match_id      uuid references public.matches(id) on delete set null,
  squad_id      uuid references public.squads(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (cardinality(challengers) between 1 and 2 and cardinality(challengers) = cardinality(challenged))
);

create trigger callouts_touch before update on public.callouts
  for each row execute function private.touch_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- Squad tournaments and trophies
-- ─────────────────────────────────────────────────────────────────────────

create table public.tournaments (
  id           uuid primary key default gen_random_uuid(),
  squad_id     uuid not null references public.squads(id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 60),
  sport        text not null check (sport in ('pickleball','padel')),
  format       text not null check (format in ('round_robin','king_of_court','americano')),
  rules        jsonb not null,
  status       text not null default 'active' check (status in ('active','completed')),
  champions    uuid[] not null default '{}',
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  completed_at timestamptz
);

create table public.tournament_entrants (
  tournament_id  uuid not null references public.tournaments(id) on delete cascade,
  player_id      uuid not null references public.players(id) on delete cascade,
  primary key (tournament_id, player_id)
);

create table public.tournament_fixtures (
  id             uuid primary key default gen_random_uuid(),
  tournament_id  uuid not null references public.tournaments(id) on delete cascade,
  round          smallint not null,
  court_number   smallint not null default 1,
  team_a         uuid[] not null,
  team_b         uuid[] not null,
  scheduled_at   timestamptz,
  court          jsonb,
  match_id       uuid references public.matches(id) on delete set null
);

alter table public.matches
  add constraint matches_tournament_fk foreign key (tournament_id) references public.tournaments(id) on delete set null,
  add constraint matches_fixture_fk foreign key (fixture_id) references public.tournament_fixtures(id) on delete set null,
  add constraint matches_callout_fk foreign key (callout_id) references public.callouts(id) on delete set null;

create table public.trophies (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null references public.profiles(id) on delete cascade,
  kind           text not null check (kind in ('tournament','replay')),
  title          text not null,
  tournament_id  uuid references public.tournaments(id) on delete set null,
  replay_id      uuid,
  awarded_at     timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────
-- Replays (24-hour match stories)
-- ─────────────────────────────────────────────────────────────────────────

create table public.replays (
  id           uuid primary key default gen_random_uuid(),
  match_id     uuid not null references public.matches(id) on delete cascade,
  author_id    uuid not null references public.profiles(id) on delete cascade,
  story        jsonb not null,           -- CourtKit ReplayStory
  photo_paths  text[] not null default '{}',
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '24 hours',
  saved        boolean not null default false
);

alter table public.trophies
  add constraint trophies_replay_fk foreign key (replay_id) references public.replays(id) on delete cascade;

-- ─────────────────────────────────────────────────────────────────────────
-- Feed: Serves and Returns (friends only, never public)
-- ─────────────────────────────────────────────────────────────────────────

create table public.serves (
  id              uuid primary key default gen_random_uuid(),
  author_id       uuid not null references public.profiles(id) on delete cascade,
  kind            text not null check (kind in ('text','photo','video','result')),
  body            text check (body is null or char_length(body) <= 1000),
  media_paths     text[] not null default '{}',
  match_id        uuid references public.matches(id) on delete set null,
  created_at      timestamptz not null default now(),
  rally_count     integer not null default 0,
  last_return_at  timestamptz
);

create table public.returns (
  id          uuid primary key default gen_random_uuid(),
  serve_id    uuid not null references public.serves(id) on delete cascade,
  author_id   uuid not null references public.profiles(id) on delete cascade,
  kind        text not null check (kind in ('comment','chant','photo')),
  body        text check (body is null or char_length(body) <= 500),
  media_path  text,
  created_at  timestamptz not null default now()
);

create index serves_author on public.serves(author_id, created_at desc);
create index returns_serve on public.returns(serve_id, created_at);

create or replace function private.count_rally() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.serves set rally_count = rally_count + 1, last_return_at = new.created_at
    where id = new.serve_id;
  else
    update public.serves set rally_count = greatest(rally_count - 1, 0),
      last_return_at = (select max(created_at) from public.returns where serve_id = old.serve_id)
    where id = old.serve_id;
  end if;
  return null;
end $$;

create trigger returns_rally after insert or delete on public.returns
  for each row execute function private.count_rally();

-- ─────────────────────────────────────────────────────────────────────────
-- Live matches: a Watch- or phone-scored match in progress, so friends can
-- follow the score and send crowd taps. The host keeps it fresh and
-- removes it at the end; the taps themselves go over a Realtime broadcast.
-- ─────────────────────────────────────────────────────────────────────────

create table public.live_matches (
  match_id    uuid primary key,
  host_id     uuid not null references public.profiles(id) on delete cascade,
  sport       text not null check (sport in ('pickleball','padel')),
  player_ids  uuid[] not null default '{}',   -- accounts in the match
  lineup      jsonb not null,                 -- CourtKit Lineup (names)
  score       jsonb not null,                 -- CourtKit LiveScoreSnapshot
  squad_id    uuid references public.squads(id) on delete set null,
  started_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger live_matches_touch before update on public.live_matches
  for each row execute function private.touch_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- Row-level security
-- ─────────────────────────────────────────────────────────────────────────

alter table public.profiles             enable row level security;
alter table public.players              enable row level security;
alter table public.friendships          enable row level security;
alter table public.blocks               enable row level security;
alter table public.reports              enable row level security;
alter table public.squads               enable row level security;
alter table public.squad_members        enable row level security;
alter table public.invites              enable row level security;
alter table public.matches              enable row level security;
alter table public.match_participants   enable row level security;
alter table public.conversations        enable row level security;
alter table public.messages             enable row level security;
alter table public.callouts             enable row level security;
alter table public.tournaments          enable row level security;
alter table public.tournament_entrants  enable row level security;
alter table public.tournament_fixtures  enable row level security;
alter table public.trophies             enable row level security;
alter table public.replays              enable row level security;
alter table public.serves               enable row level security;
alter table public.returns              enable row level security;
alter table public.live_matches         enable row level security;

-- Profiles: you, friends and squadmates. Username search goes through an
-- RPC that returns a minimal card, so profiles are never listable.
create policy profiles_select on public.profiles for select to authenticated
  using (
    private.can_see_user(auth.uid(), id)
    -- Both sides of a pending friend request see each other's card.
    or exists (select 1 from public.friendships f
               where f.user_a = least(auth.uid(), profiles.id)
                 and f.user_b = greatest(auth.uid(), profiles.id))
  );
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy players_select on public.players for select to authenticated
  using (
    (kind = 'user' and private.can_see_user(auth.uid(), id))
    or created_by = auth.uid() or claimed_by = auth.uid()
    or exists (select 1 from public.match_participants mp
               where mp.player_id = players.id and private.can_see_match(mp.match_id, auth.uid()))
    or exists (select 1 from public.tournament_entrants te
               join public.tournaments t on t.id = te.tournament_id
               where te.player_id = players.id and private.is_squad_member(t.squad_id, auth.uid()))
  );
create policy players_insert on public.players for insert to authenticated
  with check (kind = 'guest' and created_by = auth.uid());
create policy players_update on public.players for update to authenticated
  using (kind = 'guest' and created_by = auth.uid() and claimed_by is null)
  with check (kind = 'guest' and created_by = auth.uid());

create policy friendships_select on public.friendships for select to authenticated
  using (auth.uid() in (user_a, user_b));
create policy friendships_delete on public.friendships for delete to authenticated
  using (auth.uid() in (user_a, user_b));

create policy blocks_select on public.blocks for select to authenticated using (blocker = auth.uid());
create policy blocks_insert on public.blocks for insert to authenticated with check (blocker = auth.uid());
create policy blocks_delete on public.blocks for delete to authenticated using (blocker = auth.uid());

create policy reports_insert on public.reports for insert to authenticated with check (reporter = auth.uid());
create policy reports_select on public.reports for select to authenticated using (reporter = auth.uid());

create policy squads_select on public.squads for select to authenticated
  using (private.is_squad_member(id, auth.uid()));
create policy squads_update on public.squads for update to authenticated
  using (private.is_squad_member(id, auth.uid()));

create policy squad_members_select on public.squad_members for select to authenticated
  using (private.is_squad_member(squad_id, auth.uid()));
create policy squad_members_leave on public.squad_members for delete to authenticated
  using (user_id = auth.uid());

create policy invites_select on public.invites for select to authenticated using (created_by = auth.uid());

create policy matches_select on public.matches for select to authenticated
  using (private.can_see_match(id, auth.uid()));
create policy match_participants_select on public.match_participants for select to authenticated
  using (private.can_see_match(match_id, auth.uid()));

create policy conversations_select on public.conversations for select to authenticated
  using (private.is_conversation_member(id, auth.uid()));
create policy messages_select on public.messages for select to authenticated
  using (private.is_conversation_member(conversation_id, auth.uid()));
create policy messages_insert on public.messages for insert to authenticated
  with check (
    sender_id = auth.uid() and kind in ('text','photo')
    and private.is_conversation_member(conversation_id, auth.uid())
  );
create policy messages_delete on public.messages for delete to authenticated
  using (sender_id = auth.uid());

create policy callouts_select on public.callouts for select to authenticated
  using (created_by = auth.uid() or auth.uid() = any(challengers) or auth.uid() = any(challenged));

create policy tournaments_select on public.tournaments for select to authenticated
  using (private.is_squad_member(squad_id, auth.uid()));
create policy tournament_entrants_select on public.tournament_entrants for select to authenticated
  using (exists (select 1 from public.tournaments t where t.id = tournament_id
                 and private.is_squad_member(t.squad_id, auth.uid())));
create policy tournament_fixtures_select on public.tournament_fixtures for select to authenticated
  using (exists (select 1 from public.tournaments t where t.id = tournament_id
                 and private.is_squad_member(t.squad_id, auth.uid())));
-- King of the Court adds each round's fixtures as the last one finishes.
create policy tournament_fixtures_insert on public.tournament_fixtures for insert to authenticated
  with check (exists (select 1 from public.tournaments t where t.id = tournament_id
                      and t.status = 'active' and private.is_squad_member(t.squad_id, auth.uid())));
create policy tournament_fixtures_update on public.tournament_fixtures for update to authenticated
  using (exists (select 1 from public.tournaments t where t.id = tournament_id
                 and private.is_squad_member(t.squad_id, auth.uid())));

create policy trophies_select on public.trophies for select to authenticated
  using (private.can_see_user(auth.uid(), owner_id));

create policy replays_select on public.replays for select to authenticated
  using (
    author_id = auth.uid()
    or ((saved or expires_at > now()) and private.can_see_user(auth.uid(), author_id))
  );
create policy replays_insert on public.replays for insert to authenticated
  with check (author_id = auth.uid() and private.is_match_participant(match_id, auth.uid()));
create policy replays_update on public.replays for update to authenticated
  using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy replays_delete on public.replays for delete to authenticated
  using (author_id = auth.uid());

-- Serves: friends only (not squadmates who aren't friends), never public.
create policy serves_select on public.serves for select to authenticated
  using (author_id = auth.uid() or private.are_friends(auth.uid(), author_id));
create policy serves_insert on public.serves for insert to authenticated
  with check (author_id = auth.uid() and rally_count = 0 and last_return_at is null);
create policy serves_delete on public.serves for delete to authenticated
  using (author_id = auth.uid());

create policy returns_select on public.returns for select to authenticated
  using (exists (select 1 from public.serves s where s.id = serve_id
                 and (s.author_id = auth.uid() or private.are_friends(auth.uid(), s.author_id)))
         and not private.is_blocked(auth.uid(), author_id));
create policy returns_insert on public.returns for insert to authenticated
  with check (author_id = auth.uid()
              and exists (select 1 from public.serves s where s.id = serve_id
                          and (s.author_id = auth.uid() or private.are_friends(auth.uid(), s.author_id))));
create policy returns_delete on public.returns for delete to authenticated
  using (author_id = auth.uid());

-- Live matches: the host's friends, the players, and the squad follow along.
create policy live_matches_select on public.live_matches for select to authenticated
  using (
    host_id = auth.uid() or auth.uid() = any(player_ids)
    or private.are_friends(auth.uid(), host_id)
    or (squad_id is not null and private.is_squad_member(squad_id, auth.uid()))
  );
create policy live_matches_insert on public.live_matches for insert to authenticated
  with check (host_id = auth.uid());
create policy live_matches_update on public.live_matches for update to authenticated
  using (host_id = auth.uid()) with check (host_id = auth.uid());
create policy live_matches_delete on public.live_matches for delete to authenticated
  using (host_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────
-- Views
-- ─────────────────────────────────────────────────────────────────────────

-- The Feed: friends' Serves. Dead ball: once 24 hours pass without a
-- Return, a Serve drops out of the Feed (it stays in the author's archive).
-- Every Return keeps the ball in play for another 24 hours.
create view public.feed_serves with (security_invoker = true) as
  select s.* from public.serves s
  where s.author_id <> auth.uid()
    and not private.is_blocked(auth.uid(), s.author_id)
    and coalesce(s.last_return_at, s.created_at) > now() - interval '24 hours';

-- ─────────────────────────────────────────────────────────────────────────
-- RPCs
-- ─────────────────────────────────────────────────────────────────────────

-- Profile setup checks a name before saving it (profiles aren't listable).
create or replace function public.username_available(name text) returns boolean
language sql stable security definer set search_path = public as $$
  select lower(name) ~ '^[a-z0-9_.]{3,20}$' and lower(name) !~ '^[._]|[._]$'
     and not exists (select 1 from public.profiles where username = lower(name) and id <> auth.uid())
$$;

-- Username search: exact or prefix match, minimal card only.
create or replace function public.search_users(query text)
returns table (id uuid, username citext, display_name text, avatar_path text)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, p.display_name, p.avatar_path
  from public.profiles p
  where char_length(query) >= 2
    and p.username ilike replace(replace(lower(query), '%', ''), '_', '\_') || '%'
    and p.id <> auth.uid()
    and not private.is_blocked(auth.uid(), p.id)
  order by (p.username = lower(query)) desc, p.username
  limit 20
$$;

create or replace function private.ensure_direct_conversation(a uuid, b uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  cid uuid;
begin
  insert into public.conversations (kind, user_a, user_b)
  values ('direct', least(a, b), greatest(a, b))
  on conflict (user_a, user_b) do nothing;
  select id into cid from public.conversations where user_a = least(a, b) and user_b = greatest(a, b);
  return cid;
end $$;

-- Send (or accept, if they already asked you) a friend request.
create or replace function public.request_friend(target uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  existing public.friendships;
begin
  if me is null then raise exception 'not signed in'; end if;
  if target = me then raise exception 'cannot friend yourself'; end if;
  if private.is_blocked(me, target) then raise exception 'unavailable'; end if;

  select * into existing from public.friendships
  where user_a = least(me, target) and user_b = greatest(me, target);

  if not found then
    insert into public.friendships (user_a, user_b, status, requested_by)
    values (least(me, target), greatest(me, target), 'pending', me);
    return 'pending';
  elsif existing.status = 'accepted' then
    return 'accepted';
  elsif existing.requested_by = me then
    return 'pending';
  else
    update public.friendships set status = 'accepted', accepted_at = now()
    where user_a = existing.user_a and user_b = existing.user_b;
    perform private.ensure_direct_conversation(me, target);
    return 'accepted';
  end if;
end $$;

create or replace function public.respond_friend(requester uuid, accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if accept then
    update public.friendships set status = 'accepted', accepted_at = now()
    where user_a = least(me, requester) and user_b = greatest(me, requester)
      and status = 'pending' and requested_by = requester;
    if found then perform private.ensure_direct_conversation(me, requester); end if;
  else
    delete from public.friendships
    where user_a = least(me, requester) and user_b = greatest(me, requester)
      and status = 'pending' and requested_by = requester;
  end if;
end $$;

create or replace function public.block_user(target uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  insert into public.blocks (blocker, blocked) values (me, target) on conflict do nothing;
  delete from public.friendships where user_a = least(me, target) and user_b = greatest(me, target);
end $$;

create or replace function public.create_invite(invite_kind text, target uuid default null) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  tok text;
begin
  if me is null then raise exception 'not signed in'; end if;
  if invite_kind = 'squad' and not private.is_squad_member(target, me) then
    raise exception 'not a squad member';
  end if;
  if invite_kind = 'guest_claim' and not exists (
    select 1 from public.players pl
    where pl.id = target and pl.kind = 'guest' and pl.created_by = me and pl.claimed_by is null
  ) then
    raise exception 'not your guest';
  end if;
  insert into public.invites (kind, created_by, target_id) values (invite_kind, me, target) returning token into tok;
  return tok;
end $$;

-- Redeems a friend link / QR, squad link or guest claim link.
create or replace function public.redeem_invite(tok text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  inv public.invites;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into inv from public.invites where token = tok for update;
  if not found or inv.expires_at < now() then raise exception 'invite expired'; end if;
  if private.is_blocked(me, inv.created_by) then raise exception 'unavailable'; end if;

  if inv.kind = 'friend' then
    if inv.created_by <> me then
      insert into public.friendships (user_a, user_b, status, requested_by, accepted_at)
      values (least(me, inv.created_by), greatest(me, inv.created_by), 'accepted', inv.created_by, now())
      on conflict (user_a, user_b) do update set status = 'accepted', accepted_at = now();
      perform private.ensure_direct_conversation(me, inv.created_by);
    end if;
    return jsonb_build_object('kind', 'friend', 'user_id', inv.created_by);

  elsif inv.kind = 'squad' then
    insert into public.squad_members (squad_id, user_id) values (inv.target_id, me) on conflict do nothing;
    insert into public.messages (conversation_id, kind, payload)
    select id, 'event', jsonb_build_object('type', 'joined', 'user_id', me)
    from public.conversations where squad_id = inv.target_id;
    return jsonb_build_object('kind', 'squad', 'squad_id', inv.target_id);

  else -- guest_claim: single use
    if inv.used_at is not null then raise exception 'invite used'; end if;
    update public.players set claimed_by = me
    where id = inv.target_id and kind = 'guest' and claimed_by is null;
    update public.invites set used_at = now() where token = tok;
    -- Nudge every match with this guest so phones re-read the lineup.
    update public.matches set updated_at = now()
    where id in (select match_id from public.match_participants where player_id = inv.target_id);
    -- Claiming a guest means you played the person who made the link.
    if inv.created_by <> me then
      insert into public.friendships (user_a, user_b, status, requested_by, accepted_at)
      values (least(me, inv.created_by), greatest(me, inv.created_by), 'accepted', inv.created_by, now())
      on conflict (user_a, user_b) do update set status = 'accepted', accepted_at = now();
      perform private.ensure_direct_conversation(me, inv.created_by);
    end if;
    return jsonb_build_object('kind', 'guest_claim', 'player_id', inv.target_id);
  end if;
end $$;

create or replace function public.create_squad(squad_name text, member_ids uuid[] default '{}') returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  sid uuid;
  m uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  insert into public.squads (name, created_by) values (squad_name, me) returning id into sid;
  insert into public.squad_members (squad_id, user_id, role) values (sid, me, 'owner');
  foreach m in array member_ids loop
    if private.are_friends(me, m) then
      insert into public.squad_members (squad_id, user_id) values (sid, m) on conflict do nothing;
    end if;
  end loop;
  insert into public.conversations (kind, squad_id) values ('squad', sid);
  return sid;
end $$;

create or replace function public.add_squad_member(sid uuid, member uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not private.is_squad_member(sid, auth.uid()) then raise exception 'not a squad member'; end if;
  if not private.are_friends(auth.uid(), member) then raise exception 'only friends can be added'; end if;
  insert into public.squad_members (squad_id, user_id) values (sid, member) on conflict do nothing;
end $$;


-- The user a player row stands for: users are themselves, claimed guests
-- are whoever claimed them, unclaimed guests are nobody.
create or replace function private.player_user(pid uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(claimed_by, case when kind = 'user' then id end) from public.players where id = pid
$$;

-- Marks a match confirmed and tells the right chat: the squad chat for
-- squad and tournament matches, else the direct chat between `actor` and
-- another user in the match. `events` are chat event payloads the client
-- derived (belt changes, comebacks) and are posted after the result.
create or replace function private.finalize_match(mid uuid, actor uuid, events jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  mt public.matches;
  actor_team smallint;
  other uuid;
  cid uuid;
  e jsonb;
begin
  update public.matches set status = 'confirmed', confirmed_at = now() where id = mid
  returning * into mt;

  if mt.squad_id is not null then
    select id into cid from public.conversations where squad_id = mt.squad_id;
  else
    select mp.team into actor_team from public.match_participants mp
    where mp.match_id = mid and private.player_user(mp.player_id) = actor;
    select u into other from (
      select private.player_user(mp.player_id) as u, (mp.team is distinct from actor_team) as opposing
      from public.match_participants mp where mp.match_id = mid
    ) x
    where u is not null and u <> actor and private.are_friends(actor, u)
    order by opposing desc
    limit 1;
    if other is not null then
      cid := private.ensure_direct_conversation(actor, other);
    end if;
  end if;

  if cid is not null then
    insert into public.messages (conversation_id, kind, payload)
    values (cid, 'event', jsonb_build_object('type', 'result', 'match_id', mid));
    for e in select * from jsonb_array_elements(coalesce(events, '[]'::jsonb)) loop
      insert into public.messages (conversation_id, kind, payload) values (cid, 'event', e);
    end loop;
  end if;

  if mt.callout_id is not null then
    update public.callouts set status = 'completed', match_id = mid
    where id = mt.callout_id and status in ('pending','accepted','countered');
  end if;
  if mt.fixture_id is not null then
    update public.tournament_fixtures set match_id = mid where id = mt.fixture_id;
  end if;
end $$;

-- Saves a match with its participants in one call. Idempotent on match id
-- so the offline outbox can retry safely. The other side must confirm:
-- one user on each side that didn't score it. With no users on the other
-- side (guests only) the match is confirmed at once.
create or replace function public.save_match(m jsonb, participants jsonb, events jsonb default '[]') returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  mid uuid := (m->>'id')::uuid;
  existing public.matches;
  p jsonb;
  pid uuid;
  pl public.players;
  squad uuid := (m->>'squad_id')::uuid;
  tournament uuid := (m->>'tournament_id')::uuid;
  scorer_team smallint;
  needs_confirmation boolean;
begin
  if me is null then raise exception 'not signed in'; end if;

  select * into existing from public.matches where id = mid;
  if found then
    if existing.created_by is distinct from me then raise exception 'not your match'; end if;
    if existing.status = 'confirmed' then return 'confirmed'; end if;
  end if;

  if tournament is not null then
    select squad_id into squad from public.tournaments where id = tournament;
  end if;
  if squad is not null and not private.is_squad_member(squad, me) then
    raise exception 'not a squad member';
  end if;

  -- Users must be you, friends or squadmates; guests are created on first
  -- use. The row's kind decides, never the client's word for it.
  for p in select * from jsonb_array_elements(participants) loop
    pid := (p->>'player_id')::uuid;
    select * into pl from public.players where id = pid;
    if not found then
      if (p->>'kind') is distinct from 'guest' then raise exception 'unknown player %', pid; end if;
      insert into public.players (id, kind, display_name, created_by)
      values (pid, 'guest', coalesce(nullif(p->>'display_name', ''), 'Guest'), me);
    elsif pl.kind = 'user' and pid <> me and not private.are_friends(me, pid)
          and not (squad is not null and private.is_squad_member(squad, pid)) then
      raise exception 'players must be you, friends, squadmates or guests';
    end if;
  end loop;

  insert into public.matches (id, sport, rules, source, created_by, status, started_at, ended_at,
    winner_team, match_score, points, units, rally_winners, rally_offsets, court,
    squad_id, tournament_id, fixture_id, callout_id, workout)
  values (mid, m->>'sport', m->'rules', m->>'source', me, 'pending',
    (m->>'started_at')::timestamptz, (m->>'ended_at')::timestamptz,
    (m->>'winner_team')::smallint,
    array[coalesce((m->'match_score'->>0)::smallint, 0), coalesce((m->'match_score'->>1)::smallint, 0)],
    array[coalesce((m->'points'->>0)::smallint, 0), coalesce((m->'points'->>1)::smallint, 0)],
    coalesce(m->'units', '[]'::jsonb), m->>'rally_winners',
    case when jsonb_typeof(m->'rally_offsets') = 'array'
         then array(select jsonb_array_elements_text(m->'rally_offsets')::real) end,
    m->'court', squad, tournament, (m->>'fixture_id')::uuid, (m->>'callout_id')::uuid, m->'workout')
  on conflict (id) do update set
    rules = excluded.rules, ended_at = excluded.ended_at, winner_team = excluded.winner_team,
    match_score = excluded.match_score, points = excluded.points, units = excluded.units,
    rally_winners = excluded.rally_winners, rally_offsets = excluded.rally_offsets,
    court = excluded.court, workout = excluded.workout, status = 'pending';

  delete from public.match_participants where match_id = mid;
  insert into public.match_participants (match_id, player_id, team, slot)
  select mid, (x->>'player_id')::uuid, (x->>'team')::smallint, (x->>'slot')::smallint
  from jsonb_array_elements(participants) x;

  select mp.team into scorer_team from public.match_participants mp
  where mp.match_id = mid and private.player_user(mp.player_id) = me;
  if scorer_team is null and tournament is null then
    raise exception 'you must be in the match';
  end if;

  if scorer_team is not null then
    -- The scorer's own side counts as confirmed.
    update public.match_participants set confirmed_at = now()
    where match_id = mid and team = scorer_team;
    select exists (
      select 1 from public.match_participants mp
      where mp.match_id = mid and mp.team <> scorer_team and private.player_user(mp.player_id) is not null
    ) into needs_confirmation;
  else
    -- A squadmate scored someone else's tournament match: each side with a
    -- user confirms; sides of only guests are taken as confirmed.
    update public.match_participants mp set confirmed_at = now()
    where mp.match_id = mid and not exists (
      select 1 from public.match_participants o
      where o.match_id = mid and o.team = mp.team and private.player_user(o.player_id) is not null
    );
    select exists (
      select 1 from public.match_participants where match_id = mid and confirmed_at is null
    ) into needs_confirmation;
  end if;

  if needs_confirmation then
    return 'pending';
  end if;
  perform private.finalize_match(mid, me, events);
  return 'confirmed';
end $$;

-- A player confirms (or disputes) a result. One confirmation per side is
-- enough: a doubles partner confirms for the pair.
create or replace function public.confirm_match(mid uuid, agree boolean, events jsonb default '[]') returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  my_team smallint;
  mt public.matches;
begin
  select * into mt from public.matches where id = mid for update;
  if not found then raise exception 'no such match'; end if;

  select mp.team into my_team from public.match_participants mp
  where mp.match_id = mid and private.player_user(mp.player_id) = me;
  if my_team is null then raise exception 'not in this match'; end if;
  if mt.status <> 'pending' then return mt.status; end if;

  if not agree then
    update public.match_participants set disputed_at = now()
    where match_id = mid and private.player_user(player_id) = me;
    update public.matches set status = 'disputed' where id = mid;
    return 'disputed';
  end if;

  update public.match_participants set confirmed_at = coalesce(confirmed_at, now())
  where match_id = mid and team = my_team;

  if exists (select 1 from public.match_participants where match_id = mid and confirmed_at is null) then
    return 'pending';
  end if;
  perform private.finalize_match(mid, me, events);
  return 'confirmed';
end $$;

-- The scorer fixes a disputed result by saving it again (save_match), or
-- withdraws it.
create or replace function public.withdraw_match(mid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.matches where id = mid and created_by = auth.uid() and status <> 'confirmed';
  if not found then raise exception 'cannot withdraw'; end if;
end $$;

-- Call outs: create, respond (accept / counter / decline), cancel.
create or replace function public.create_callout(c jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  cid uuid;
  conv uuid;
  target uuid;
begin
  foreach target in array array(select jsonb_array_elements_text(c->'challenged')::uuid) loop
    if not private.are_friends(me, target) then raise exception 'you can only call out friends'; end if;
  end loop;
  insert into public.callouts (created_by, challengers, challenged, sport, rules, proposed_at, court, squad_id)
  values (me,
    array(select jsonb_array_elements_text(c->'challengers')::uuid),
    array(select jsonb_array_elements_text(c->'challenged')::uuid),
    c->>'sport', c->'rules', (c->>'proposed_at')::timestamptz, c->'court', (c->>'squad_id')::uuid)
  returning id into cid;

  if c ? 'squad_id' then
    select id into conv from public.conversations where squad_id = (c->>'squad_id')::uuid;
  else
    conv := private.ensure_direct_conversation(me, (c->'challenged'->>0)::uuid);
  end if;
  insert into public.messages (conversation_id, kind, payload)
  values (conv, 'event', jsonb_build_object('type', 'callout', 'callout_id', cid, 'by', me));
  return cid;
end $$;

create or replace function public.respond_callout(cid uuid, response text, counter_offer jsonb default null) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  co public.callouts;
begin
  select * into co from public.callouts where id = cid for update;
  if not found then raise exception 'no such call out'; end if;
  -- The challenger can call it off any time before it's played.
  if response = 'cancel' then
    if co.created_by <> me then raise exception 'only the challenger can cancel'; end if;
    if co.status not in ('pending','countered','accepted') then return co.status; end if;
    update public.callouts set status = 'cancelled' where id = cid;
    return 'cancelled';
  end if;
  if co.status not in ('pending','countered') then return co.status; end if;

  -- The side that didn't make the last move answers.
  if co.status = 'pending' and not (me = any(co.challenged)) then raise exception 'not your call out to answer'; end if;
  if co.status = 'countered' and (co.counter->>'by')::uuid = me then raise exception 'waiting on the other side'; end if;
  if not (me = any(co.challenged) or me = any(co.challengers)) then raise exception 'not in this call out'; end if;

  if response = 'accept' then
    update public.callouts set status = 'accepted',
      proposed_at = coalesce((co.counter->>'proposed_at')::timestamptz, proposed_at),
      court = coalesce(co.counter->'court', court)
    where id = cid;
    return 'accepted';
  elsif response = 'decline' then
    update public.callouts set status = 'declined' where id = cid;
    return 'declined';
  elsif response = 'counter' then
    update public.callouts set status = 'countered',
      counter = coalesce(counter_offer, '{}'::jsonb) || jsonb_build_object('by', me)
    where id = cid;
    return 'countered';
  end if;
  raise exception 'unknown response %', response;
end $$;

-- Squad tournaments: one call creates the tournament, entrants (squad
-- members and guests by name) and the generated fixtures.
create or replace function public.create_tournament(t jsonb, entrants jsonb, fixtures jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  tid uuid;
  e jsonb;
  f jsonb;
  conv uuid;
begin
  if not private.is_squad_member((t->>'squad_id')::uuid, me) then raise exception 'not a squad member'; end if;
  insert into public.tournaments (squad_id, name, sport, format, rules, created_by)
  values ((t->>'squad_id')::uuid, t->>'name', t->>'sport', t->>'format', t->'rules', me)
  returning id into tid;

  for e in select * from jsonb_array_elements(entrants) loop
    if (e->>'kind') = 'guest' then
      insert into public.players (id, kind, display_name, created_by)
      values ((e->>'player_id')::uuid, 'guest', e->>'display_name', me) on conflict (id) do nothing;
    elsif not private.is_squad_member((t->>'squad_id')::uuid, (e->>'player_id')::uuid) then
      raise exception 'entrants must be squad members or guests';
    end if;
    insert into public.tournament_entrants (tournament_id, player_id) values (tid, (e->>'player_id')::uuid);
  end loop;

  for f in select * from jsonb_array_elements(fixtures) loop
    insert into public.tournament_fixtures (id, tournament_id, round, court_number, team_a, team_b, scheduled_at, court)
    values (coalesce((f->>'id')::uuid, gen_random_uuid()), tid, (f->>'round')::smallint,
      coalesce((f->>'court_number')::smallint, 1),
      array(select jsonb_array_elements_text(f->'team_a')::uuid),
      array(select jsonb_array_elements_text(f->'team_b')::uuid),
      (f->>'scheduled_at')::timestamptz, f->'court');
  end loop;

  select id into conv from public.conversations where squad_id = (t->>'squad_id')::uuid;
  insert into public.messages (conversation_id, kind, payload)
  values (conv, 'event', jsonb_build_object('type', 'tournament_created', 'tournament_id', tid));
  return tid;
end $$;

-- Closes a tournament: champions get trophies, the squad chat hears.
create or replace function public.complete_tournament(tid uuid, champion_ids uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare
  tr public.tournaments;
  c uuid;
  conv uuid;
begin
  select * into tr from public.tournaments where id = tid for update;
  if not private.is_squad_member(tr.squad_id, auth.uid()) then raise exception 'not a squad member'; end if;
  if tr.status = 'completed' then return; end if;
  update public.tournaments set status = 'completed', champions = champion_ids, completed_at = now() where id = tid;
  foreach c in array champion_ids loop
    if private.player_user(c) is not null then
      insert into public.trophies (owner_id, kind, title, tournament_id)
      values (private.player_user(c), 'tournament', tr.name, tid);
    end if;
  end loop;
  select id into conv from public.conversations where squad_id = tr.squad_id;
  insert into public.messages (conversation_id, kind, payload)
  values (conv, 'event', jsonb_build_object('type', 'champion', 'tournament_id', tid, 'champions', to_jsonb(champion_ids)));
end $$;

-- Shares a Replay to a friend or squad chat as an event message.
create or replace function public.share_replay(rid uuid, conversation uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.replays where id = rid and author_id = auth.uid()) then
    raise exception 'not your replay';
  end if;
  if not private.is_conversation_member(conversation, auth.uid()) then raise exception 'not in this chat'; end if;
  insert into public.messages (conversation_id, kind, payload)
  values (conversation, 'event', jsonb_build_object('type', 'replay', 'replay_id', rid, 'by', auth.uid()));
end $$;

-- Saving a Replay keeps it past 24 hours and puts it in the trophy case.
create or replace function public.save_replay(rid uuid, title text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.replays set saved = true where id = rid and author_id = auth.uid();
  if not found then raise exception 'not your replay'; end if;
  insert into public.trophies (owner_id, kind, title, replay_id) values (auth.uid(), 'replay', title, rid);
end $$;

-- Deletes the caller's account (App Store Guideline 5.1.1(v)). Matches
-- stay in opponents' history under a neutral name; everything personal
-- (profile, friendships, chats, Serves, Replays, trophies) goes with the
-- auth user through the cascades above. The app empties the user's
-- storage folders through the Storage API first (Supabase refuses direct
-- deletes from storage.objects).
create or replace function public.delete_account() returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  delete from public.messages where sender_id = me;
  update public.players set display_name = 'Former player' where id = me;
  update public.players set claimed_by = null, display_name = 'Former player' where claimed_by = me;
  delete from auth.users where id = me;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- Grants, realtime, storage
-- ─────────────────────────────────────────────────────────────────────────

-- Signed-in users only; RLS narrows every table from here. Supabase's
-- default privileges hand new objects to anon too, so take them back.
grant usage on schema public to anon, authenticated, service_role;
revoke all on all tables in schema public from anon, public;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
revoke execute on all functions in schema public from anon, public;
grant execute on all functions in schema public to authenticated, service_role;
grant usage on schema private to authenticated, service_role;
revoke execute on all functions in schema private from anon, public;
-- Policies run as the caller, so the checks they call must be executable;
-- the steps only RPCs may take are not.
grant execute on all functions in schema private to authenticated, service_role;
revoke execute on function private.finalize_match(uuid, uuid, jsonb),
                           private.ensure_direct_conversation(uuid, uuid) from authenticated;

alter publication supabase_realtime add table
  public.messages, public.conversations, public.friendships, public.matches,
  public.match_participants, public.callouts, public.serves, public.returns,
  public.tournament_fixtures, public.tournaments, public.live_matches;

insert into storage.buckets (id, name, public) values
  ('avatars', 'avatars', true),
  ('media', 'media', false)
on conflict (id) do nothing;

-- Files live under "<user id>/…". Owners write their own folder; media is
-- readable by the owner and their friends (signed URLs from the app).
create policy avatars_write on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy media_write on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
create policy media_read on storage.objects for select to authenticated
  using (bucket_id = 'media' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or private.can_see_user(auth.uid(), ((storage.foldername(name))[1])::uuid)
  ));
create policy media_delete on storage.objects for delete to authenticated
  using (bucket_id in ('media','avatars') and (storage.foldername(name))[1] = auth.uid()::text);
