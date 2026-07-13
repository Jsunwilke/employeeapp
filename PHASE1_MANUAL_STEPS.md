# Phase 1 — Manual steps only you can do

> UPDATE 2026-07-12: Owner decided NOT to revoke/rotate the exposed credentials
> — repo is private and single-user, so the leaked keys are treated as
> uncompromised (accepted residual risk; a leaked key stays usable by anyone who
> ever copied it until revoked). Git history WAS purged: all `.p8`/`.p12` and
> `GoogleService-Info.plist` removed from every branch + tag, and the Captura
> secret + rebuild token scrubbed from old `Functions/index.js` blobs, then
> force-pushed. Full pre-rewrite backup: `~/Desktop/employeeapp-backup-before-purge.bundle`.
> The actual key FILES now live only in `~/Desktop/employeeapp-keys-TO-REVOKE/`
> — they are still VALID and may be needed for signing/APNs, so keep them safe
> (the folder name is now a misnomer). Sections 1–2 below are therefore SKIPPED
> by choice; section 5 (purge) is DONE.

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

### DONE (2026-07-12)
- `claude-proxy` Edge Function deployed to project `nofegnmrgnanpznavlqy` (Focal-Point).
- `ANTHROPIC_API_KEY` secret set (currently the EXISTING key — rotate below).
- Tested working: text request returned a valid Claude response; a 5MB image
  payload passed through the function to Anthropic without hitting a size limit.

### STILL TO DO — in this order
1. **Ship a new app build** (TestFlight → App Store). The new build calls the
   proxy and no longer needs the key. The CURRENTLY INSTALLED app still reads
   the key from the `app_config` table, so do NOT lock that down yet.
2. **After the new build is in users' hands**, run the lock-down migration:
   ```bash
   supabase db push        # applies 20260712_lock_down_app_config.sql
   ```
   This drops the permissive RLS policy and nulls the stored key. Running it
   BEFORE the new build is universal will break roster scanning on old app
   versions.
3. **Rotate the Anthropic key** at console.anthropic.com (the old one was
   readable by every employee + is in git history — treat as compromised),
   then update BOTH places that use it until the migration in step 2 has run:
   ```bash
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-<new>   # proxy
   # and update app_config.claude_api_key in the dashboard so the OLD app
   # build keeps working until everyone has updated
   ```
   Once step 2's migration has run and old builds are gone, only the proxy
   secret matters.

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
