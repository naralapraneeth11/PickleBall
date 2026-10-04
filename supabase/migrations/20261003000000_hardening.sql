-- ─────────────────────────────────────────────────────────────────────────
-- PickleBall · Migration 3: release hardening
--
-- Fixes from the release-readiness audit. Run after the first two
-- migrations; safe to run on a project that already has them.
--
--   H1. Guests can't be created already claimed by someone else.
--   H2. Blocking hides each other's messages and chat photos in shared
--       squads too (direct chats already did).
--   H3. save_match checks what it's given: rules, players, sides, scores,
--       dates and size. Broken matches are refused instead of stored.
--   H4. Workout and heart-rate data never live on the shared match row.
--       Existing values are wiped and a check keeps it that way.
--   H5. Account deletion: one routine for the app and for the
--       delete-account Edge Function (which also cleans Storage and
--       revokes Sign in with Apple). Workout data is scrubbed first.
--   H6. Avatars: owners can read their own folder, so uploads that
--       replace a photo and deletion's file listing work.
--   H7. Realtime: the per-user channel is private (works with "Private
--       channels only"), and squad members and Replays are published.
-- ─────────────────────────────────────────────────────────────────────────

-- ── H1. Guest claims only through invites ───────────────────────────────

drop policy if exists players_insert on public.players;
create policy players_insert on public.players for insert to authenticated
  with check (kind = 'guest' and created_by = auth.uid() and claimed_by is null);

-- ── H2. Blocks apply inside shared squads ───────────────────────────────

drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages for select to authenticated
  using (
    private.is_conversation_member(conversation_id, auth.uid())
    -- Squad events (sender_id null) and your own messages always show;
    -- someone you blocked, or who blocked you, doesn't.
    and (sender_id is null or sender_id = auth.uid() or not private.is_blocked(sender_id, auth.uid()))
  );

drop policy if exists media_read on storage.objects;
create policy media_read on storage.objects for select to authenticated
  using (bucket_id = 'media' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or private.is_admin(auth.uid())
    or case
         when (storage.foldername(name))[2] = 'chat'
           then private.is_conversation_member(private.try_uuid((storage.foldername(name))[3]), auth.uid())
                and not private.is_blocked(private.try_uuid((storage.foldername(name))[1]), auth.uid())
         else private.can_see_user(auth.uid(), private.try_uuid((storage.foldername(name))[1]))
       end
  ));

-- ── H3. Match validation ────────────────────────────────────────────────

-- True when `r` is a CourtKit MatchRules value the apps can decode.
create or replace function private.valid_rules(r jsonb, sport text) returns boolean
language sql immutable as $$
  select case
    when jsonb_typeof(r) <> 'object' then false
    when r->>'kind' in ('pickleballSideOut', 'pickleballRally') then
      sport = 'pickleball'
      and jsonb_typeof(r->'pickleball') = 'object'
      and jsonb_typeof(r->'pickleball'->'pointsToWin') = 'number'
      and (r->'pickleball'->>'pointsToWin')::numeric between 1 and 50
      and jsonb_typeof(r->'pickleball'->'winBy') = 'number'
      and (r->'pickleball'->>'winBy')::numeric between 1 and 5
      and jsonb_typeof(r->'pickleball'->'gamesToWin') = 'number'
      and (r->'pickleball'->>'gamesToWin')::numeric between 1 and 5
      and jsonb_typeof(r->'pickleball'->'isDoubles') = 'boolean'
      and r->'pickleball'->>'firstServer' in ('0', '1')
      and r->'pickleball' ? 'startingRightCourt'
      and (not r->'pickleball' ? 'pointCap' or jsonb_typeof(r->'pickleball'->'pointCap') in ('number', 'null'))
    when r->>'kind' = 'padel' then
      sport = 'padel'
      and jsonb_typeof(r->'padel') = 'object'
      and jsonb_typeof(r->'padel'->'setsToWin') = 'number'
      and (r->'padel'->>'setsToWin')::numeric between 1 and 3
      and jsonb_typeof(r->'padel'->'gamesPerSet') = 'number'
      and (r->'padel'->>'gamesPerSet')::numeric between 1 and 9
      and jsonb_typeof(r->'padel'->'tiebreakPoints') = 'number'
      and (r->'padel'->>'tiebreakPoints')::numeric between 1 and 21
      and r->'padel'->>'deuceRule' in ('advantage', 'goldenPoint', 'starPoint')
      and r->'padel' ? 'decidingSet'
      and jsonb_typeof(r->'padel'->'isDoubles') = 'boolean'
      and r->'padel'->>'firstServer' in ('0', '1')
      and r->'padel' ? 'firstServerIndex'
    else false
  end
