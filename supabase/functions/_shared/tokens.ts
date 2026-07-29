// PSH.2 — device-token lookup and reaping against public.user_devices.
//
// One row per DEVICE. users.apns_token was one column per person, so an iPhone+iPad user
// was reachable only on whichever device registered last; every sender now fans out over
// user_devices instead. This module is the ONLY place the lookup lives — the previous
// shape was the same five-line select hand-copied into four functions, which is exactly
// how chat-notification kept reading a message column that did not exist while its
// siblings got fixed.
//
// REAPING. The token is the primary key and Apple is the authority on its validity.
// A 410 Unregistered means the app was removed from that device; a BadDeviceToken on the
// token's own recorded environment means it can never deliver (for a NULL-environment
// legacy token, BadDeviceToken here means BOTH endpoints rejected it — the batch sender
// already retried sandbox before reporting). Dead rows are deleted so the table is
// self-cleaning and a rotated token cannot deliver another person's pushes forever.

import type { SendResult, TokenTarget } from "./apns.ts";

// Minimal structural type for the supabase-js client — enough for .from().select()/.delete().
// deno-lint-ignore no-explicit-any
type SupabaseishClient = any;

/**
 * Fetch the push targets for a set of user ids, one per registered device.
 *
 * Ids are lowercased for the match: a user_devices row can only ever be written through
 * register_device by a signed-in account, and every signable-in users.id is a lowercase
 * uuid string. (The one legacy mixed-case users.id belongs to an orphan account with no
 * auth.users row — it cannot sign in, so it can never hold a device row; lowercasing
 * cannot lose it here.)
 */
export async function lookupTokenTargets(
  supabase: SupabaseishClient,
  userIds: string[],
): Promise<TokenTarget[]> {
  if (!userIds || userIds.length === 0) return [];

  const { data, error } = await supabase
    .from("user_devices")
    .select("token, environment")
    .in("user_id", [...new Set(userIds.map((id) => id.toLowerCase()))]);

  if (error) {
    // Surface loudly and fail the send — a lookup error is not "no devices".
    // PSH.1 exists because failures were presentable as empty states.
    throw new Error(`user_devices lookup failed: ${error.message}`);
  }

  return (data || [])
    .filter((row: { token: string | null }) => Boolean(row.token))
    .map((row: { token: string; environment: string | null }) => ({
      token: row.token,
      environment: row.environment ?? null,
    }));
}

/**
 * Delete user_devices rows whose tokens Apple has pronounced dead.
 * Returns the number of rows reaped. Never throws — reaping is hygiene, and a hygiene
 * failure must not turn a successful send into an error response.
 */
export async function reapDeadTokens(
  supabase: SupabaseishClient,
  results: SendResult[],
): Promise<number> {
  const dead = results
    .filter((r) =>
      !r.success &&
      (r.statusCode === 410 ||
        r.error === "Unregistered" ||
        r.error === "BadDeviceToken")
    )
    .map((r) => r.deviceToken);

  if (dead.length === 0) return 0;

  try {
    const { error } = await supabase
      .from("user_devices")
      .delete()
      .in("token", dead);
    if (error) {
      console.warn(`Token reap failed for ${dead.length} dead token(s): ${error.message}`);
      return 0;
    }
    // Count only — a device token is a per-device credential and is never logged.
    console.log(`Reaped ${dead.length} dead device token(s).`);
    return dead.length;
  } catch (e) {
    console.warn(
      `Token reap threw for ${dead.length} dead token(s): ${
        e instanceof Error ? e.message : String(e)
      }`,
    );
    return 0;
  }
}
