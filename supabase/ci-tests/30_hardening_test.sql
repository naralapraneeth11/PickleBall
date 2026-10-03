-- Behaviour tests for migration 3 (release hardening). Each block mirrors
-- a reproduction from the release-readiness audit, plus the exact write
-- shapes the apps now use.
--
-- Cast: hal is friends with ida and jo; ida and jo are squadmates (in
-- hal's squad) but not friends. kim is new and has no profile yet.

\o /dev/null
\set ON_ERROR_STOP 1

\set hal '00000000-0000-0000-0000-000000000301'
\set ida '00000000-0000-0000-0000-000000000302'
\set jo  '00000000-0000-0000-0000-000000000303'
\set kim '00000000-0000-0000-0000-000000000304'

\set as_admin   'reset role; set request.jwt.claim.sub = '''';'
\set as_service 'reset role; set request.jwt.claim.sub = ''''; set role service_role;'
\set as_hal 'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000000301''; set role authenticated;'
\set as_ida 'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000000302''; set role authenticated;'
\set as_jo  'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000000303''; set role authenticated;'
\set as_kim 'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000000304''; set role authenticated;'

:as_admin
insert into auth.users (id, email) values
  (:'hal', 'hal@example.com'), (:'ida', 'ida@example.com'), (:'jo', 'jo@example.com'), (:'kim', 'kim@example.com');
insert into public.profiles (id, username, display_name) values
  (:'hal', 'hal', 'Hal'), (:'ida', 'ida', 'Ida'), (:'jo', 'joe', 'Jo');

:as_hal
select public.request_friend(:'ida');
select public.request_friend(:'jo');
:as_ida
select public.respond_friend(:'hal', true);
:as_jo
select public.respond_friend(:'hal', true);
:as_hal
select public.create_squad('Kitchen', array[:'ida', :'jo']::uuid[]) as squad \gset
select id as squad_chat from public.conversations where squad_id = :'squad' \gset

-- ── Profile writes (audit 1) ────────────────────────────────────────────
-- The app inserts a new profile, then updates without touching the id.

:as_kim
insert into public.profiles (id, username, display_name) values (:'kim', 'kim', 'Kim');
select test.eq((select display_name from public.profiles where id = :'kim'), 'Kim', 'a new user creates a profile');
update public.profiles set display_name = 'Kim K', username = 'kimk' where id = :'kim';
select test.eq((select display_name from public.profiles where id = :'kim'), 'Kim K', 'and edits it without the id');
select test.throws(format($$update public.profiles set id = gen_random_uuid() where id = %L$$, :'kim'),
  'permission denied', 'a profile id can''t change');
select test.throws(format($$insert into public.profiles (id, username, display_name) values (%L, 'kim2', 'x')
  on conflict (id) do update set id = excluded.id, display_name = excluded.display_name$$, :'kim'),
  'permission denied', 'the old upsert shape is refused, which is why the app no longer uses it');

-- ── Live matches (audit 1) ──────────────────────────────────────────────

:as_hal
insert into public.live_matches (match_id, host_id, sport, player_ids, lineup, score)
values ('70000000-0000-0000-0000-000000000001', :'hal', 'pickleball', array[:'hal']::uuid[], '{}', '{"call":"0-0-2"}');
update public.live_matches set score = '{"call":"1-0-1"}' where match_id = '70000000-0000-0000-0000-000000000001';
select test.eq((select score->>'call' from public.live_matches where match_id = '70000000-0000-0000-0000-000000000001'),
  '1-0-1', 'a live score publishes and updates');
select test.throws(format($$update public.live_matches set host_id = %L where match_id = '70000000-0000-0000-0000-000000000001'$$, :'ida'),
  'permission denied', 'a live match can''t change hands');
delete from public.live_matches where match_id = '70000000-0000-0000-0000-000000000001';

-- ── H1. Guests can't be created pre-claimed (audit 6) ───────────────────

select test.throws(format($$insert into public.players (id, kind, display_name, created_by, claimed_by)
  values (gen_random_uuid(), 'guest', 'Fake', %L, %L)$$, :'hal', :'ida'),
  'row-level security', 'a guest can''t be created already claimed by someone else');
insert into public.players (id, kind, display_name, created_by)
values ('00000000-0000-0000-0000-0000000003f1', 'guest', 'Pat', :'hal');
select test.ok(exists (select 1 from public.players where id = '00000000-0000-0000-0000-0000000003f1'),
  'ordinary guests still work');

-- ── H2. Blocks inside a shared squad (audit 7) ──────────────────────────

:as_jo
insert into public.blocks (blocker, blocked) values (:'jo', :'ida');
:as_ida
insert into public.messages (conversation_id, sender_id, kind, body) values (:'squad_chat', :'ida', 'text', 'Anyone tonight?');
select test.eq((select count(*) from public.messages where conversation_id = :'squad_chat' and sender_id = :'ida'), 1::bigint,
  'you see your own squad messages');
:as_jo
insert into public.messages (conversation_id, sender_id, kind, body) values (:'squad_chat', :'jo', 'text', 'I''m in');
select test.eq((select count(*) from public.messages where conversation_id = :'squad_chat' and sender_id = :'ida'), 0::bigint,
  'the blocker doesn''t see the blocked person''s squad messages');
:as_ida
select test.eq((select count(*) from public.messages where conversation_id = :'squad_chat' and sender_id = :'jo'), 0::bigint,
  'and the blocked person doesn''t see the blocker''s');
:as_hal
select test.eq((select count(*) from public.messages where conversation_id = :'squad_chat' and sender_id in (:'ida', :'jo')), 2::bigint,
  'everyone else in the squad sees both');

:as_admin
insert into storage.objects (bucket_id, name, owner) values
  ('media', :'ida' || '/chat/' || :'squad_chat' || '/1.jpg', :'ida');
:as_jo
select test.eq((select count(*) from storage.objects where name like :'ida' || '/chat/%'), 0::bigint,
  'chat photos from someone you blocked are hidden');
:as_hal
select test.eq((select count(*) from storage.objects where name like :'ida' || '/chat/%'), 1::bigint,
  'squadmates still see chat photos');

-- ── H3. Malformed matches are refused (audit 8) ─────────────────────────

:as_hal
select test.throws(format($$select public.save_match(test.match('70000000-0000-0000-0000-000000000010', '{"rules":{}}'),
  jsonb_build_array(test.p(%L, 0), test.p(%L, 1)))$$, :'hal', :'ida'), 'invalid rules', 'empty rules are refused');
select test.throws(format($$select public.save_match(test.match('70000000-0000-0000-0000-000000000011'),
  jsonb_build_array(test.p(%L, 0)))$$, :'hal'), 'each side needs', 'a one-sided match is refused');
select test.throws(format($$select public.save_match(test.match('70000000-0000-0000-0000-000000000012', '{"sport":"padel"}'),
  jsonb_build_array(test.p(%L, 0), test.p(%L, 1)))$$, :'hal', :'ida'), 'invalid rules', 'rules must match the sport');
select test.throws(format($$select public.save_match(test.match('70000000-0000-0000-0000-000000000013'),
  jsonb_build_array(test.p(%L, 0), test.p(%L, 1)))$$, :'hal', :'hal'), 'only appear once', 'a player can''t play themselves');
select test.throws(format($$select public.save_match(test.match('70000000-0000-0000-0000-000000000014', '{"started_at":"2099-01-01T00:00:00Z"}'),
  jsonb_build_array(test.p(%L, 0), test.p(%L, 1)))$$, :'hal', :'ida'), 'invalid date', 'future dates are refused');
select test.throws(format($$select public.save_match(test.match('70000000-0000-0000-0000-000000000015', '{"match_score":[40,0]}'),
  jsonb_build_array(test.p(%L, 0), test.p(%L, 1)))$$, :'hal', :'ida'), 'invalid score', 'impossible scores are refused');
select test.throws(format($$select public.save_match(test.match('70000000-0000-0000-0000-000000000016', jsonb_build_object('court', repeat('x', 70000))),
  jsonb_build_array(test.p(%L, 0), test.p(%L, 1)))$$, :'hal', :'ida'), 'too large', 'oversized payloads are refused');
select test.eq(public.save_match(test.match('70000000-0000-0000-0000-000000000017',
    jsonb_build_object('rules', '{"kind":"padel","padel":{"setsToWin":2,"gamesPerSet":6,"tiebreakPoints":7,"deuceRule":"goldenPoint","decidingSet":{"superTiebreak":{"points":10}},"isDoubles":false,"firstServer":1,"firstServerIndex":{"a":0,"b":0}}}'::jsonb,
                       'sport', 'padel')),
  jsonb_build_array(test.p(:'hal', 0), test.p(:'ida', 1))), 'pending', 'a valid padel match is accepted');

-- ── H4. Workouts never reach the shared row (audit 5) ───────────────────

select public.save_match(test.match('70000000-0000-0000-0000-000000000020',
    jsonb_build_object('workout', '{"averageHeartRate":150}'::jsonb, 'squad_id', :'squad')),
  jsonb_build_array(test.p(:'hal', 0), test.p(:'jo', 1)));
:as_ida
select test.ok(exists (select 1 from public.matches where id = '70000000-0000-0000-0000-000000000020'),
  'squadmates see the squad match');
select test.eq((select workout from public.matches where id = '70000000-0000-0000-0000-000000000020'), null::jsonb,
  'but no workout or heart rate on it');
:as_admin
select test.throws($$update public.matches set workout = '{"x":1}' where id = '70000000-0000-0000-0000-000000000020'$$,
  'matches_no_workout', 'nothing can put health data back on a match');

-- ── H6. Avatars: owners can read their folder (deletion lists it) ───────

insert into storage.objects (bucket_id, name, owner) values ('avatars', :'hal' || '/avatar.jpg', :'hal');
:as_hal
select test.eq((select count(*) from storage.objects where bucket_id = 'avatars' and name like :'hal' || '/%'), 1::bigint,
  'you can list your own avatar');
:as_ida
select test.eq((select count(*) from storage.objects where bucket_id = 'avatars' and name like :'hal' || '/%'), 0::bigint,
  'but not someone else''s folder');

-- ── H5. Deletion (audit 10) ─────────────────────────────────────────────

:as_hal
select test.throws(format($$select public.delete_account_as_service(%L)$$, :'ida'),
  'permission denied', 'only the service role can delete another account');
:as_service
select public.delete_account_as_service(:'hal');
:as_admin
select test.ok(not exists (select 1 from auth.users where id = :'hal'), 'the account is gone');
select test.eq((select display_name from public.players where id = :'hal'), 'Former player', 'matches show a former player');
select test.eq((select court from public.matches where id = '70000000-0000-0000-0000-000000000020'), null::jsonb,
  'and keep nothing personal');

-- ── H7. Realtime publication ────────────────────────────────────────────

select test.ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'squad_members'),
  'squad membership changes are published');
select test.ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'replays'),
  'Replays are published');

\echo 'hardening: all tests passed'