$$;

-- Raises when a match payload is malformed. Called before anything is written.
create or replace function private.validate_match(m jsonb, participants jsonb) returns void
language plpgsql stable as $$
declare
  doubles boolean;
  per_side int;
  a_count int;
  b_count int;
begin
  if pg_column_size(m) + pg_column_size(participants) > 65536 then
    raise exception 'match is too large';
  end if;
  if (m->>'sport') not in ('pickleball', 'padel') then raise exception 'unknown sport'; end if;
  if (m->>'source') not in ('watch', 'phone', 'entered') then raise exception 'unknown source'; end if;
  if not private.valid_rules(m->'rules', m->>'sport') then raise exception 'invalid rules'; end if;

  -- Sides: one or two players each, the same on both sides, matching the rules.
  if jsonb_typeof(participants) <> 'array' then raise exception 'invalid players'; end if;
  doubles := coalesce((m->'rules'->'pickleball'->>'isDoubles')::boolean, (m->'rules'->'padel'->>'isDoubles')::boolean);
  per_side := case when doubles then 2 else 1 end;
  select count(*) filter (where x->>'team' = '0'), count(*) filter (where x->>'team' = '1')
    into a_count, b_count
  from jsonb_array_elements(participants) x;
  if a_count <> per_side or b_count <> per_side
     or jsonb_array_length(participants) <> per_side * 2 then
    raise exception 'each side needs % player(s)', per_side;
  end if;
  if exists (select 1 from jsonb_array_elements(participants) x
             where (x->>'slot') is null or (x->>'slot')::int not between 0 and 1
                or (x->>'player_id') is null) then
    raise exception 'invalid players';
  end if;
  if (select count(distinct x->>'player_id') from jsonb_array_elements(participants) x) <> per_side * 2 then
    raise exception 'a player can only appear once';
  end if;

  -- Scores and dates.
  if (m->>'winner_team') is not null and (m->>'winner_team') not in ('0', '1') then
    raise exception 'invalid winner';
  end if;
  if exists (select 1 from jsonb_array_elements_text(coalesce(m->'match_score', '[]')) v where v::numeric not between 0 and 9)
     or exists (select 1 from jsonb_array_elements_text(coalesce(m->'points', '[]')) v where v::numeric not between 0 and 2000) then
    raise exception 'invalid score';
  end if;
  if jsonb_typeof(coalesce(m->'units', '[]')) <> 'array' or jsonb_array_length(coalesce(m->'units', '[]')) > 9 then
    raise exception 'invalid games';
  end if;
  if (m->>'started_at') is null or (m->>'started_at')::timestamptz > now() + interval '1 day'
     or (m->>'started_at')::timestamptz < now() - interval '2 years' then
    raise exception 'invalid date';
  end if;
  if (m->>'ended_at') is not null and (m->>'ended_at')::timestamptz < (m->>'started_at')::timestamptz then
    raise exception 'invalid date';
  end if;
  if length(coalesce(m->>'rally_winners', '')) > 2000 then raise exception 'too many rallies'; end if;
  if jsonb_typeof(m->'rally_offsets') = 'array'
     and jsonb_array_length(m->'rally_offsets') <> length(coalesce(m->>'rally_winners', '')) then
    raise exception 'rally log mismatch';
  end if;
end $$;

