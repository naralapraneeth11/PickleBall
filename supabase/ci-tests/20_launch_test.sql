-- Behaviour tests for the Phase 3 launch migration: the security review
-- fixes, moderation, analytics, share links and the new formats.
--
-- Cast: ada is an admin; ben and cat are friends; ben and zed are friends
-- but zed and cat are not; ivy is a stranger. Helpers come from
-- 10_social_core_test.sql.

\o /dev/null
\set ON_ERROR_STOP 1

\set ada '00000000-0000-0000-0000-0000000000a1'
\set ben '00000000-0000-0000-0000-0000000000b1'
\set cat '00000000-0000-0000-0000-0000000000c1'
\set zed '00000000-0000-0000-0000-0000000000d1'
\set ivy '00000000-0000-0000-0000-0000000000e1'

\set as_admin 'reset role; set request.jwt.claim.sub = '''';'
\set as_anon  'reset role; set request.jwt.claim.sub = ''''; set role anon;'
\set as_ada   'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-0000000000a1''; set role authenticated;'
\set as_ben   'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-0000000000b1''; set role authenticated;'
\set as_cat   'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-0000000000c1''; set role authenticated;'
\set as_zed   'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-0000000000d1''; set role authenticated;'
\set as_ivy   'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-0000000000e1''; set role authenticated;'

-- ── Cast ─────────────────────────────────────────────────────────────────

:as_admin
insert into auth.users (id, email) values
  (:'ada', 'ada@example.com'), (:'ben', 'ben@example.com'), (:'cat', 'cat@example.com'),
  (:'zed', 'zed@example.com'), (:'ivy', 'ivy@example.com');
insert into public.profiles (id, username, display_name) values
  (:'ada', 'ada', 'Ada Admin'), (:'ben', 'ben', 'Ben Baker'), (:'cat', 'cat', 'Cat Cruz'),
  (:'zed', 'zed', 'Zed'), (:'ivy', 'ivy', 'Ivy');
insert into private.admins (user_id) values (:'ada');
insert into auth.sessions (id, user_id) values ('30000000-0000-0000-0000-000000000001', :'ben');
insert into auth.refresh_tokens (user_id, session_id) values (:'ben', '30000000-0000-0000-0000-000000000001');

:as_ben
select public.request_friend(:'cat');
select public.request_friend(:'zed');
:as_cat
select public.respond_friend(:'ben', true);
:as_zed
select public.respond_friend(:'ben', true);
:as_ben
select public.create_squad('Night Owls', array[:'cat']::uuid[]) as squad \gset

-- ── F1: guests can be renamed, never handed to someone else ─────────────

:as_ben
insert into public.players (id, kind, display_name, created_by)
values ('00000000-0000-0000-0000-0000000000f7', 'guest', 'Pat', :'ben');
select test.throws(format($$update public.players set claimed_by = %L where id = '00000000-0000-0000-0000-0000000000f7'$$, :'ivy'),
  'permission denied', 'a guest cannot be given to another account');
update public.players set display_name = 'Patty' where id = '00000000-0000-0000-0000-0000000000f7';
select test.eq((select display_name from public.players where id = '00000000-0000-0000-0000-0000000000f7'), 'Patty',
  'a guest can still be renamed');

-- ── F2: confirmations can't post forged chat events ─────────────────────

:as_ben
select public.save_match(test.match('40000000-0000-0000-0000-000000000001'),
  jsonb_build_array(test.p(:'ben', 0), test.p(:'cat', 1)));
:as_cat
select test.eq(public.confirm_match('40000000-0000-0000-0000-000000000001', true,
  jsonb_build_array(
    jsonb_build_object('type', 'result', 'match_id', '40000000-0000-0000-0000-00000000ffff'),
    jsonb_build_object('type', 'callout', 'text', 'fake'),
    jsonb_build_object('type', 'belt', 'kind', 'won'))), 'confirmed', 'match confirmed with events');
