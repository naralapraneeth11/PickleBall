-- Behaviour tests for the Phase 2 schema. Each block acts as a signed-in
-- user (role `authenticated`, auth.uid() from the JWT claim) so row-level
-- security is exercised exactly as the app will hit it.
--
-- Cast: alice, bob, carol, dave are friends of alice; eve is a stranger;
-- frank deletes his account at the end.

\o /dev/null
\set ON_ERROR_STOP 1

\set alice '00000000-0000-0000-0000-00000000000a'
\set bob   '00000000-0000-0000-0000-00000000000b'
\set carol '00000000-0000-0000-0000-00000000000c'
\set dave  '00000000-0000-0000-0000-00000000000d'
\set eve   '00000000-0000-0000-0000-00000000000e'
\set frank '00000000-0000-0000-0000-00000000000f'

\set as_admin 'reset role; set request.jwt.claim.sub = '''';'
\set as_anon  'reset role; set request.jwt.claim.sub = ''''; set role anon;'
\set as_alice 'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-00000000000a''; set role authenticated;'
\set as_bob   'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-00000000000b''; set role authenticated;'
\set as_carol 'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-00000000000c''; set role authenticated;'
\set as_dave  'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-00000000000d''; set role authenticated;'
\set as_eve   'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-00000000000e''; set role authenticated;'
\set as_frank 'reset role; set request.jwt.claim.sub = ''00000000-0000-0000-0000-00000000000f''; set role authenticated;'

-- ── Test helpers ─────────────────────────────────────────────────────────

create schema test;
grant usage on schema test to anon, authenticated;