-- save_match as in migration 2, plus validation, and without workouts.
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
  perform private.validate_match(m, participants);

  if tournament is not null then
    select squad_id into squad from public.tournaments where id = tournament;
  end if;
  if squad is not null and not private.is_squad_member(squad, me) then
    raise exception 'not a squad member';
  end if;
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

  for p in select * from jsonb_array_elements(participants) loop
    pid := (p->>'player_id')::uuid;
    select * into pl from public.players where id = pid;
    if not found then
      if (p->>'kind') is distinct from 'guest' then raise exception 'unknown player %', pid; end if;
      insert into public.players (id, kind, display_name, created_by)
      values (pid, 'guest', left(coalesce(nullif(p->>'display_name', ''), 'Guest'), 40), me);
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
    m->'court', squad, tournament, (m->>'fixture_id')::uuid, (m->>'callout_id')::uuid, null)
  on conflict (id) do update set
    rules = excluded.rules, ended_at = excluded.ended_at, winner_team = excluded.winner_team,
    match_score = excluded.match_score, points = excluded.points, units = excluded.units,
    rally_winners = excluded.rally_winners, rally_offsets = excluded.rally_offsets,
    court = excluded.court, workout = null, status = 'pending';

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
    update public.match_participants set confirmed_at = now()
    where match_id = mid and team = scorer_team;
    select exists (
      select 1 from public.match_participants mp
      where mp.match_id = mid and mp.team <> scorer_team and private.player_user(mp.player_id) is not null
    ) into needs_confirmation;
  else
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

-- ── H4. No health data on shared rows ───────────────────────────────────

update public.matches set workout = null where workout is not null;
alter table public.matches drop constraint if exists matches_no_workout;
alter table public.matches add constraint matches_no_workout check (workout is null);
comment on column public.matches.workout is
  'Unused. Workout and heart-rate data stay on the player''s devices; a Replay only shares what the player chooses.';

-- ── H5. Account deletion ────────────────────────────────────────────────

-- Removes one account's data. Matches stay for the other players with this
-- player shown as "Former player"; nothing personal is left on them.
create or replace function private.delete_user(target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if target is null then raise exception 'no account'; end if;
  update public.matches set workout = null where created_by = target and workout is not null;
  update public.matches set court = null where created_by = target;
  delete from public.messages where sender_id = target;
  delete from public.live_matches where host_id = target;
  delete from public.share_links where created_by = target;
  update public.players set display_name = 'Former player' where id = target;
  update public.players set claimed_by = null, display_name = 'Former player' where claimed_by = target;
  delete from auth.users where id = target;
end $$;

create or replace function public.delete_account() returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  perform private.delete_user(me);
end $$;

-- For the delete-account Edge Function, which runs with the service role
-- after it has removed the account's files and revoked Sign in with Apple.
create or replace function public.delete_account_as_service(target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform private.delete_user(target);
end $$;

revoke execute on function private.delete_user(uuid) from public, anon, authenticated;
revoke execute on function public.delete_account_as_service(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_as_service(uuid) to service_role;

-- ── H6. Avatar owners can read their folder ─────────────────────────────

drop policy if exists avatars_read_own on storage.objects;
create policy avatars_read_own on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ── H7. Realtime ────────────────────────────────────────────────────────

do $$
declare
  t text;
begin
  foreach t in array array['squad_members', 'replays'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- The app's own channel "user-<id>" is private: only that user may join.
-- Table changes on it are still filtered by each table's row security.
do $$
begin
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'realtime' and c.relname = 'messages') then
    execute 'drop policy if exists user_channel_read on realtime.messages';
    execute $p$
      create policy user_channel_read on realtime.messages for select to authenticated
      using (realtime.topic() = 'user-' || auth.uid()::text)
    $p$;
  end if;
exception when others then
  raise notice 'realtime policy skipped: %', sqlerrm;
end $$;

-- ── Grants for the new functions ────────────────────────────────────────

revoke execute on function private.valid_rules(jsonb, text), private.validate_match(jsonb, jsonb) from public, anon;
grant execute on function private.valid_rules(jsonb, text), private.validate_match(jsonb, jsonb) to authenticated, service_role;