select test.eq(test.events(test.dm(:'ben', :'cat'), 'result'), 1::bigint, 'only the real result is posted');
select test.eq(test.events(test.dm(:'ben', :'cat'), 'callout'), 0::bigint, 'forged event types are dropped');
select test.eq(test.events(test.dm(:'ben', :'cat'), 'belt'), 1::bigint, 'belt events still travel');
select test.eq((select payload->>'match_id' from public.messages where conversation_id = test.dm(:'ben', :'cat')
                and payload->>'type' = 'belt'), '40000000-0000-0000-0000-000000000001', 'belt events name their match');

-- ── F3: matches only link to what they belong to ────────────────────────

:as_ben
select public.create_tournament(
  jsonb_build_object('squad_id', :'squad', 'name', 'Owl Cup', 'sport', 'padel', 'format', 'double_elimination',
                     'rules', '{}'::jsonb, 'settings', '{"seeds": 4}'::jsonb),
  jsonb_build_array(jsonb_build_object('player_id', :'ben'), jsonb_build_object('player_id', :'cat'),
                    jsonb_build_object('player_id', '00000000-0000-0000-0000-0000000000f8', 'kind', 'guest', 'display_name', 'Robin Hood')),
  jsonb_build_array(jsonb_build_object('id', '50000000-0000-0000-0000-000000000001', 'round', 1, 'stage', 'winners', 'slot', 0,
                                       'team_a', jsonb_build_array(:'ben'), 'team_b', jsonb_build_array(:'cat')))
) as cup \gset
select test.eq((select settings->>'seeds' from public.tournaments where id = :'cup'), '4', 'tournaments keep their settings');
select test.eq((select stage from public.tournament_fixtures where id = '50000000-0000-0000-0000-000000000001'), 'winners',
  'fixtures know their bracket');
select test.throws(format($$select public.create_tournament(jsonb_build_object('squad_id', %L, 'name', 'x', 'sport', 'padel', 'format', 'mexicano', 'rules', '{}'::jsonb), jsonb_build_array(jsonb_build_object('player_id', %L)), jsonb_build_array(jsonb_build_object('round', 1, 'team_a', jsonb_build_array(%L), 'team_b', jsonb_build_array(%L))))$$,
  :'squad', :'ben', :'ben', :'ivy'), 'fixtures must use entrants', 'fixtures only use entrants');
select test.throws(format($$select public.create_tournament(jsonb_build_object('squad_id', %L, 'name', 'x', 'sport', 'padel', 'format', 'swiss', 'rules', '{}'::jsonb), '[]', '[]')$$,
  :'squad'), 'tournaments_format_check', 'unknown formats are refused');
select test.throws(format($$select public.create_tournament(jsonb_build_object('squad_id', %L, 'name', 'x', 'sport', 'padel', 'format', 'pools', 'rules', '{}'::jsonb), jsonb_build_array(jsonb_build_object('player_id', %L, 'kind', 'guest', 'display_name', 'x')), '[]')$$,
  :'squad', :'cat'), 'squad members or guests', 'a real account cannot be entered as a guest');

-- A tournament ID with someone else's fixture.
select test.throws(format($$select public.save_match(test.match('40000000-0000-0000-0000-000000000002', jsonb_build_object('tournament_id', %L, 'fixture_id', gen_random_uuid())), jsonb_build_array(test.p(%L, 0), test.p(%L, 1)))$$,
  :'cup', :'ben', :'cat'), 'fixture is not part of this tournament', 'fixtures must belong to the tournament');

-- Fixtures added later: never pre-linked to a match, only entrants.
select test.throws(format($$insert into public.tournament_fixtures (tournament_id, round, team_a, team_b, match_id) values (%L, 2, array[%L]::uuid[], array[%L]::uuid[], '40000000-0000-0000-0000-000000000001')$$,
  :'cup', :'ben', :'cat'), 'row-level security', 'added fixtures cannot claim a match');
