// Session Notification Edge Function
// Called by Supabase webhook when sessions are created/updated

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  sendPushNotificationBatch,
  createAlertPayload,
  getAPNsConfigFromEnv,
} from "../_shared/apns.ts";

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

    // Only notify for published sessions
    if (!record.is_published) {
      return new Response(
        JSON.stringify({ message: "Session not published, skipping" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const sessionId = record.id as string;
    const schoolName = record.school_name as string || "Unknown School";
    const sessionDate = record.session_date as string;
    const organizationId = record.organization_id as string;

    // Get assigned employee IDs
    const assignedEmployees = record.assigned_employees as string[] || [];

    if (assignedEmployees.length === 0) {
      return new Response(
        JSON.stringify({ message: "No assigned employees" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get APNs tokens for assigned employees
    const { data: users, error } = await supabase
      .from("users")
      .select("id, apns_token, first_name")
      .in("id", assignedEmployees.map((id) => id.toLowerCase()))
      .not("apns_token", "is", null);

    if (error) {
      console.error("Error fetching user tokens:", error);
      throw error;
    }

    const deviceTokens = users?.map((u) => u.apns_token).filter(Boolean) || [];

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

    if (type === "INSERT") {
      title = "New Session Assigned";
      body = `You've been assigned to ${schoolName} on ${sessionDate}`;
      notificationType = "session_new";
    } else {
      // UPDATE - detect what changed
      const changes: string[] = [];
      if (old_record?.session_date !== record.session_date) {
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

    const results = await sendPushNotificationBatch(
      deviceTokens,
      notificationPayload,
      apnsConfig
    );

    const successful = results.filter((r) => r.success).length;

    console.log(`Session notification: ${successful}/${deviceTokens.length} sent`);

    return new Response(
      JSON.stringify({
        success: true,
        sent: successful,
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
