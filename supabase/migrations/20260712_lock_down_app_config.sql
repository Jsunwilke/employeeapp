-- Security fix: app_config held the org's Anthropic API key behind a
-- USING (true) SELECT policy, so ANY authenticated employee could read
-- and exfiltrate the billable key. Claude calls now go through the
-- claude-proxy Edge Function, which holds the key as a function secret
-- (supabase secrets set ANTHROPIC_API_KEY=...). No client needs to read
-- this table anymore.

-- Remove client read access entirely. RLS stays enabled with no
-- policies, so the API can neither read nor write; the dashboard
-- (service role) is unaffected.
DROP POLICY IF EXISTS "Authenticated users can read app_config" ON app_config;

-- Scrub the key from the table — it must not linger in a row that a
-- future permissive policy could re-expose. (Rotate the key at
-- console.anthropic.com as well: it must be treated as compromised.)
UPDATE app_config SET claude_api_key = NULL WHERE id = 1;
