// Session Notification Edge Function
// Fired by the trg_session_notification trigger on public.sessions (INSERT/UPDATE/DELETE).
//
// PSH.1 (2026-07-27): the APNs helper code that used to be inlined here has been removed in
// favour of the shared module. The inlining was justified as being "for dashboard
// deployment"; the CLI deploy bundles the import correctly, and keeping two copies of the
// push plumbing is how one copy silently keeps a bug the other one fixed.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  sendPushNotificationBatch,
  createAlertPayload,
  getAPNsConfigFromEnv,
  type TokenTarget,
} from "../_shared/apns.ts";
import { lookupTokenTargets, reapDeadTokens } from "../_shared/tokens.ts";
import { callerIsServiceRole, forbiddenResponse } from "../_shared/gate.ts";

// ============================================================================
// Main Edge Function
// ============================================================================

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  schema: string;
  record: Record<string, unknown>;
  old_record: Record<string, unknown> | null;
}

interface Photographer {
  id: string;
  name: string;
  email?: string;
  notes?: string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // AUTHORIZATION (PSH.2 fix round). This function takes crew_ids verbatim and pushes
    // attacker-controllable text ("Your session at <school_name> has been cancelled") to
    // them with the service role. The PSH.2 security audit PROVED the hole live: a forged
    // webhook signed with nothing but the public anon key returned 200 here while the two
    // gated siblings returned 403 — verify_jwt accepts ANY project-signed JWT, and the
    // anon key ships in every client binary. Only the database trigger is a legitimate
    // caller, and it presents the service-role key from the vault. The gate lives in
    // _shared/gate.ts — one copy for all three push functions.
    if (!callerIsServiceRole(req)) {
      console.warn("session-notification: refused a non-service-role caller.");
      return forbiddenResponse(corsHeaders);
    }

    const apnsConfig = getAPNsConfigFromEnv();
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const payload: WebhookPayload = await req.json();
    const { type, record, old_record } = payload;

    console.log(`Session notification triggered: ${type}`, type === "DELETE" ? old_record : record);

    // For DELETE events, data is in old_record
    const sessionData = type === "DELETE" ? old_record : record;

