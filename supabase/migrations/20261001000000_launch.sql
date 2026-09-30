-- PickleBall Phase 3: launch and grow.
--
--   1. Security review fixes (see docs/SECURITY_REVIEW.md for each finding).
--   2. Moderation: admins, bans, report handling.
--   3. Privacy-friendly analytics and crash reports (no account link).
--   4. Share links and public read-only scoreboards for the web.
--   5. Compete: new tournament formats, stages, and published levels.

-- ─────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────

create table if not exists private.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  added_at   timestamptz not null default now()
);

create table public.bans (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  reason     text not null default '',
  banned_by  uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.bans enable row level security;
-- No policies: only moderation functions read or write bans.

create or replace function private.is_admin(u uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from private.admins where user_id = u)
$$;

create or replace function private.is_banned(u uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.bans where user_id = u)
$$;

-- Called at the top of write functions: banned accounts can't act, even
-- in the minutes before their session expires.
create or replace function private.assert_active() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if private.is_banned(auth.uid()) then raise exception 'account suspended'; end if;
end $$;

-- Each player publishes the level their phone works out from confirmed
-- results, so friends see the same number: {"pickleball": 3.42, ...}.
alter table public.profiles add column levels jsonb not null default '{}'
  check (jsonb_typeof(levels) = 'object' and pg_column_size(levels) < 500);

create or replace function private.try_uuid(t text) returns uuid
language plpgsql immutable as $$
begin
  return t::uuid;
exception when others then
  return null;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 1. Security review fixes
-- ─────────────────────────────────────────────────────────────────────────

-- F1. A guest's creator could set claimed_by to anyone. Only renames now.
revoke update on public.players from authenticated;
grant update (display_name) on public.players to authenticated;

-- F6. Updates were open on every column. Narrow them to what the app edits.
revoke update on public.squads from authenticated;
grant update (name, signature_chant) on public.squads to authenticated;
revoke update on public.tournament_fixtures from authenticated;
grant update (scheduled_at, court) on public.tournament_fixtures to authenticated;
revoke update on public.replays from authenticated;   -- saved via save_replay()
drop policy replays_update on public.replays;
revoke update on public.profiles from authenticated;
grant update (username, display_name, avatar_path, sports, home_courts, levels) on public.profiles to authenticated;
revoke update on public.live_matches from authenticated;
grant update (sport, player_ids, lineup, score, squad_id) on public.live_matches to authenticated;

-- F6. Replays start unsaved and expire within a day.
drop policy replays_insert on public.replays;
create policy replays_insert on public.replays for insert to authenticated
  with check (author_id = auth.uid() and private.is_match_participant(match_id, auth.uid())
              and saved = false and expires_at <= now() + interval '25 hours');

-- F3. Added fixtures can't point at an existing match: see the fixtures
-- insert policy in section 5.

-- F7. Chat photos live under <user>/chat/<conversation>/ and only that
-- chat can read them. Everything else follows friends-and-squad
-- visibility. Admins can see reported media.
drop policy media_read on storage.objects;
create policy media_read on storage.objects for select to authenticated
  using (bucket_id = 'media' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or private.is_admin(auth.uid())
    or case
         when (storage.foldername(name))[2] = 'chat'
           then private.is_conversation_member(private.try_uuid((storage.foldername(name))[3]), auth.uid())
         else private.can_see_user(auth.uid(), private.try_uuid((storage.foldername(name))[1]))
       end
  ));

-- Banned accounts can't write anything directly (restrictive policies are
-- ANDed with every permissive one).
do $$
declare
  t text;
begin
  foreach t in array array['profiles','players','blocks','reports','messages','replays','serves','returns',
                           'live_matches','tournament_fixtures','squads'] loop
    execute format('create policy %I on public.%I as restrictive for insert to authenticated with check (not private.is_banned(auth.uid()))',
                   t || '_not_banned_insert', t);
    execute format('create policy %I on public.%I as restrictive for update to authenticated using (not private.is_banned(auth.uid()))',
                   t || '_not_banned_update', t);
  end loop;
