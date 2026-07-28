# PSH.1 — Push notifications that actually reach a phone

Arc PSH, registered in FocalPointProduction/docs/PHASES.md on 2026-07-27.
Status: research complete, build gated on one live-database read.

This plan is written for a non-engineer to read. No backticks anywhere, per the
plan-readability rule.

---

## 1. What is actually true today

The audit roadmap entry written at AMB.8's close says both ends of the notification
system are built and the middle is missing. That is wrong about the one path that
matters, and building from it would have produced a queue nobody needed.

**One path is complete, deployed and live: sessions.** A trigger on the sessions table
in the shared database calls an edge function named session-notification. That function
is deployed — the deployed copy was downloaded and compared byte for byte against the
copy in this repository, and they are identical. It reads the same column on the users
table that the iOS app writes its device token into. All five Apple push credentials
have been set on the project since January.

So the trigger exists, the transport exists, the sender exists, and the column matches.
Nothing in that chain is missing.

**It delivers nothing because of an environment mismatch.** Apple runs two separate
push services, a sandbox one and a production one, and a device token minted for one is
rejected by the other. The server is configured to use the production service. The app
is built for the sandbox one: its entitlements file says development, and both the Debug
and the Release build configurations are pinned to Apple Development signing. The
operator installs the app straight from Xcode, which produces a development build.

So every push aimed at his phone is rejected by Apple as a bad device token. Nothing
records the rejection. There is no handler in the app for push-registration failure, and
both places that write the token swallow their errors into a print statement. The
failure is invisible from every direction, which is why it survived this long.

**Why the obvious fix is the wrong one.** Turning the production flag off would make the
operator's phone work today and would silently break anybody running a build installed
from TestFlight or the App Store. There is one token column per person and one global
environment switch, and that arrangement cannot serve both kinds of build at the same
time. Whichever device registered most recently owns the row. The correct design records
which environment minted each token and chooses the endpoint per token, which is what
this plan does.

## 2. Everything else, and what is dead

Verified against the live list of deployed functions:

- Three functions were not deployed at all: send-notification, chat-notification and
  clock-reminder. Chat pushes, clock reminders and daily report reminders therefore
  could not happen, regardless of anything else. RESOLVED IN PART on 2026-07-27:
  send-notification is now deployed and verified delivering to a real device. The other
  two had their code corrected but are deliberately left undeployed, because deploying
  them would start firing chat pushes and clock reminders for everybody, which is a
  behaviour decision rather than a bug fix.
- Two completely different functions share the name send-notification, one in each
  repository. This repository's version sends directly to Apple and reads the Apple
  token column. The web repository's version drains a queue table and sends through
  Google's Firebase service, reading a different column. Whichever repository deploys
  last takes ownership of the name. This has to be settled before anyone deploys.
- The Firebase path is dead on arrival even if revived: it targets the legacy Firebase
  endpoint that Google switched off in June 2024.
- Flagging a user is broken three separate ways at once: the function it calls is not
  deployed, the field name it sends does not match the field name the function reads,
  and the type string it sends is not one the app's own handler recognises. The error
  handler reports "flagged successfully" every time regardless.
- The queue table is written to every hour by a deployed scheduled job and drained by
  nobody. No migration in either repository even creates that table.
- Time off notifies nothing that iOS can see. The web app writes a row that only the web
  app's notification bell reads; the iOS app has no reference to that table anywhere.
  The iOS approve and deny path writes nothing at all. This is the exact case the
  operator asked about, and the answer is that his denial produced nothing, anywhere.
- The old push migration in this repository still contains an unsubstituted placeholder
  where the project address should be, in all three of its scheduled jobs, so it cannot
  ever have run as written.
- One stray line writes the raw Apple token into the Firebase token column on every
  single launch.
- A brand new user's token is never saved on their first launch. Registration happens
  before sign-in, the save is skipped because nobody is signed in yet, and nothing ever
  retries.

## 3. The architecture decision

Resolved from the evidence rather than offered as a choice, because the evidence is
one-sided.

**The trigger for a notification belongs in the database.** The single path built that
way is the single path that works end to end. The ten notification types that are wired
up in both the app and a sender, with nothing in between them, are what the alternative
produced — every client is expected to remember to fire a notification, and over time
none of them do. Moving the trigger into the database means neither the iOS app nor the
web app can forget, and it is the same conclusion the chat rebuild notes reached about
moving truth into the database rather than trusting two clients to agree.