    if (!sessionData) {
      return new Response(
        JSON.stringify({ message: "No session data found" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Only notify for published sessions (skip check for DELETE - always notify)
    if (type !== "DELETE" && !sessionData.is_published) {
      return new Response(
        JSON.stringify({ message: "Session not published, skipping" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const sessionId = sessionData.id as string;
    const schoolName = sessionData.school_name as string || "Unknown School";

    // A session's date lives in the `session_days` child table now. Prefer the
    // legacy sessions.date column while it still exists (transition); once it's
    // dropped, fall back to the first day from session_days. On DELETE the day
    // rows are already cascade-removed, so only the legacy column (if present)
    // can supply the date.
    let sessionDate = (sessionData.date as string) || "";
    if (!sessionDate && type !== "DELETE") {
      const { data: dayRows } = await supabase
        .from("session_days")
        .select("date, sort_order")
        .eq("session_id", sessionId)
        .order("date", { ascending: true })
        .order("sort_order", { ascending: true });
      if (dayRows && dayRows.length > 0) {
        const extra = dayRows.length - 1;
        sessionDate = extra > 0
          ? `${dayRows[0].date} (+${extra} more day${extra > 1 ? "s" : ""})`
          : (dayRows[0].date as string);
      }
    }

    // Resolve the assigned crew. The MD7 arc moved crew off the sessions row and onto
    // the session_days child rows (sessions has NO photographers column on the live
    // schema — verified, and it is why this function delivered nothing between the crew
    // move and PSH.2: record.photographers was always missing and every fire exited
    // "No assigned employees"). Resolution order:
    //   1. crew_ids injected by the BEFORE DELETE trigger, which runs while the day rows
    //      still exist (an AFTER trigger would find them cascade-deleted).
    //   2. The union of session_days.photographers for this session.
    //   3. record.photographers, kept only for a replayed pre-MD7 payload.
    let assignedEmployees: string[] = [];

    const crewIds = sessionData.crew_ids as string[] | undefined;
    if (crewIds && crewIds.length > 0) {
      assignedEmployees = crewIds;
    } else if (type !== "DELETE") {
      const { data: dayCrew, error: dayCrewError } = await supabase
        .from("session_days")
        .select("photographers")
        .eq("session_id", sessionId);
      if (dayCrewError) {
        console.error("Error fetching session_days crew:", dayCrewError);
        throw dayCrewError;
      }
      const ids = new Set<string>();
      for (const day of dayCrew || []) {
        for (const p of (day.photographers as Photographer[] | null) || []) {
          if (p?.id) ids.add(p.id);
        }
      }
      assignedEmployees = [...ids];
    }

    // NOTE (review round): an earlier version fell back to record.photographers — the
    // pre-MD7 embedded crew array — "for replayed old payloads". That was a parallel
    // implementation of the path this phase replaced (delete-first violation), and its
    // one activation route was exactly the hazard the roadmap warns about: a replayed
    // historical webhook resolving a years-stale crew list and pushing session changes
    // to people long off the session. Deleted; session_days and crew_ids are the only
    // crew sources.

    console.log(`Crew resolved: ${assignedEmployees.length} assignee(s)`);

    if (assignedEmployees.length === 0) {
      return new Response(
        JSON.stringify({ message: "No assigned employees" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fan out over every registered device of every assignee (PSH.2: user_devices).
    const deviceTokens: TokenTarget[] = await lookupTokenTargets(supabase, assignedEmployees);

    if (deviceTokens.length === 0) {
      return new Response(
        JSON.stringify({ message: "No device tokens found" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Determine notification type and message
    let title: string;
    let body: string;
    let notificationType: string;

    const onDate = sessionDate ? ` on ${sessionDate}` : "";

    // A publish is a debut, not an edit: the crew has never seen the session, so
    // "Session Updated" would be nonsense. The trigger now fires UPDATE only for
    // is_published/school_name transitions (PSH.2), and the unpublished->published one
    // lands here. (A plain INSERT never reaches this function any more — both clients
    // insert the sessions row before the day rows carrying the crew, so the old INSERT
    // fire never had a recipient; the "new session" push for direct-published sessions
    // comes from the session_days trigger instead.)
    //
    // The REVERSE transition is a retraction, not an edit (review round): pulling a
    // published session back to draft removes it from the crew's schedule (PUB.1 draft
    // redaction), so "Session Updated" was misleading and its tap dead-ended — and a
    // subsequent draft delete is deliberately silent, so without this the crew were
    // never told at all and could still show up. An unpublish reads as a cancellation;
    // if the session is later re-published, the publish transition announces it anew.
    const wasPublished = Boolean(old_record?.is_published);
    const isPublishTransition =
      type === "UPDATE" && !wasPublished && Boolean(record.is_published);
    const isUnpublishTransition =
      type === "UPDATE" && wasPublished && !record.is_published;

    if (type === "INSERT" || isPublishTransition) {
      title = "New Session Assigned";
      body = `You've been assigned to ${schoolName}${onDate}`;
      notificationType = "session_new";
    } else if (isUnpublishTransition) {
      title = "Session Cancelled";
      body = `Your session at ${schoolName}${onDate} has been cancelled`;
      notificationType = "session_delete";
    } else if (type === "DELETE") {
      title = "Session Cancelled";
      body = `Your session at ${schoolName}${onDate} has been cancelled`;
      notificationType = "session_delete";
    } else {
      // UPDATE - detect what changed. date/start_time live in session_days now;
      // these legacy-column comparisons still work while the columns exist
      // (transition) and harmlessly report no date/time change once dropped — a
      // pure day move is a session_days change that doesn't fire this sessions
      // trigger anyway (see rollout note: a session_days-trigger notification is
      // the follow-up for granular day-move pushes).
      const changes: string[] = [];
      if (old_record?.date !== record.date) {
        changes.push("date");
      }
      if (old_record?.start_time !== record.start_time) {
        changes.push("time");
      }
      if (old_record?.school_name !== record.school_name) {
        changes.push("location");
      }

      title = "Session Updated";
      body = changes.length > 0
        ? `${schoolName} session updated: ${changes.join(", ")} changed`
        : `${schoolName} session has been updated`;
      notificationType = "session_update";
    }

    const notificationPayload = createAlertPayload(title, body, {
      type: notificationType,
      sessionId,
      schoolName,
      sessionDate,
    });

    console.log(`Sending notifications to ${deviceTokens.length} devices`);

    const results = await sendPushNotificationBatch(
      deviceTokens,
      notificationPayload,
      apnsConfig
    );

    await reapDeadTokens(supabase, results);

    const successful = results.filter((r) => r.success).length;
    const failed = results.filter((r) => !r.success);

    console.log(`Session notification: ${successful}/${deviceTokens.length} sent`);
    if (failed.length > 0) {
      // Reasons only. SendResult carries the device token, which is a per-device
      // credential and must not be written to a log the whole team can read.
      console.log(
        `Failed notifications:`,
        failed.map((f) => ({ error: f.error, statusCode: f.statusCode }))
      );
    }

    return new Response(
      JSON.stringify({
        // True only if at least one device was actually reached. Hardcoding true here is
        // what let "Apple rejected every token" read as a success to the trigger.
        success: successful > 0,
        sent: successful,
        failed: failed.length,
        sessionId,
        type: notificationType,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Error in session notification:", error);
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