select test.throws(format($$insert into public.tournament_fixtures (tournament_id, round, team_a, team_b) values (%L, 2, array[%L]::uuid[], array[%L]::uuid[])$$,
  :'cup', :'ben', :'ivy'), 'row-level security', 'added fixtures only use entrants');
insert into public.tournament_fixtures (tournament_id, round, stage, slot, team_a, team_b)
values (:'cup', 2, 'losers', 0, array[:'cat']::uuid[], array['00000000-0000-0000-0000-0000000000f8']::uuid[]);
select test.throws(format($$insert into public.tournament_fixtures (tournament_id, round, stage, slot, team_a, team_b) values (%L, 2, 'losers', 0, array[%L]::uuid[], array[%L]::uuid[])$$,
  :'cup', :'cat', :'ben'), 'tournament_fixtures_place', 'the same bracket match is only added once');
insert into public.tournament_fixtures (tournament_id, round, stage, slot, team_a, team_b)
values (:'cup', 2, 'losers', 0, array[:'cat']::uuid[], array[:'ben']::uuid[])
on conflict (tournament_id, stage, round, slot) do nothing;
select test.eq((select count(*) from public.tournament_fixtures where tournament_id = :'cup'), 2::bigint,
  'a second phone adding it again is a no-op');
select test.throws(format($$update public.tournament_fixtures set match_id = '40000000-0000-0000-0000-000000000001' where tournament_id = %L$$, :'cup'),
  'permission denied', 'fixtures cannot be relinked');

-- Champions come from the entrants.
select test.throws(format($$select public.complete_tournament(%L, array[%L]::uuid[])$$, :'cup', :'zed'),
  'champions must be entrants', 'outsiders cannot be crowned');

-- ── F4: call outs name the caller and their friends ─────────────────────

:as_zed
select test.throws(format($$select public.create_callout(jsonb_build_object('challengers', jsonb_build_array(%L), 'challenged', jsonb_build_array(%L), 'sport', 'padel', 'rules', '{}'::jsonb))$$,
  :'cat', :'ben'), 'one of the challengers', 'you cannot call out on someone else''s behalf');
select test.throws(format($$select public.create_callout(jsonb_build_object('challengers', jsonb_build_array(%L, %L), 'challenged', jsonb_build_array(%L, %L), 'sport', 'padel', 'rules', '{}'::jsonb))$$,
  :'zed', :'ivy', :'ben', :'ben'), 'partner must be a friend', 'partners are friends');
select test.throws(format($$select public.create_callout(jsonb_build_object('challengers', jsonb_build_array(%L), 'challenged', jsonb_build_array(%L), 'sport', 'padel', 'rules', '{}'::jsonb, 'squad_id', %L))$$,
  :'zed', :'ben', :'squad'), 'not a squad member', 'squad call outs come from the squad');

-- ── F6: updates are narrowed to the columns the app edits ───────────────

:as_ben
select test.throws(format($$update public.squads set created_by = %L where id = %L$$, :'ivy', :'squad'),
  'permission denied', 'squad owners cannot be rewritten');
update public.squads set name = 'Night Owls II' where id = :'squad';
select test.eq((select name from public.squads where id = :'squad'), 'Night Owls II', 'squads can be renamed');
select test.throws($$update public.profiles set created_at = now() - interval '9 years' where id = auth.uid()$$,
  'permission denied', 'profile bookkeeping is read-only');
update public.profiles set levels = '{"padel": 3.4}' where id = :'ben';
select test.eq((select levels->>'padel' from public.profiles where id = :'ben'), '3.4', 'levels are published');
select test.throws($$update public.profiles set levels = '[1]' where id = auth.uid()$$, 'profiles_levels_check',
  'levels are a map');