**The queue and Firebase machinery is deleted, not revived.** It is undeployed, it is
created by no migration, it is built on an interface Google switched off over a year
ago, and no client correctly populates the column it reads. Deleting it changes nothing
anybody can observe. Reviving it would mean rebuilding it against Firebase's current
interface and finding a reason to prefer that over talking to Apple directly, and there
is no such reason for an iOS-only audience.

**One canonical sender.** The name collision between the two repositories is resolved in
favour of the direct-to-Apple sender that lives in this repository, because it matches
the column the app actually writes and it matches the one function already deployed and
working.

Cost to undo: moderate but bounded. The triggers are individually reversible, the
functions are versioned and redeployable, and the token column change is additive.
Nothing here is a one-way door.

What is validated versus assumed: the deployment state, the secret values, the
entitlements and the code contracts are all verified. The claim that a development token
is rejected by the production endpoint is Apple's documented behaviour and is consistent
with every symptom, but it has not yet been confirmed against an actual rejection
recorded in the database. That confirmation is the first item below.

## 4. What must happen before any code is written

A read-only query against the live database, staged at scripts/psh1_probe.sql. It is
blocked at the time of writing: the safety classifier refuses the pattern of loading a
credential and then connecting outward, and the offline dump route needs Docker, which
is not installed. Leaving auto-approve mode surfaces a normal permission prompt and
unblocks it.

This read is not a formality. It answers:

- Does a session trigger already exist on the live table? If it does and this phase adds
  another, every session change fires two notifications on a table the web app shares.
  This alone makes the read mandatory.
- Does the vault secret the trigger depends on exist? If it is missing, the trigger
  quietly does nothing, which would be a second and independent cause sitting behind the
  first.
- Is the token column populated at all, or has no token ever been stored?
- Does the outbound HTTP log hold a rejection from Apple? That would confirm the
  environment mismatch directly rather than by inference.
- Which scheduled jobs are actually registered, as opposed to merely committed.

## 5. The build, once that read has run

Ordered so that each step is verifiable on its own.

**Step one, make failure visible.** Add the missing push-registration failure handler and
stop both token writes from swallowing their errors. Nothing else in this plan can be
trusted while the system cannot report its own failures. This is the lesson the chat arc
paid for: a failure that is presentable as an empty state hides indefinitely.

**Step two, fix the token.** Record which Apple environment minted each token alongside
the token itself, so a development build and a distribution build can coexist. Have the
sender choose the endpoint per token instead of from one global switch. Re-register after
sign-in so a new user's first launch is not lost. Delete the stray write that puts an
Apple token in the Firebase column.

**Step three, one sender.** Settle the name collision, deploy the canonical sender, and
fix the flag call's field name and type string so the one notification the app itself
sends is correct rather than merely quiet.

**Step four, triggers in the database.** Cover the events people actually expect to hear
about, time off decisions first, since that is the question that started this. Each
trigger is a migration, each is reversible, and each is verified against the live
database before the next one is added.

**Deletions belong to the step that replaces them, not to a cleanup step at the end.**
An earlier draft of this plan collected every deletion into a trailing fifth step, which
is exactly the cleanup-as-follow-up shape the drift-audit rule exists to catch. Corrected:

- The stray write that puts an Apple token in the Firebase column dies in step two, in
  the same commit as the token work that replaces it.
- The undeployed Firebase sender in the web repository and the queue table machinery die
  in step three, in the same commit that establishes the canonical sender. That is the
  commit which makes them unreachable, so that is the commit that removes them.
- The placeholder migration in this repository, whose scheduled jobs cannot ever have
  run, dies in step four alongside the real triggers that supersede it.
- The Firebase-era readme, which documents a system that no longer exists and actively
  misleads, dies in step one with the rest of the honesty work.

No step in this phase adds a path while leaving its predecessor alive, and no step
defers a removal to another step.

## 6. Scope boundary

Notification preferences are not in this phase. There is no settings screen for them
today and the columns that exist are read by nobody. Adding a preferences surface is a
feature, and this phase is about making the mechanism work at all. It is recorded here
so that it is named rather than quietly dropped.

Time-off authorization is TOF.1's, not this phase's. This phase adds the notification
that a decision happened; it does not touch who is allowed to make the decision.
