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
    const organizationId = sessionData.organization_id as string;

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

    // Get assigned employee IDs from photographers array
    const photographers = sessionData.photographers as Photographer[] || [];
    const assignedEmployees = photographers.map(p => p.id);

    console.log(`Photographers found: ${photographers.length}`, assignedEmployees);

    if (assignedEmployees.length === 0) {
      return new Response(
        JSON.stringify({ message: "No assigned employees" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get APNs tokens for assigned employees
    const { data: users, error } = await supabase
      .from("users")
      .select("id, apns_token, apns_environment, first_name")
      .in("id", assignedEmployees.map((id) => id.toLowerCase()))
      .not("apns_token", "is", null);

    if (error) {
      console.error("Error fetching user tokens:", error);
      throw error;
    }

    console.log(`Users with tokens found: ${users?.length || 0}`);

    const deviceTokens: TokenTarget[] = (users || [])
      .filter((u) => Boolean(u.apns_token))
      .map((u) => ({
        token: u.apns_token as string,
        environment: (u.apns_environment as string | null) ?? null,
      }));

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

    if (type === "INSERT") {
      title = "New Session Assigned";
      body = `You've been assigned to ${schoolName}${onDate}`;
      notificationType = "session_new";
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
