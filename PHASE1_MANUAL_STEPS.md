# Phase 1 — Manual steps only you can do

The code changes are done and committed. These remaining steps require your
Apple, Supabase, and Google accounts. Do them before/around the git history
purge. Check each off in AUDIT_ROADMAP.md as you finish.

## 1. Revoke the exposed Apple credentials
The four files have been moved OUT of the repo to `~/Desktop/employeeapp-keys-TO-REVOKE/`.
They were in git history, so treat all four as compromised.

- Apple Developer portal → **Keys**: revoke the three AuthKeys
  (`58S4768CLL`, `FHV9KAR596`, `ZVZ46FYX5T`). These are APNs / App Store Connect
  keys. Create replacements as needed; store them outside the repo.
- Revoke the code-signing identity in `Certificates.p12` (Certificates section),
  regenerate if still needed. Xcode "Automatic" signing will recreate a dev cert.
- After confirming nothing in CI/Xcode Cloud references the old files, delete the
  `~/Desktop/employeeapp-keys-TO-REVOKE/` folder.

## 2. Rotate the secrets that were hardcoded
- **Captura** (`CAPTURA_CLIENT_SECRET`): rotate the client secret with ImageQuix/
  Captura, then set the new value in your Cloud Functions env AND `Config.xcconfig`.
- **Rebuild token** (`REBUILD_TOKEN`): choose a new random token, set it in the
  Cloud Functions env. The code now refuses the endpoint if the env var is unset.
- Redeploy the Cloud Functions (`firebase deploy --only functions` or your flow).

## 3. Deploy the Claude proxy + lock down the key
The app now calls a `claude-proxy` Edge Function instead of reading the key.

```bash
# from repo root, with the Supabase CLI linked to your project
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...   # a NEWLY ROTATED key
supabase functions deploy claude-proxy
supabase db push        # applies 20260712_lock_down_app_config.sql
```

- Rotate the Anthropic key at console.anthropic.com first (the old one was
  readable by every employee — treat as compromised).
- The migration drops the permissive RLS policy and nulls the stored key.
- Verify roster/portrait-card scanning still works in the app after deploy.

## 4. Restrict the Google API key
- Google Cloud console → Credentials → the key `AIzaSy…UJnSE`: add an iOS
  bundle-ID restriction and limit it to only the APIs used (Places, Maps SDK).
  Ideally split a separate restricted key for Places.

## 5. Purge git history (do LAST, after the above)
Once secrets are rotated (so the historical copies are worthless), rewrite history:

```bash
# install if needed: brew install git-filter-repo
git filter-repo --force \
  --path "Iconik Employee/AuthKey_58S4768CLL.p8" \
  --path "AuthKey_FHV9KAR596.p8" \
  --path "AuthKey_ZVZ46FYX5T.p8" \
  --path "Iconik Employee/Certificates.p12" \
  --path "Iconik Employee/GoogleService-Info.plist" \
  --invert-paths
git remote add origin https://github.com/Jsunwilke/employeeapp.git   # filter-repo drops the remote
git push --force --all
git push --force --tags
```

Note: the Captura secret and rebuild token lived inside `Functions/index.js`
(a file you still want), so history-scrubbing them means a targeted
`git filter-repo --replace-text` with a rules file mapping the old secret
strings to `***REMOVED***`. Because you're rotating them anyway, the historical
copies become useless — the replace-text pass is defense-in-depth, optional.

After force-pushing, anyone with a clone must re-clone (history hashes change).
