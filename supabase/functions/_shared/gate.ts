// PSH.2 — the ONE caller gate for every push function.
//
// One copy, imported by send-notification, chat-notification and session-notification,
// because the fix-round audit caught the alternative in the act: three hand-copied
// gates, one of which (session-notification) simply didn't exist, and a "hardening"
// applied to the other two that silently broke every trigger push. The history matters,
// so it is written down here:
//
//   1. PSH.1 gated send-notification with: literal-key match OR decoded-claims
//      role === 'service_role' (no signature check, leaning on verify_jwt).
//   2. The PSH.2 security audit flagged the unverified-claims branch — its safety
//      depends on the dashboard's verify_jwt flag, which no repo artifact controls —
//      and the fix round removed it, leaving literal-only.
//   3. A live end-to-end probe then returned 403 to the VAULT service key itself.
//      What is PROVEN: the vault key is byte-identical (md5-compared) to the legacy
//      service_role JWT, and the runtime's SUPABASE_SERVICE_ROLE_KEY env does NOT
//      equal it — the literal comparison failed for the one caller class that
//      matters. What is inferred, not proven from here: this project carries both
//      key families (Management API), and once new-format keys exist the runtime env
//      is expected to hold the 'sb_secret_…' form, which is not a JWT and so can
//      never be presented by a caller that verify_jwt admits. Either way the
//      conclusion stands: a literal-only gate rejected the trigger path, so the
//      claims branch was never defense-in-depth slop — it was the only satisfiable
//      path for the vault-key callers.
//
// So the gate is: literal match (covers any future where env and callers share a
// format) OR claims role === 'service_role' on a bearer that the platform has already
// signature-verified. THE CLAIMS BRANCH IS SOUND ONLY WHILE verify_jwt STAYS ON for
// these functions. Never deploy them with --no-verify-jwt; that constraint is recorded
// in AUDIT_ROADMAP alongside the SEC.* notes.

/** True when the request's bearer is the service role — the only legitimate caller
 * class for the push senders (database triggers via the vault key, scheduled
 * dispatchers, daily-workflow-check via its service client). */
export function callerIsServiceRole(req: Request): boolean {
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.replace(/^Bearer\s+/i, "");
  if (bearer.length === 0) return false;

  const envKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (envKey.length > 0 && bearer === envKey) return true;

  if (bearer.split(".").length === 3) {
    try {
      const claims = JSON.parse(
        atob(bearer.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")),
      );
      return claims?.role === "service_role";
    } catch {
      return false;
    }
  }
  return false;
}

/** The standard 403 for a refused caller. */
export function forbiddenResponse(corsHeaders: Record<string, string>): Response {
  return new Response(JSON.stringify({ error: "Forbidden" }), {
    status: 403,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