end $$;

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
    -- Only belt events travel with a confirmation, a handful at most: the
    -- rest are written here, so nobody can post a forged result.
    for e in select * from jsonb_array_elements(coalesce(events, '[]'::jsonb)) limit 6 loop
      if jsonb_typeof(e) = 'object' and e->>'type' = 'belt' and pg_column_size(e) < 4000 then
        insert into public.messages (conversation_id, kind, payload)
        values (cid, 'event', e || jsonb_build_object('match_id', mid));
      end if;
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
  perform private.assert_active();

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
  -- A fixture must belong to the tournament; a call out must be mine.
  if (m->>'fixture_id') is not null and not exists (
    select 1 from public.tournament_fixtures f
    where f.id = (m->>'fixture_id')::uuid and f.tournament_id is not distinct from tournament
  ) then
    raise exception 'fixture is not part of this tournament';
  end if;
  if (m->>'callout_id') is not null and not exists (
    select 1 from public.callouts c
    where c.id = (m->>'callout_id')::uuid and (me = c.created_by or me = any(c.challengers) or me = any(c.challenged))
  ) then
    raise exception 'not your call out';
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

create or replace function public.create_callout(c jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  cid uuid;
  conv uuid;
  target uuid;
begin
  perform private.assert_active();
  -- You're one of the challengers; your partner and your opponents are friends.
  if not me = any(array(select jsonb_array_elements_text(c->'challengers')::uuid)) then
    raise exception 'you must be one of the challengers';
  end if;
  foreach target in array array(select jsonb_array_elements_text(c->'challengers')::uuid) loop
    if target <> me and not private.are_friends(me, target) then raise exception 'your partner must be a friend'; end if;
  end loop;
  if (c->>'squad_id') is not null and not private.is_squad_member((c->>'squad_id')::uuid, me) then
    raise exception 'not a squad member';
  end if;
  foreach target in array array(select jsonb_array_elements_text(c->'challenged')::uuid) loop
    if not private.are_friends(me, target) then raise exception 'you can only call out friends'; end if;
  end loop;
  insert into public.callouts (created_by, challengers, challenged, sport, rules, proposed_at, court, squad_id)
  values (me,
    array(select jsonb_array_elements_text(c->'challengers')::uuid),
    array(select jsonb_array_elements_text(c->'challenged')::uuid),
    c->>'sport', c->'rules', (c->>'proposed_at')::timestamptz, c->'court', (c->>'squad_id')::uuid)
  returning id into cid;

  if (c->>'squad_id') is not null then
    select id into conv from public.conversations where squad_id = (c->>'squad_id')::uuid;
  else
    conv := private.ensure_direct_conversation(me, (c->'challenged'->>0)::uuid);
  end if;
  insert into public.messages (conversation_id, kind, payload)
  values (conv, 'event', jsonb_build_object('type', 'callout', 'callout_id', cid, 'by', me));
  return cid;
end $$;

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
  if exists (select 1 from unnest(champion_ids) as ch(pid)
             where ch.pid not in (select te.player_id from public.tournament_entrants te where te.tournament_id = tid)) then
    raise exception 'champions must be entrants';
  end if;
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

create or replace function public.request_friend(target uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  existing public.friendships;
begin
  if me is null then raise exception 'not signed in'; end if;
  if target = me then raise exception 'cannot friend yourself'; end if;
  if private.is_blocked(me, target) then raise exception 'unavailable'; end if;
  perform private.assert_active();
  if (select count(*) from public.friendships where requested_by = me and status = 'pending') >= 50 then
    raise exception 'too many pending requests';
  end if;

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
-- F8. Crowd taps on private Realtime channels: only people who can see the
-- live match may join "crowd-<match id>". (Realtime Authorization; skipped
-- where the realtime schema doesn't exist, e.g. plain Postgres in CI.)
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'realtime')
     and exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'realtime' and c.relname = 'messages') then
    execute $p$
      create policy crowd_read on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and exists (
        select 1 from public.live_matches l
        where 'crowd-' || l.match_id::text = realtime.topic()))
    $p$;
    execute $p$
      create policy crowd_write on realtime.messages for insert to authenticated
      with check (realtime.messages.extension = 'broadcast' and exists (
        select 1 from public.live_matches l
        where 'crowd-' || l.match_id::text = realtime.topic()))
    $p$;
  end if;