select test.throws(format($$insert into public.replays (match_id, author_id, story, saved) values ('40000000-0000-0000-0000-000000000001', %L, '{}', true)$$, :'ben'),
  'row-level security', 'replays start unsaved');
select test.throws(format($$insert into public.replays (match_id, author_id, story, expires_at) values ('40000000-0000-0000-0000-000000000001', %L, '{}', now() + interval '1 year')$$, :'ben'),
  'row-level security', 'replays expire within a day');
insert into public.replays (match_id, author_id, story) values ('40000000-0000-0000-0000-000000000001', :'ben', '{}');
select test.throws($$update public.replays set expires_at = now() + interval '1 year'$$, 'permission denied',
  'replays are only saved through save_replay');

-- ── F7: chat photos stay in the chat ─────────────────────────────────────

:as_admin
insert into storage.objects (bucket_id, name) values
  ('media', :'ben' || '/chat/' || test.dm(:'ben', :'cat') || '/a.jpg'),
  ('media', :'ben' || '/serves/b.jpg'),
  ('media', :'ben' || '/chat/not-a-uuid/c.jpg');
:as_cat
select test.eq((select count(*) from storage.objects where name like '%/chat/%'), 1::bigint, 'chat members see chat photos');
:as_zed
select test.eq((select count(*) from storage.objects where name like '%/chat/%'), 0::bigint, 'friends outside the chat do not');
select test.eq((select count(*) from storage.objects where name like '%/serves/%'), 1::bigint, 'friends see other media');
:as_ivy
select test.eq((select count(*) from storage.objects where bucket_id = 'media'), 0::bigint, 'strangers see nothing');
:as_ada
select test.eq((select count(*) from storage.objects where bucket_id = 'media' and name like :'ben' || '/%'), 3::bigint, 'admins can review media');

-- ── Moderation ───────────────────────────────────────────────────────────

:as_zed
insert into public.serves (author_id, kind, body) values (:'zed', 'text', 'rude words') returning id as rude \gset
:as_ben
insert into public.reports (reporter, target_type, target_id, reason) values (:'ben', 'serve', :'rude', 'harassment')
returning id as report \gset
insert into public.reports (reporter, target_type, target_id, reason) values (:'ben', 'user', :'zed', 'harassment');
select test.eq(public.is_admin(), false, 'players are not admins');
select test.throws($$select * from public.admin_reports()$$, 'admins only', 'players cannot read reports');
select test.throws(format($$select public.admin_ban(%L)$$, :'zed'), 'admins only', 'players cannot ban');
select test.throws($$select public.admin_stats()$$, 'admins only', 'players cannot read stats');
select test.throws($$select count(*) from public.bans$$, 'permission denied', 'bans are private');

:as_ada
select test.eq(public.is_admin(), true, 'admins know they are admins');
select test.eq((select body from public.admin_reports() where id = :'report'), 'rude words', 'admins see what was reported');
select test.eq((select author from public.admin_reports() where id = :'report'), :'zed'::uuid, 'and who wrote it');
select test.eq((select author_reports from public.admin_reports() where id = :'report'), 2::bigint, 'and how often they were reported');
select test.throws(format($$select public.admin_ban(%L)$$, :'ada'), 'cannot ban an admin', 'admins cannot be banned');
select public.admin_resolve(:'report', 'banned');
select test.eq((select count(*) from public.serves where id = :'rude'), 0::bigint, 'reported Serve removed');
select test.eq((select count(*) from public.admin_reports() where reporter = :'ben'), 1::bigint, 'resolved reports leave the queue');
select test.eq((select count(*) from public.admin_bans() where user_id = :'zed'), 1::bigint, 'ban recorded');
:as_admin
select test.eq((select banned_until from auth.users where id = :'zed'), 'infinity'::timestamptz, 'auth refuses the banned account');

