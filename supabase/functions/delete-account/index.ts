// delete-account: removes a PickleBall account completely.
//
// 1. Checks the caller's own session (only you can delete you).
// 2. Revokes Sign in with Apple, as Apple requires, using the
//    authorization code the app gets from a fresh Sign in with Apple.
// 3. Removes every file the account owns from Storage, page by page.
// 4. Deletes the account's data (public.delete_account_as_service).
//
// Deploy:  supabase functions deploy delete-account
// Secrets: supabase secrets set APPLE_TEAM_ID=… APPLE_KEY_ID=… \
//            APPLE_CLIENT_ID=ME.PickleBall APPLE_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are set by
// Supabase automatically.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

const BUCKETS = ["avatars", "media"];
const PAGE = 100;

type Result = { ok: boolean; filesRemoved: number; appleRevoked: boolean | null; error?: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204 });
  if (req.method !== "POST") return json({ ok: false, filesRemoved: 0, appleRevoked: null, error: "POST only" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") ?? "";

  // Who is asking: their own session, never a body field.
  const asUser = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: userData, error: userError } = await asUser.auth.getUser();
  if (userError || !userData.user) {
    return json({ ok: false, filesRemoved: 0, appleRevoked: null, error: "not signed in" }, 401);
  }
  const userID = userData.user.id;
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  let body: { appleAuthorizationCode?: string } = {};
  try { body = await req.json(); } catch { /* empty body is fine */ }

  // Apple first: once the account is gone we can't ask again.
  let appleRevoked: boolean | null = null;
  if (body.appleAuthorizationCode) {
    appleRevoked = await revokeApple(body.appleAuthorizationCode).catch((e) => {
      console.error("apple revoke failed", e);
      return false;
    });
  }

  let filesRemoved = 0;
  try {
    for (const bucket of BUCKETS) filesRemoved += await removeFolder(admin, bucket, userID);
  } catch (e) {
    return json({ ok: false, filesRemoved, appleRevoked, error: `storage: ${e}` }, 500);
  }

  const { error: deleteError } = await admin.rpc("delete_account_as_service", { target: userID });
  if (deleteError) {
    return json({ ok: false, filesRemoved, appleRevoked, error: deleteError.message }, 500);
  }
  return json({ ok: true, filesRemoved, appleRevoked });
});

/** Every file under `<user id>/`, including nested folders, in pages. */
async function removeFolder(admin: SupabaseClient, bucket: string, userID: string): Promise<number> {
  const files: string[] = [];
  const folders = [userID];
  while (folders.length > 0) {
    const folder = folders.pop()!;
    for (let offset = 0; ; offset += PAGE) {
      const { data, error } = await admin.storage.from(bucket).list(folder, { limit: PAGE, offset });
      if (error) throw error;
      for (const entry of data ?? []) {
        const path = `${folder}/${entry.name}`;
        // Folders come back without an id.
        if (entry.id === null || entry.id === undefined) folders.push(path); else files.push(path);
      }
      if (!data || data.length < PAGE) break;
    }
  }
  for (let i = 0; i < files.length; i += PAGE) {
    const { error } = await admin.storage.from(bucket).remove(files.slice(i, i + PAGE));
    if (error) throw error;
  }
  return files.length;
}

/** Exchanges the authorization code for a token, then revokes it. */
async function revokeApple(code: string): Promise<boolean> {
  const teamID = Deno.env.get("APPLE_TEAM_ID");
  const keyID = Deno.env.get("APPLE_KEY_ID");
  const clientID = Deno.env.get("APPLE_CLIENT_ID");
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
  if (!teamID || !keyID || !clientID || !privateKey) {
    console.warn("Apple secrets not set; skipping revocation");
    return false;
  }
  const key = await importPKCS8(privateKey.replace(/\\n/g, "\n"), "ES256");
  const now = Math.floor(Date.now() / 1000);
  const clientSecret = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(teamID)
    .setIssuedAt(now)
    .setExpirationTime(now + 300)
    .setAudience("https://appleid.apple.com")
    .setSubject(clientID)
    .sign(key);

  const tokenResponse = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: clientID, client_secret: clientSecret, code, grant_type: "authorization_code" }),
  });
  if (!tokenResponse.ok) {
    console.error("apple token", tokenResponse.status, await tokenResponse.text());
    return false;
  }
  const tokens = await tokenResponse.json() as { refresh_token?: string; access_token?: string };
  const token = tokens.refresh_token ?? tokens.access_token;
  if (!token) return false;

  const revokeResponse = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientID,
      client_secret: clientSecret,
      token,
      token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
    }),
  });
  return revokeResponse.ok;
}

function json(body: Result, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