exception when others then
  raise notice 'realtime policies skipped: %', sqlerrm;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 2. Moderation
-- ─────────────────────────────────────────────────────────────────────────

alter table public.reports add column resolution text
  check (resolution in ('dismissed','removed','banned'));

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select private.is_admin(auth.uid())
$$;

create or replace function private.assert_admin() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not private.is_admin(auth.uid()) then raise exception 'admins only'; end if;
end $$;

-- Who wrote a reported thing, and what it says.
create or replace function private.report_target(target_type text, target uuid)
returns table (author uuid, body text, media text[])
language sql stable security definer set search_path = public as $$
  select sender_id, body, array_remove(array[media_path], null) from public.messages where target_type = 'message' and id = target
  union all
  select author_id, body, media_paths from public.serves where target_type = 'serve' and id = target
  union all
  select author_id, body, array_remove(array[media_path], null) from public.returns where target_type = 'return' and id = target
  union all
  select author_id, story->>'headline', photo_paths from public.replays where target_type = 'replay' and id = target
  union all
  select created_by, null, '{}'::text[] from public.matches where target_type = 'match' and id = target
  union all
  select id, display_name || ' (@' || username || ')', array_remove(array[avatar_path], null)
    from public.profiles where target_type = 'user' and id = target
$$;

create or replace function public.admin_reports(open_only boolean default true)
returns table (id uuid, reporter uuid, target_type text, target_id uuid, reason text, created_at timestamptz,
               resolved_at timestamptz, resolution text, author uuid, author_name text, body text, media text[],
               author_reports bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  perform private.assert_admin();
  return query
    select r.id, r.reporter, r.target_type, r.target_id, r.reason, r.created_at, r.resolved_at, r.resolution,
           t.author, p.display_name, t.body, coalesce(t.media, '{}'),
           (select count(*) from public.reports r2 join lateral private.report_target(r2.target_type, r2.target_id) t2 on true
             where t2.author = t.author)
    from public.reports r
    left join lateral private.report_target(r.target_type, r.target_id) t on true
    left join public.profiles p on p.id = t.author
    where not open_only or r.resolved_at is null
    order by r.created_at desc
    limit 200;
end $$;

-- Deletes reported content.
create or replace function private.remove_target(target_type text, target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  case target_type
    when 'message' then delete from public.messages where id = target;
    when 'serve' then delete from public.serves where id = target;
    when 'return' then delete from public.returns where id = target;
    when 'replay' then delete from public.replays where id = target;
    when 'match' then delete from public.matches where id = target;
    else null;
  end case;
end $$;

create or replace function public.admin_ban(target uuid, why text default '') returns void
language plpgsql security definer set search_path = public as $$
begin
  perform private.assert_admin();
  if private.is_admin(target) then raise exception 'cannot ban an admin'; end if;
  insert into public.bans (user_id, reason, banned_by) values (target, coalesce(why, ''), auth.uid())
  on conflict (user_id) do update set reason = excluded.reason;
  -- Supabase Auth refuses sign-in and refresh for banned users.
  begin
    execute 'update auth.users set banned_until = ''infinity'' where id = $1' using target;
    execute 'delete from auth.refresh_tokens where user_id = $1::text' using target;
    execute 'delete from auth.sessions where user_id = $1' using target;
  exception when others then
    raise notice 'auth ban step skipped: %', sqlerrm;
  end;
  delete from public.live_matches where host_id = target;
end $$;

create or replace function public.admin_unban(target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform private.assert_admin();
  delete from public.bans where user_id = target;
  begin
    execute 'update auth.users set banned_until = null where id = $1' using target;
  exception when others then
    raise notice 'auth unban step skipped: %', sqlerrm;
  end;
end $$;

create or replace function public.admin_resolve(report uuid, action text) returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.reports;
  who uuid;
begin
  perform private.assert_admin();
  select * into r from public.reports where id = report for update;
  if not found then raise exception 'no such report'; end if;
  if action not in ('dismissed','removed','banned') then raise exception 'unknown action'; end if;
  select author into who from private.report_target(r.target_type, r.target_id);
  if action in ('removed','banned') then
    perform private.remove_target(r.target_type, r.target_id);
  end if;
  if action = 'banned' and who is not null then
    perform public.admin_ban(who, r.reason);
  end if;
  -- Every open report on the same thing is settled together.
  update public.reports set resolved_at = now(), resolution = action
  where target_type = r.target_type and target_id = r.target_id and resolved_at is null;
end $$;

create or replace function public.admin_bans()
returns table (user_id uuid, name text, reason text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform private.assert_admin();
  return query select b.user_id, coalesce(p.display_name, 'Deleted'), b.reason, b.created_at
    from public.bans b left join public.profiles p on p.id = b.user_id order by b.created_at desc;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 3. Analytics and crash reports
--
-- Privacy-friendly on purpose: a random install ID (not the account), the
-- day, the device's region setting and the app version. No IP, no
-- location, no events inside the app. Enough to know which countries grow
-- and how many people come back each week.
-- ─────────────────────────────────────────────────────────────────────────

create table public.app_pings (
  install_id  uuid not null,
  day         date not null default current_date,
  country     text check (country ~ '^[A-Z]{2}$'),
  app_version text check (char_length(app_version) <= 20),
  locale      text check (char_length(locale) <= 12),
  first_seen  date,
  primary key (install_id, day)
);
alter table public.app_pings enable row level security;

create table public.crash_reports (
  id          uuid primary key default gen_random_uuid(),
  install_id  uuid not null,
  app_version text check (char_length(app_version) <= 20),
  os_version  text check (char_length(os_version) <= 40),
  device      text check (char_length(device) <= 40),
  kind        text not null check (kind in ('crash','hang','cpu','disk')),
  summary     text check (char_length(summary) <= 500),
  payload     jsonb,
  created_at  timestamptz not null default now(),
  check (pg_column_size(payload) < 200000)
);
alter table public.crash_reports enable row level security;

-- Once a day per install. Anyone may call it, signed in or not.
create or replace function public.ping(install uuid, country text, app_version text, locale text default null, first_seen date default null)
returns void language sql security definer set search_path = public as $$
  insert into public.app_pings (install_id, country, app_version, locale, first_seen)
  values (install, nullif(upper(country), ''), app_version, locale, first_seen)
  on conflict (install_id, day) do update set app_version = excluded.app_version
$$;

create or replace function public.report_crash(install uuid, app_version text, os_version text, device text,
                                               kind text, summary text, payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  -- A crash loop shouldn't flood the table: 20 a day per install.
  if (select count(*) from public.crash_reports where install_id = install and created_at > now() - interval '1 day') >= 20 then
    return;
  end if;
  insert into public.crash_reports (install_id, app_version, os_version, device, kind, summary, payload)
  values (install, app_version, os_version, device, kind, summary, payload);
end $$;

-- Kept for 13 months, as the privacy policy says. Runs nightly where
-- pg_cron is enabled (Supabase: Database → Extensions → pg_cron).
create or replace function private.purge_telemetry() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.app_pings where day < current_date - interval '13 months';
  delete from public.crash_reports where created_at < now() - interval '13 months';
  delete from public.share_links where expires_at < now() - interval '30 days';
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('purge-telemetry', '17 3 * * *', 'select private.purge_telemetry()');
  end if;
exception when others then
  raise notice 'cron schedule skipped: %', sqlerrm;
end $$;

-- The launch numbers: top countries, weekly actives, week-over-week
-- retention, and recent crashes.
create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  result jsonb;
begin
  perform private.assert_admin();
  with weeks as (
    select date_trunc('week', day)::date as week, install_id from public.app_pings group by 1, 2
  ), weekly as (
    select w.week, count(*) as active,
           count(*) filter (where exists (select 1 from weeks p where p.install_id = w.install_id and p.week = w.week - 7)) as back,
           (select count(*) from weeks p where p.week = w.week - 7) as previous
    from weeks w group by w.week
  )
  select jsonb_build_object(
    'countries', coalesce((select jsonb_agg(jsonb_build_object('country', country, 'installs', installs) order by installs desc)
                           from (select coalesce(country, '??') as country, count(distinct install_id) as installs
                                 from public.app_pings where day > current_date - 30 group by 1 order by 2 desc limit 10) c), '[]'),
    'weeks', coalesce((select jsonb_agg(jsonb_build_object('week', week, 'active', active, 'returning', back,
                                                           'retention', case when previous > 0 then round(back::numeric / previous, 3) end)
                                        order by week desc)
                       from (select * from weekly order by week desc limit 8) w), '[]'),
    'installs', (select count(distinct install_id) from public.app_pings),
    'crashes', coalesce((select jsonb_agg(jsonb_build_object('app_version', app_version, 'kind', kind, 'summary', summary,
                                                             'count', n, 'last', last) order by n desc)
                         from (select app_version, kind, summary, count(*) as n, max(created_at) as last
                               from public.crash_reports where created_at > now() - interval '14 days'
                               group by 1, 2, 3 order by 4 desc limit 20) c), '[]')
  ) into result;
  return result;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 4. Share links and public scoreboards
-- ─────────────────────────────────────────────────────────────────────────

create table public.share_links (
  token       text primary key default encode(gen_random_bytes(12), 'hex'),
  kind        text not null check (kind in ('match','tournament')),
  target_id   uuid not null,
  created_by  uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '30 days'
);
alter table public.share_links enable row level security;
create policy share_links_select on public.share_links for select to authenticated using (created_by = auth.uid());

create or replace function public.create_share_link(link_kind text, target uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  tok text;
begin
  perform private.assert_active();
  if link_kind = 'match' then
    if not (exists (select 1 from public.live_matches where match_id = target and host_id = me)
            or private.is_match_participant(target, me)) then
      raise exception 'not your match';
    end if;
  elsif link_kind = 'tournament' then
    if not exists (select 1 from public.tournaments t where t.id = target and private.is_squad_member(t.squad_id, me)) then
      raise exception 'not your tournament';
    end if;
  else
    raise exception 'unknown link kind';
  end if;
  select token into tok from public.share_links
  where kind = link_kind and target_id = target and created_by = me and expires_at > now() + interval '1 day';
  if tok is null then
    insert into public.share_links (kind, target_id, created_by) values (link_kind, target, me) returning token into tok;
  end if;
  return tok;
end $$;

-- The read-only view behind a share link. Names are first names only and
-- people are keyed by an opaque per-tournament hash, never their ID;
-- nothing else about them is exposed.
create or replace function private.first_name(pid uuid) returns text
language sql stable security definer set search_path = public as $$
  select split_part(coalesce((select display_name from public.players where id = pid), 'Player'), ' ', 1)
$$;

create or replace function public.public_scoreboard(tok text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  link public.share_links;
  live public.live_matches;
  mt public.matches;
  tr public.tournaments;
begin
  select * into link from public.share_links where token = tok and expires_at > now();
  if not found then return null; end if;

  if link.kind = 'match' then
    select * into live from public.live_matches where match_id = link.target_id;
    if found then
      return jsonb_build_object(
        'kind', 'match', 'live', true, 'sport', live.sport,
        'teams', jsonb_build_array(
          (select coalesce(jsonb_agg(split_part(p->>'displayName', ' ', 1)), '[]') from jsonb_array_elements(live.lineup->'teams'->'a') p),
          (select coalesce(jsonb_agg(split_part(p->>'displayName', ' ', 1)), '[]') from jsonb_array_elements(live.lineup->'teams'->'b') p)),
        'score', live.score, 'updated_at', live.updated_at);
    end if;
    select * into mt from public.matches where id = link.target_id;
    if not found then return jsonb_build_object('kind', 'match', 'live', false, 'gone', true); end if;
    return jsonb_build_object(
      'kind', 'match', 'live', false, 'sport', mt.sport, 'status', mt.status,
      'teams', jsonb_build_array(
        (select coalesce(jsonb_agg(private.first_name(player_id) order by slot), '[]') from public.match_participants where match_id = mt.id and team = 0),
        (select coalesce(jsonb_agg(private.first_name(player_id) order by slot), '[]') from public.match_participants where match_id = mt.id and team = 1)),
      'winner', mt.winner_team, 'units', mt.units, 'match_score', to_jsonb(mt.match_score), 'played_at', mt.started_at);
  end if;

  select * into tr from public.tournaments where id = link.target_id;
  if not found then return jsonb_build_object('kind', 'tournament', 'gone', true); end if;
  return jsonb_build_object(
    'kind', 'tournament', 'name', tr.name, 'sport', tr.sport, 'format', tr.format, 'status', tr.status,
    'champions', (select coalesce(jsonb_agg(private.first_name(c)), '[]') from unnest(tr.champions) c),
    'entrants', (select coalesce(jsonb_agg(jsonb_build_object('id', substr(md5(tr.id::text || player_id::text), 1, 10), 'name', private.first_name(player_id))), '[]')
                 from public.tournament_entrants where tournament_id = tr.id),
    'fixtures', (select coalesce(jsonb_agg(jsonb_build_object(
                   'round', f.round, 'court', f.court_number, 'stage', f.stage, 'slot', f.slot, 'pool', f.pool,
                   'scheduled_at', f.scheduled_at,
                   'team_a', (select jsonb_agg(jsonb_build_object('id', substr(md5(tr.id::text || x::text), 1, 10), 'name', private.first_name(x))) from unnest(f.team_a) x),
                   'team_b', (select jsonb_agg(jsonb_build_object('id', substr(md5(tr.id::text || x::text), 1, 10), 'name', private.first_name(x))) from unnest(f.team_b) x),
                   'winner', m.winner_team, 'units', m.units, 'confirmed', m.status = 'confirmed')
                   order by f.round, f.court_number), '[]')
                 from public.tournament_fixtures f left join public.matches m on m.id = f.match_id
                 where f.tournament_id = tr.id and (m.id is null or m.status <> 'disputed')));
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 5. Compete
-- ─────────────────────────────────────────────────────────────────────────

alter table public.tournaments drop constraint tournaments_format_check;
alter table public.tournaments add constraint tournaments_format_check
  check (format in ('round_robin','king_of_court','americano','mexicano','single_elimination','double_elimination','pools'));
alter table public.tournaments add column settings jsonb not null default '{}';

-- Where a fixture sits: pool play, the winners' or losers' bracket, the
-- final; its slot in the bracket and its pool.
alter table public.tournament_fixtures add column stage text not null default 'main'
  check (stage in ('main','pool','winners','losers','final','reset'));
alter table public.tournament_fixtures add column slot smallint;
alter table public.tournament_fixtures add column pool smallint;
-- Progressive formats set a slot, so two phones adding the same next
-- match at once can't create it twice (league fixtures leave it null).
alter table public.tournament_fixtures add constraint tournament_fixtures_place unique (tournament_id, stage, round, slot);


-- Tournaments carry their settings (pool count, bracket size, points per
-- Mexicano round) and fixtures their stage. Brackets add each round's
-- fixtures as the one before finishes, like King of the Court.
create or replace function public.create_tournament(t jsonb, entrants jsonb, fixtures jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  tid uuid;
  e jsonb;
  f jsonb;
  conv uuid;
begin
  perform private.assert_active();
  if not private.is_squad_member((t->>'squad_id')::uuid, me) then raise exception 'not a squad member'; end if;
  if jsonb_array_length(entrants) > 64 then raise exception 'too many entrants'; end if;
  if jsonb_array_length(fixtures) > 500 then raise exception 'too many fixtures'; end if;
  insert into public.tournaments (squad_id, name, sport, format, rules, settings, created_by)
  values ((t->>'squad_id')::uuid, t->>'name', t->>'sport', t->>'format', t->'rules',
          coalesce(t->'settings', '{}'::jsonb), me)
  returning id into tid;

  for e in select * from jsonb_array_elements(entrants) loop
    if (e->>'kind') = 'guest' then
      insert into public.players (id, kind, display_name, created_by)
      values ((e->>'player_id')::uuid, 'guest', e->>'display_name', me) on conflict (id) do nothing;
      if not exists (select 1 from public.players where id = (e->>'player_id')::uuid and kind = 'guest') then
        raise exception 'entrants must be squad members or guests';
      end if;
    elsif not private.is_squad_member((t->>'squad_id')::uuid, (e->>'player_id')::uuid) then
      raise exception 'entrants must be squad members or guests';
    end if;
    insert into public.tournament_entrants (tournament_id, player_id) values (tid, (e->>'player_id')::uuid);
  end loop;

  for f in select * from jsonb_array_elements(fixtures) loop
    insert into public.tournament_fixtures (id, tournament_id, round, court_number, team_a, team_b, scheduled_at, court,
                                            stage, slot, pool)
    values (coalesce((f->>'id')::uuid, gen_random_uuid()), tid, (f->>'round')::smallint,
      coalesce((f->>'court_number')::smallint, 1),
      array(select jsonb_array_elements_text(f->'team_a')::uuid),
      array(select jsonb_array_elements_text(f->'team_b')::uuid),
      (f->>'scheduled_at')::timestamptz, f->'court',
      coalesce(f->>'stage', 'main'), (f->>'slot')::smallint, (f->>'pool')::smallint);
  end loop;
  if exists (select 1 from public.tournament_fixtures fx, unnest(fx.team_a || fx.team_b) as x(pid)
             where fx.tournament_id = tid
               and x.pid not in (select te.player_id from public.tournament_entrants te where te.tournament_id = tid)) then
    raise exception 'fixtures must use entrants';
  end if;

  select id into conv from public.conversations where squad_id = (t->>'squad_id')::uuid;
  insert into public.messages (conversation_id, kind, payload)
  values (conv, 'event', jsonb_build_object('type', 'tournament_created', 'tournament_id', tid));
  return tid;
end $$;

-- Fixtures added later also only use entrants.
drop policy tournament_fixtures_insert on public.tournament_fixtures;
create policy tournament_fixtures_insert on public.tournament_fixtures for insert to authenticated
  with check (match_id is null
    and exists (select 1 from public.tournaments t where t.id = tournament_id
                and t.status = 'active' and private.is_squad_member(t.squad_id, auth.uid()))
    and (team_a || team_b) <@ array(select te.player_id from public.tournament_entrants te
                                    where te.tournament_id = tournament_fixtures.tournament_id));

-- ─────────────────────────────────────────────────────────────────────────
-- Account deletion
--
-- The app removes the account's files from Storage first (Storage's API,
-- not SQL, owns object deletion), then calls this. Everything the account
-- owns cascades from auth.users; matches stay for the other players, with
-- this player shown as "Former player".
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.delete_account() returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  delete from public.messages where sender_id = me;
  delete from public.live_matches where host_id = me;
  delete from public.share_links where created_by = me;
  update public.players set display_name = 'Former player' where id = me;
  update public.players set claimed_by = null, display_name = 'Former player' where claimed_by = me;
  delete from auth.users where id = me;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- Grants
-- ─────────────────────────────────────────────────────────────────────────

revoke all on public.bans, public.app_pings, public.crash_reports from anon, authenticated;
grant select, insert, delete on public.share_links to authenticated;
revoke execute on all functions in schema public from anon, public;
grant execute on all functions in schema public to authenticated, service_role;
revoke execute on all functions in schema private from anon, public;
grant execute on all functions in schema private to authenticated, service_role;
revoke execute on function private.finalize_match(uuid, uuid, jsonb),
                           private.ensure_direct_conversation(uuid, uuid),
                           private.remove_target(text, uuid),
                           private.report_target(text, uuid),
                           private.purge_telemetry() from authenticated;
-- The web scoreboard and the launch pings work without an account.
grant usage on schema public to anon;
grant execute on function public.public_scoreboard(text), public.ping(uuid, text, text, text, date),
                          public.report_crash(uuid, text, text, text, text, text, jsonb) to anon;