:as_zed
select test.throws(format($$select public.request_friend(%L)$$, :'ivy'), 'account suspended', 'banned accounts cannot act');
select test.throws(format($$select public.save_match(test.match('40000000-0000-0000-0000-000000000003'), jsonb_build_array(test.p(%L, 0), test.p(%L, 1)))$$,
  :'zed', :'ben'), 'account suspended', 'banned accounts cannot record matches');
select test.throws(format($$insert into public.serves (author_id, kind, body) values (%L, 'text', 'hi')$$, :'zed'),
  'row-level security', 'banned accounts cannot post');

:as_ada
select public.admin_unban(:'zed');
:as_zed
insert into public.serves (author_id, kind, body) values (:'zed', 'text', 'sorry') returning id as serve \gset
select test.ok(:'serve' is not null, 'unbanned accounts can post again');

-- A ban also ends sessions.
:as_ada
select public.admin_ban(:'ivy', 'spam');
select public.admin_ban(:'ben', 'testing');
:as_admin
select test.eq((select count(*) from auth.sessions where user_id = :'ben'), 0::bigint, 'bans end sessions');
select test.eq((select count(*) from auth.refresh_tokens where user_id = :'ben'), 0::bigint, 'and refresh tokens');
:as_ada
select public.admin_unban(:'ben');

-- ── Friend request spam ──────────────────────────────────────────────────

:as_admin
insert into auth.users (id) select ('00000000-0000-0000-0000-0000001' || lpad(i::text, 5, '0'))::uuid from generate_series(1, 51) i;
insert into public.profiles (id, username, display_name)
select ('00000000-0000-0000-0000-0000001' || lpad(i::text, 5, '0'))::uuid, 'fan' || i, 'Fan' from generate_series(1, 51) i;
:as_cat
select public.request_friend(('00000000-0000-0000-0000-0000001' || lpad(i::text, 5, '0'))::uuid) from generate_series(1, 50) i;
select test.throws($$select public.request_friend('00000000-0000-0000-0000-000000100051')$$, 'too many pending requests',
  'pending friend requests are capped');

-- ── Analytics and crashes (no account needed, nothing readable) ─────────

:as_anon
select public.ping('60000000-0000-0000-0000-000000000001', 'es', '1.0', 'es_ES', current_date);
select public.ping('60000000-0000-0000-0000-000000000001', 'ES', '1.0.1', 'es_ES');
select public.ping('60000000-0000-0000-0000-000000000002', 'BR', '1.0', 'pt_BR');
select test.throws($$select count(*) from public.app_pings$$, 'permission denied', 'pings are write-only');
select test.throws($$select public.ping('60000000-0000-0000-0000-000000000003', 'Spain', '1.0')$$, 'app_pings_country_check',
  'countries are region codes');
select public.report_crash('60000000-0000-0000-0000-000000000001', '1.0', 'iOS 26.1', 'iPhone17,1', 'crash', 'EXC_BAD_ACCESS', '{}')
from generate_series(1, 25);
select test.throws($$select count(*) from public.crash_reports$$, 'permission denied', 'crash reports are write-only');
select test.throws($$select public.admin_stats()$$, 'permission denied', 'stats need an account');
:as_admin
select test.eq((select count(*) from public.app_pings), 2::bigint, 'one ping per install per day');
select test.eq((select app_version from public.app_pings where install_id = '60000000-0000-0000-0000-000000000001'), '1.0.1',
  'the latest version wins');
select test.eq((select count(*) from public.crash_reports), 20::bigint, 'crash loops are capped');
:as_ada
select test.eq(jsonb_array_length(public.admin_stats()->'countries'), 2, 'stats list countries');
select test.eq(public.admin_stats()->'weeks'->0->>'active', '2', 'stats count weekly actives');
select test.eq(public.admin_stats()->'crashes'->0->>'count', '20', 'stats group crashes');

-- ── Share links and the public scoreboard ────────────────────────────────