create function test.ok(cond boolean, label text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FAIL: %', label; end if;
  raise notice 'ok - %', label;
end $$;

create function test.eq(actual anycompatible, expected anycompatible, label text) returns void language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL: % (got %, expected %)', label, actual, expected;
  end if;
  raise notice 'ok - %', label;
end $$;

-- Runs `stmt` as the current role and expects it to fail with an error
-- whose message contains `pattern`.
create function test.throws(stmt text, pattern text, label text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlerrm not ilike '%' || pattern || '%' then
      raise exception 'FAIL: % (threw "%", expected "%")', label, sqlerrm, pattern;
    end if;
    raise notice 'ok - % [%]', label, sqlerrm;
    return;
  end;
  raise exception 'FAIL: % (did not throw)', label;
end $$;

create function test.match(mid uuid, extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object(
    'id', mid, 'sport', 'pickleball', 'rules', jsonb_build_object('sport', 'pickleball'),
    'source', 'entered', 'started_at', now() - interval '1 hour', 'ended_at', now(),
    'winner_team', 0, 'match_score', jsonb_build_array(1, 0), 'points', jsonb_build_array(11, 7),
    'units', '[]'::jsonb
  ) || extra
$$;

create function test.p(pid uuid, team int, slot int default 0, kind text default 'user', name text default null)
returns jsonb language sql as $$
  select jsonb_build_object('player_id', pid, 'team', team, 'slot', slot, 'kind', kind, 'display_name', name)
$$;

create function test.dm(a uuid, b uuid) returns uuid language sql as $$
  select id from public.conversations where user_a = least(a, b) and user_b = greatest(a, b)
$$;

create function test.events(conversation uuid, event_type text) returns bigint language sql as $$
  select count(*) from public.messages
  where conversation_id = conversation and kind = 'event' and payload->>'type' = event_type
$$;

grant execute on all functions in schema test to anon, authenticated;

-- ── Accounts ─────────────────────────────────────────────────────────────

:as_admin
insert into auth.users (id, email) values
  (:'alice', 'alice@example.com'), (:'bob', 'bob@example.com'), (:'carol', 'carol@example.com'),
  (:'dave', 'dave@example.com'), (:'eve', 'eve@example.com'), (:'frank', 'frank@example.com');

:as_alice
insert into public.profiles (id, username, display_name, sports)
values (:'alice', 'alice', 'Alice', '{pickleball,padel}');
select test.throws(format($$insert into public.profiles (id, username, display_name) values (%L, 'bobby', 'Bob')$$, :'bob'),
  'row-level security', 'cannot create someone else''s profile');
select test.eq((select kind from public.players where id = :'alice'), 'user', 'profile creates a user player row');

:as_bob
select test.throws(format($$insert into public.profiles (id, username, display_name) values (%L, 'BOB', 'Bob')$$, :'bob'),
  'check constraint', 'usernames are lowercase');
select test.throws(format($$insert into public.profiles (id, username, display_name) values (%L, 'bo', 'Bob')$$, :'bob'),
  'check constraint', 'usernames are at least 3 characters');
select test.throws(format($$insert into public.profiles (id, username, display_name) values (%L, 'bob_', 'Bob')$$, :'bob'),
  'check constraint', 'usernames cannot end in punctuation');
select test.throws(format($$insert into public.profiles (id, username, display_name) values (%L, 'alice', 'Bob')$$, :'bob'),
  'duplicate key', 'usernames are unique');
select test.throws(format($$insert into public.profiles (id, username, display_name, sports) values (%L, 'bob', 'Bob', '{tennis}')$$, :'bob'),
  'check constraint', 'sports are pickleball or padel');
insert into public.profiles (id, username, display_name) values (:'bob', 'bob', 'Bob');

:as_carol
insert into public.profiles (id, username, display_name) values (:'carol', 'carol', 'Carol');
:as_dave
insert into public.profiles (id, username, display_name) values (:'dave', 'dave.d', 'Dave');
:as_eve
insert into public.profiles (id, username, display_name) values (:'eve', 'eve', 'Eve');
:as_frank
insert into public.profiles (id, username, display_name) values (:'frank', 'frank', 'Frank');

:as_eve
select test.eq((select count(*) from public.profiles where id = :'alice'), 0::bigint, 'strangers cannot read profiles');
select test.eq((select count(*) from public.profiles), 1::bigint, 'profiles are not listable');
select test.eq((select count(*) from public.search_users('ali')), 1::bigint, 'username prefix search finds alice');
select test.eq((select display_name from public.search_users('alice')), 'Alice', 'search returns a minimal card');
select test.eq((select count(*) from public.search_users('a')), 0::bigint, 'one-letter searches return nothing');
select test.eq((select count(*) from public.search_users('%')), 0::bigint, 'wildcards are not searches');

:as_anon
select test.throws('select * from public.profiles', 'permission denied', 'anon cannot read profiles');
select test.throws($$select public.search_users('alice')$$, 'permission denied', 'anon cannot call RPCs');

-- ── Friends ──────────────────────────────────────────────────────────────

:as_alice
select test.eq(public.request_friend(:'bob'), 'pending', 'friend request sent');
select test.eq(public.request_friend(:'bob'), 'pending', 'repeat request stays pending');
select test.throws(format('select public.request_friend(%L)', :'alice'), 'yourself', 'cannot friend yourself');
select test.throws(format($$insert into public.friendships (user_a, user_b, status, requested_by) values (%L, %L, 'accepted', %L)$$,
  :'alice', :'carol', :'alice'), 'row-level security', 'friendships cannot be written directly');

:as_bob
select test.eq((select display_name from public.profiles where id = :'alice'), 'Alice', 'requester card visible while pending');
select test.eq((select status from public.friendships where requested_by = :'alice'), 'pending', 'request visible to recipient');
select public.respond_friend(:'alice', true);
select test.ok(private.are_friends(:'alice', :'bob'), 'accepting makes friends');
select test.ok(test.dm(:'alice', :'bob') is not null, 'friends get a direct chat');

:as_eve
select test.eq((select count(*) from public.conversations), 0::bigint, 'strangers see no chats');

:as_carol
select public.create_invite('friend') as carol_invite \gset
:as_alice
select test.eq(public.redeem_invite(:'carol_invite')->>'kind', 'friend', 'friend link redeemed');
select test.ok(private.are_friends(:'alice', :'carol'), 'friend link makes friends');
select test.eq((select username::text from public.profiles where id = :'carol'), 'carol', 'friends read each other''s profiles');

:as_alice
select public.request_friend(:'dave');
:as_dave
select public.respond_friend(:'alice', false);
select test.eq((select count(*) from public.friendships), 0::bigint, 'declined request disappears');

:as_eve
select test.eq(public.request_friend(:'alice'), 'pending', 'stranger sends a request');

:as_frank
select public.request_friend(:'alice');
:as_alice
select test.eq(public.request_friend(:'frank'), 'accepted', 'requesting back accepts');

-- ── Squads and chat ──────────────────────────────────────────────────────

:as_alice
select public.create_squad('Tuesday Night', array[:'bob', :'carol', :'eve']::uuid[]) as squad \gset
select test.eq((select count(*) from public.squad_members where squad_id = :'squad'), 3::bigint,
  'squad has creator and friends, not strangers');
select id as squad_chat from public.conversations where squad_id = :'squad' \gset

:as_bob
select test.eq((select name from public.squads where id = :'squad'), 'Tuesday Night', 'members see the squad');
select test.eq((select display_name from public.profiles where id = :'carol'), 'Carol', 'squadmates see each other');
select test.throws(format('select public.add_squad_member(%L, %L)', :'squad', :'dave'), 'only friends', 'only friends can be added');
insert into public.messages (conversation_id, sender_id, kind, body) values (:'squad_chat', :'bob', 'text', 'Courts at 7?');
select test.throws(format($$insert into public.messages (conversation_id, sender_id, kind, payload) values (%L, %L, 'event', '{}')$$,
  :'squad_chat', :'bob'), 'row-level security', 'clients cannot forge event messages');
select test.throws(format($$insert into public.messages (conversation_id, sender_id, kind, body) values (%L, %L, 'text', 'hi')$$,
  :'squad_chat', :'alice'), 'row-level security', 'cannot send as someone else');

:as_carol
select test.eq((select body from public.messages where conversation_id = :'squad_chat' and kind = 'text'), 'Courts at 7?',
  'squad chat delivers');
select test.ok((select last_message_at from public.conversations where id = :'squad_chat') is not null, 'chat list sorts by last message');

:as_eve
select test.eq((select count(*) from public.squads), 0::bigint, 'non-members cannot see squads');
select test.throws(format($$insert into public.messages (conversation_id, sender_id, kind, body) values (%L, %L, 'text', 'hi')$$,
  :'squad_chat', :'eve'), 'row-level security', 'non-members cannot post');
select test.throws(format('select public.create_invite(''squad'', %L)', :'squad'), 'not a squad member', 'only members make squad links');

-- ── Matches and confirmation ─────────────────────────────────────────────

:as_alice
select test.eq(public.save_match(test.match('10000000-0000-0000-0000-000000000001'),
  jsonb_build_array(test.p(:'alice', 0), test.p(:'bob', 1))), 'pending', 'result against a friend waits for them');
select test.eq(public.save_match(test.match('10000000-0000-0000-0000-000000000001'),
  jsonb_build_array(test.p(:'alice', 0), test.p(:'bob', 1))), 'pending', 'saving twice is idempotent');
select test.eq((select count(*) from public.match_participants where match_id = '10000000-0000-0000-0000-000000000001'),
  2::bigint, 'retries do not duplicate players');

:as_eve
select test.eq((select count(*) from public.matches), 0::bigint, 'strangers cannot see matches');
:as_carol
select test.eq((select status from public.matches where id = '10000000-0000-0000-0000-000000000001'), 'pending',
  'friends of a player see the match');

:as_bob
select test.throws($$select public.save_match(test.match('10000000-0000-0000-0000-000000000001'), '[]')$$,
  'not your match', 'only the scorer can edit a result');
select test.eq(public.confirm_match('10000000-0000-0000-0000-000000000001', true,
  jsonb_build_array(jsonb_build_object('type', 'belt', 'holder', :'alice'))), 'confirmed', 'opponent confirms');
select test.eq(public.confirm_match('10000000-0000-0000-0000-000000000001', true), 'confirmed', 'confirming twice is harmless');
select test.eq(test.events(test.dm(:'alice', :'bob'), 'result'), 1::bigint, 'confirmed result posts to the direct chat');
select test.eq(test.events(test.dm(:'alice', :'bob'), 'belt'), 1::bigint, 'belt change posts after the result');
update public.matches set winner_team = 1 where id = '10000000-0000-0000-0000-000000000001';
select test.eq((select winner_team from public.matches where id = '10000000-0000-0000-0000-000000000001'), 0::smallint,
  'confirmed results cannot be edited directly');

:as_alice
select test.eq(public.save_match(test.match('10000000-0000-0000-0000-000000000001'),
  jsonb_build_array(test.p(:'alice', 0), test.p(:'bob', 1))), 'confirmed', 'confirmed results are final');

-- Guests: confirmed at once, claimable by link.
select test.eq(public.save_match(test.match('10000000-0000-0000-0000-000000000002'),
  jsonb_build_array(test.p(:'alice', 0), test.p('00000000-0000-0000-0000-0000000000f1', 1, 0, 'guest', 'Sam'))),
  'confirmed', 'result against a guest is confirmed at once');
select test.eq((select display_name from public.players where id = '00000000-0000-0000-0000-0000000000f1'), 'Sam',
  'guest created on first use');
select public.create_invite('guest_claim', '00000000-0000-0000-0000-0000000000f1') as claim \gset

:as_bob
select test.throws($$select public.create_invite('guest_claim', '00000000-0000-0000-0000-0000000000f1')$$,
  'not your guest', 'only the guest''s creator makes a claim link');

:as_dave
select test.eq(public.redeem_invite(:'claim')->>'kind', 'guest_claim', 'guest claimed');
select test.eq((select count(*) from public.matches where id = '10000000-0000-0000-0000-000000000002'), 1::bigint,
  'claimer inherits the guest''s matches');
select test.ok(private.are_friends(:'alice', :'dave'), 'claiming a guest friends the host');

:as_eve
select test.throws(format('select public.redeem_invite(%L)', :'claim'), 'invite used', 'claim links are single use');

:as_alice
select test.throws(format($$select public.save_match(test.match('10000000-0000-0000-0000-000000000003'), jsonb_build_array(test.p(%L, 0), test.p(%L, 1)))$$,
  :'alice', :'eve'), 'players must be', 'strangers cannot be put in matches');
select test.throws(format($$select public.save_match(test.match('10000000-0000-0000-0000-000000000003'), jsonb_build_array(test.p(%L, 0), test.p(%L, 1, 0, 'guest', 'Eve')))$$,
  :'alice', :'eve'), 'players must be', 'a user cannot be smuggled in as a guest');
select test.throws(format($$select public.save_match(test.match('10000000-0000-0000-0000-000000000003'), jsonb_build_array(test.p(%L, 0), test.p(%L, 1)))$$,
  :'bob', :'carol'), 'must be in the match', 'you can only record your own matches');

-- Dispute, fix, confirm.
:as_bob
select test.eq(public.save_match(test.match('10000000-0000-0000-0000-000000000004', '{"winner_team":0}'),
  jsonb_build_array(test.p(:'bob', 0), test.p(:'alice', 1))), 'pending', 'bob records a win');
:as_alice
select test.eq(public.confirm_match('10000000-0000-0000-0000-000000000004', false), 'disputed', 'alice disputes');
:as_bob
select test.eq(public.save_match(test.match('10000000-0000-0000-0000-000000000004', '{"winner_team":1,"match_score":[0,1]}'),
  jsonb_build_array(test.p(:'bob', 0), test.p(:'alice', 1))), 'pending', 'fixing a disputed result asks again');
:as_alice
select test.eq(public.confirm_match('10000000-0000-0000-0000-000000000004', true), 'confirmed', 'fixed result confirmed');

:as_bob
select public.save_match(test.match('10000000-0000-0000-0000-000000000005'), jsonb_build_array(test.p(:'bob', 0), test.p(:'alice', 1)));
select public.withdraw_match('10000000-0000-0000-0000-000000000005');
select test.throws($$select public.withdraw_match('10000000-0000-0000-0000-000000000004')$$, 'cannot withdraw',
  'confirmed results cannot be withdrawn');
:as_alice
select test.eq((select count(*) from public.matches where id = '10000000-0000-0000-0000-000000000005'), 0::bigint,
  'withdrawn result is gone');

-- Doubles: one confirmation per side.
select test.eq(public.save_match(test.match('10000000-0000-0000-0000-000000000006'),
  jsonb_build_array(test.p(:'alice', 0, 0), test.p(:'carol', 0, 1), test.p(:'bob', 1, 0), test.p(:'dave', 1, 1))),
  'pending', 'doubles result waits for the other pair');
:as_carol
select test.eq(public.confirm_match('10000000-0000-0000-0000-000000000006', true), 'pending', 'partner confirming does not close it');
:as_dave
select test.eq(public.confirm_match('10000000-0000-0000-0000-000000000006', true), 'confirmed', 'either opponent confirms for the pair');
:as_eve
select test.throws($$select public.confirm_match('10000000-0000-0000-0000-000000000006', true)$$, 'not in this match',
  'outsiders cannot confirm');

-- ── Call outs ────────────────────────────────────────────────────────────

:as_alice
select public.create_callout(jsonb_build_object('challengers', jsonb_build_array(:'alice'), 'challenged', jsonb_build_array(:'bob'),
  'sport', 'pickleball', 'rules', '{}'::jsonb, 'proposed_at', '2026-10-01T18:00:00Z')) as callout \gset
select test.eq(test.events(test.dm(:'alice', :'bob'), 'callout'), 1::bigint, 'call out posts to the chat');
select test.throws(format($$select public.respond_callout(%L, 'accept')$$, :'callout'), 'not your call out to answer',
  'challenger cannot accept their own call out');
select test.throws(format($$select public.create_callout(jsonb_build_object('challengers', jsonb_build_array(%L), 'challenged', jsonb_build_array(%L), 'sport', 'padel', 'rules', '{}'::jsonb))$$,
  :'alice', :'eve'), 'only call out friends', 'only friends can be called out');
select test.throws(format($$select public.create_callout(jsonb_build_object('challengers', jsonb_build_array(%L), 'challenged', jsonb_build_array(%L, %L), 'sport', 'padel', 'rules', '{}'::jsonb))$$,
  :'alice', :'bob', :'dave'), 'check constraint', 'sides must be the same size');

:as_carol
select test.eq((select count(*) from public.callouts), 0::bigint, 'call outs are private to the players');
select test.throws(format($$select public.respond_callout(%L, 'accept')$$, :'callout'), 'not your call out', 'outsiders cannot answer');

:as_bob
select test.eq(public.respond_callout(:'callout', 'counter', '{"proposed_at":"2026-10-02T19:00:00Z","court":{"name":"Rec Center"}}'),
  'countered', 'bob counters');
select test.throws(format($$select public.respond_callout(%L, 'accept')$$, :'callout'), 'waiting on the other side',
  'cannot accept your own counter');
:as_alice
select test.eq(public.respond_callout(:'callout', 'accept'), 'accepted', 'alice accepts the counter');
select test.eq((select proposed_at from public.callouts where id = :'callout'), '2026-10-02T19:00:00Z'::timestamptz,
  'accepted counter sets the time');
select test.eq((select court->>'name' from public.callouts where id = :'callout'), 'Rec Center', 'accepted counter sets the court');

:as_bob
select public.save_match(test.match('10000000-0000-0000-0000-000000000007', jsonb_build_object('callout_id', :'callout')),
  jsonb_build_array(test.p(:'bob', 0), test.p(:'alice', 1)));
:as_alice
select public.confirm_match('10000000-0000-0000-0000-000000000007', true);
select test.eq((select status from public.callouts where id = :'callout'), 'completed', 'confirmed result closes the call out');
select test.eq((select match_id from public.callouts where id = :'callout'), '10000000-0000-0000-0000-000000000007'::uuid,
  'call out links to its match');

-- ── Squad tournaments ────────────────────────────────────────────────────

:as_alice
select public.create_tournament(
  jsonb_build_object('squad_id', :'squad', 'name', 'Tuesday Round Robin', 'sport', 'pickleball', 'format', 'round_robin', 'rules', '{}'::jsonb),
  jsonb_build_array(jsonb_build_object('player_id', :'alice'), jsonb_build_object('player_id', :'bob'),
                    jsonb_build_object('player_id', :'carol'),
                    jsonb_build_object('player_id', '00000000-0000-0000-0000-0000000000f2', 'kind', 'guest', 'display_name', 'Riley')),
  jsonb_build_array(
    jsonb_build_object('id', '20000000-0000-0000-0000-000000000001', 'round', 1, 'team_a', jsonb_build_array(:'alice'), 'team_b', jsonb_build_array(:'bob'),
                       'scheduled_at', '2026-10-06T19:00:00Z', 'court', '{"name":"Court 3"}'::jsonb),
    jsonb_build_object('id', '20000000-0000-0000-0000-000000000002', 'round', 1, 'court_number', 2,
                       'team_a', jsonb_build_array(:'bob'), 'team_b', jsonb_build_array('00000000-0000-0000-0000-0000000000f2')))
) as tournament \gset
select test.eq(test.events(:'squad_chat', 'tournament_created'), 1::bigint, 'new tournament posts to the squad chat');
select test.throws(format($$select public.create_tournament(jsonb_build_object('squad_id', %L, 'name', 'x', 'sport', 'padel', 'format', 'americano', 'rules', '{}'::jsonb), jsonb_build_array(jsonb_build_object('player_id', %L)), '[]')$$,
  :'squad', :'eve'), 'squad members or guests', 'entrants come from the squad');

:as_bob
select test.eq((select count(*) from public.tournament_entrants where tournament_id = :'tournament'), 4::bigint, 'members see entrants');
select test.eq((select display_name from public.players where id = '00000000-0000-0000-0000-0000000000f2'), 'Riley',
  'members see guest entrants');
select test.eq((select court->>'name' from public.tournament_fixtures where id = '20000000-0000-0000-0000-000000000001'), 'Court 3',
  'fixtures carry their court');

:as_eve
select test.eq((select count(*) from public.tournaments), 0::bigint, 'non-members cannot see tournaments');
select test.throws(format($$select public.create_tournament(jsonb_build_object('squad_id', %L, 'name', 'x', 'sport', 'padel', 'format', 'americano', 'rules', '{}'::jsonb), '[]', '[]')$$,
  :'squad'), 'not a squad member', 'only members create tournaments');

-- Anyone in the squad scores any match.
:as_carol
select test.eq(public.save_match(test.match('10000000-0000-0000-0000-000000000008',
  jsonb_build_object('tournament_id', :'tournament', 'fixture_id', '20000000-0000-0000-0000-000000000001')),
  jsonb_build_array(test.p(:'alice', 0), test.p(:'bob', 1))), 'pending', 'a squadmate scores someone else''s match');
:as_alice
select test.eq(public.confirm_match('10000000-0000-0000-0000-000000000008', true), 'pending', 'one side confirmed');
:as_bob
select test.eq(public.confirm_match('10000000-0000-0000-0000-000000000008', true), 'confirmed', 'both sides confirmed');
select test.eq(test.events(:'squad_chat', 'result'), 1::bigint, 'tournament result posts to the squad chat');
select test.eq((select match_id from public.tournament_fixtures where id = '20000000-0000-0000-0000-000000000001'),
  '10000000-0000-0000-0000-000000000008'::uuid, 'fixture links to its match');
select test.eq(public.save_match(test.match('10000000-0000-0000-0000-000000000009',
  jsonb_build_object('tournament_id', :'tournament', 'fixture_id', '20000000-0000-0000-0000-000000000002')),
  jsonb_build_array(test.p(:'bob', 0), test.p('00000000-0000-0000-0000-0000000000f2', 1))), 'confirmed',
  'another member''s guest can be played');
update public.tournament_fixtures set scheduled_at = '2026-10-07T19:00:00Z' where id = '20000000-0000-0000-0000-000000000002';
select test.eq((select scheduled_at from public.tournament_fixtures where id = '20000000-0000-0000-0000-000000000002'),
  '2026-10-07T19:00:00Z'::timestamptz, 'members reschedule fixtures');
select public.complete_tournament(:'tournament', array[:'alice']::uuid[]);
select public.complete_tournament(:'tournament', array[:'alice']::uuid[]);
select test.eq((select count(*) from public.trophies where owner_id = :'alice'), 1::bigint, 'champion gets one trophy');
select test.eq(test.events(:'squad_chat', 'champion'), 1::bigint, 'champion posts to the squad chat');
:as_eve
select test.eq((select count(*) from public.trophies), 0::bigint, 'trophy cases are friends-only');

-- ── Replays ──────────────────────────────────────────────────────────────

:as_alice
insert into public.replays (id, match_id, author_id, story)
values ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', :'alice', '{"beats":[]}');
select public.share_replay('30000000-0000-0000-0000-000000000001', test.dm(:'alice', :'bob'));
select test.eq(test.events(test.dm(:'alice', :'bob'), 'replay'), 1::bigint, 'Replay sent to a friend');
:as_eve
select test.throws(format($$insert into public.replays (match_id, author_id, story) values ('10000000-0000-0000-0000-000000000001', %L, '{}')$$,
  :'eve'), 'row-level security', 'only players make Replays');
select test.throws(format($$select public.share_replay('30000000-0000-0000-0000-000000000001', %L)$$, :'squad_chat'),
  'not your replay', 'only the author shares a Replay');
select test.eq((select count(*) from public.replays), 0::bigint, 'strangers cannot see Replays');

:as_admin
insert into public.replays (id, match_id, author_id, story, created_at, expires_at)
values ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', :'alice', '{}',
        now() - interval '2 days', now() - interval '1 day');
:as_bob
select test.eq((select count(*) from public.replays), 1::bigint, 'friends see live Replays, not expired ones');
:as_alice
select test.eq((select count(*) from public.replays), 2::bigint, 'authors keep their expired Replays');
select public.save_replay('30000000-0000-0000-0000-000000000002', 'Comeback from 2-9');
:as_bob
select test.eq((select count(*) from public.replays), 2::bigint, 'saved Replays outlive 24 hours');
select test.eq((select count(*) from public.trophies where kind = 'replay'), 1::bigint, 'saved Replay goes in the trophy case');

-- ── Feed ─────────────────────────────────────────────────────────────────

:as_alice
insert into public.serves (id, author_id, kind, body)
values ('40000000-0000-0000-0000-000000000001', :'alice', 'text', 'Who is up for Sunday?');
select test.throws(format($$insert into public.serves (author_id, kind, body, rally_count) values (%L, 'text', 'x', 50)$$, :'alice'),
  'row-level security', 'rally counts cannot be forged');
select test.eq((select count(*) from public.feed_serves), 0::bigint, 'your own Serves are not in your Feed');

:as_bob
select test.eq((select count(*) from public.feed_serves), 1::bigint, 'friends see the Serve');
update public.serves set rally_count = 100;
select test.eq((select rally_count from public.serves where id = '40000000-0000-0000-0000-000000000001'), 0,
  'Serves cannot be edited by others');
insert into public.returns (id, serve_id, author_id, kind, body)
values ('50000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', :'bob', 'comment', 'In!');
insert into public.returns (serve_id, author_id, kind) values ('40000000-0000-0000-0000-000000000001', :'bob', 'chant');
select test.eq((select rally_count from public.serves where id = '40000000-0000-0000-0000-000000000001'), 2,
  'each Return adds to the rally');

:as_carol
select test.eq((select count(*) from public.returns), 2::bigint, 'friends see Returns');
:as_dave
select test.eq((select count(*) from public.feed_serves), 1::bigint, 'every friend sees the Serve');

:as_eve
select test.eq((select count(*) from public.serves), 0::bigint, 'Serves are never public');
select test.throws(format($$insert into public.returns (serve_id, author_id, kind) values ('40000000-0000-0000-0000-000000000001', %L, 'chant')$$,
  :'eve'), 'row-level security', 'strangers cannot Return');

:as_bob
delete from public.returns where id = '50000000-0000-0000-0000-000000000001';
select test.eq((select rally_count from public.serves where id = '40000000-0000-0000-0000-000000000001'), 1,
  'deleting a Return shortens the rally');

-- Dead ball: 24 hours without a Return and the Serve leaves the Feed.
:as_admin
insert into public.serves (id, author_id, kind, body, created_at) values
  ('40000000-0000-0000-0000-000000000002', :'alice', 'text', 'dead', now() - interval '30 hours'),
  ('40000000-0000-0000-0000-000000000003', :'alice', 'text', 'kept alive', now() - interval '30 hours');
insert into public.returns (serve_id, author_id, kind, created_at)
values ('40000000-0000-0000-0000-000000000003', :'carol', 'comment', now() - interval '2 hours');
:as_bob
select test.eq((select count(*) from public.feed_serves where id = '40000000-0000-0000-0000-000000000002'), 0::bigint,
  'dead ball leaves the Feed');
select test.eq((select count(*) from public.feed_serves where id = '40000000-0000-0000-0000-000000000003'), 1::bigint,
  'a recent Return keeps the ball in play');
:as_alice
select test.eq((select count(*) from public.serves where author_id = :'alice'), 3::bigint, 'dead balls stay in the archive');

-- ── Reports and blocks ───────────────────────────────────────────────────

:as_bob
insert into public.reports (reporter, target_type, target_id, reason)
values (:'bob', 'serve', '40000000-0000-0000-0000-000000000001', 'spam');
:as_alice
select test.eq((select count(*) from public.reports), 0::bigint, 'reports are private to the reporter');

:as_alice
select public.block_user(:'eve');
:as_eve
select test.eq((select count(*) from public.search_users('alice')), 0::bigint, 'blocked users do not appear in search');
select test.throws(format('select public.request_friend(%L)', :'alice'), 'unavailable', 'blocked users cannot send requests');
select test.eq((select count(*) from public.friendships), 0::bigint, 'blocking removes the pending request');

:as_dave
select public.block_user(:'alice');
select test.ok(not private.are_friends(:'alice', :'dave'), 'blocking ends the friendship');
select test.eq((select count(*) from public.feed_serves), 0::bigint, 'blocked friends leave the Feed');
select test.eq((select count(*) from public.conversations where id = test.dm(:'alice', :'dave')), 0::bigint,
  'blocking hides the direct chat');

-- ── Storage ──────────────────────────────────────────────────────────────

:as_alice
insert into storage.objects (bucket_id, name, owner) values ('media', :'alice' || '/serves/1.jpg', :'alice');
select test.throws(format($$insert into storage.objects (bucket_id, name) values ('media', %L)$$, :'bob' || '/x.jpg'),
  'row-level security', 'cannot upload into someone else''s folder');
:as_bob
select test.eq((select count(*) from storage.objects where bucket_id = 'media'), 1::bigint, 'friends can read media');
:as_eve
select test.eq((select count(*) from storage.objects where bucket_id = 'media'), 0::bigint, 'strangers cannot read media');

-- ── Account deletion ─────────────────────────────────────────────────────

:as_frank
select public.save_match(test.match('10000000-0000-0000-0000-00000000000a'), jsonb_build_array(test.p(:'frank', 0), test.p(:'alice', 1)));
:as_alice
select public.confirm_match('10000000-0000-0000-0000-00000000000a', true);
:as_frank
select public.delete_account();
:as_admin
select test.eq((select count(*) from public.profiles where id = :'frank'), 0::bigint, 'deleting an account removes the profile');
select test.eq((select count(*) from auth.users where id = :'frank'), 0::bigint, 'deleting an account removes the login');
:as_alice
select test.eq((select count(*) from public.matches where id = '10000000-0000-0000-0000-00000000000a'), 1::bigint,
  'opponents keep the match');
select test.eq((select display_name from public.players where id = :'frank'), 'Former player', 'deleted players are anonymised');

-- ── Realtime ─────────────────────────────────────────────────────────────

:as_admin
select test.eq((select count(*) from pg_publication_tables where pubname = 'supabase_realtime'
                and tablename in ('messages', 'matches', 'serves', 'callouts')), 4::bigint, 'live tables are published');

-- ── API surface ──────────────────────────────────────────────────────────

:as_eve
select test.throws($$select private.finalize_match('10000000-0000-0000-0000-000000000004', auth.uid(), '[]')$$,
  'permission denied', 'internal steps are not callable');
select test.throws(format($$select private.ensure_direct_conversation(%L, %L)$$, :'alice', :'bob'),
  'permission denied', 'chats cannot be opened between other people');
:as_admin
select test.eq((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname in ('finalize_match', 'are_friends', 'ensure_direct_conversation')),
  0::bigint, 'helpers are not in the exposed schema');

\echo 'social core: all tests passed'