:as_ben
insert into public.live_matches (match_id, host_id, sport, player_ids, lineup, score)
values ('40000000-0000-0000-0000-000000000009', :'ben', 'pickleball', array[:'ben', :'cat']::uuid[],
  '{"teams":{"a":[{"id":"00000000-0000-0000-0000-0000000000b1","kind":"user","displayName":"Ben Baker"}],"b":[{"id":"00000000-0000-0000-0000-0000000000c1","kind":"user","displayName":"Cat Cruz"}]}}',
  '{"points":{"a":"7","b":"4"}}');
select public.create_share_link('match', '40000000-0000-0000-0000-000000000009') as live_link \gset
select test.eq(public.create_share_link('match', '40000000-0000-0000-0000-000000000009'), :'live_link', 'share links are reused');
select public.create_share_link('match', '40000000-0000-0000-0000-000000000001') as done_link \gset
select public.create_share_link('tournament', :'cup') as cup_link \gset
:as_ivy
select test.throws($$select public.create_share_link('match', '40000000-0000-0000-0000-000000000009')$$, 'account suspended',
  'banned accounts cannot share');
:as_zed
select test.throws($$select public.create_share_link('match', '40000000-0000-0000-0000-000000000001')$$, 'not your match',
  'only players share a match');
select test.throws(format($$select public.create_share_link('tournament', %L)$$, :'cup'), 'not your tournament',
  'only the squad shares a tournament');

:as_anon
select test.throws($$select count(*) from public.share_links$$, 'permission denied', 'links are not listable');
select test.throws($$select public.create_share_link('match', '40000000-0000-0000-0000-000000000009')$$, 'permission denied',
  'links need an account');
select test.eq(public.public_scoreboard(:'live_link')->>'live', 'true', 'a live match shows live');
select test.eq(public.public_scoreboard(:'live_link')->'teams'->0->>0, 'Ben', 'first names only');
select test.eq(public.public_scoreboard(:'live_link')->'score'->'points'->>'a', '7', 'the live score');
select test.eq(public.public_scoreboard(:'done_link')->>'winner', '0', 'a finished match shows its winner');
select test.eq(public.public_scoreboard(:'done_link')->'teams'->1->>0, 'Cat', 'with first names');
select test.eq(public.public_scoreboard(:'cup_link')->>'format', 'double_elimination', 'a tournament shows its format');
select test.eq(jsonb_array_length(public.public_scoreboard(:'cup_link')->'fixtures'), 2, 'and its fixtures');
select test.ok(public.public_scoreboard(:'cup_link')::text !~ :'ben', 'no account IDs in public');
select test.eq(public.public_scoreboard(:'cup_link')->'entrants'->2->>'name', 'Robin', 'guests by first name');
select test.ok(public.public_scoreboard('nope') is null, 'unknown links show nothing');
:as_admin
update public.share_links set expires_at = now() - interval '1 minute' where token = :'done_link';
:as_anon
select test.ok(public.public_scoreboard(:'done_link') is null, 'expired links show nothing');

-- ── Account deletion still works with everything new ────────────────────

:as_cat
select public.delete_account();
:as_admin
select test.eq((select count(*) from public.profiles where id = :'cat'), 0::bigint, 'deleted account is gone');
select test.eq((select display_name from public.players where id = :'cat'), 'Former player', 'their matches stay, unnamed');

-- ── API surface ──────────────────────────────────────────────────────────

:as_anon
select test.throws(format($$select public.admin_reports()$$), 'permission denied', 'anon cannot reach admin');
select test.throws(format($$select private.is_admin(%L)$$, :'ada'), 'permission denied', 'anon cannot reach helpers');
:as_ben
select test.throws($$select * from private.report_target('message', gen_random_uuid())$$, 'permission denied',
  'report internals are not callable');
select test.throws($$select private.remove_target('message', gen_random_uuid())$$, 'permission denied',
  'content removal is admin only');

\echo 'launch: all tests passed'
