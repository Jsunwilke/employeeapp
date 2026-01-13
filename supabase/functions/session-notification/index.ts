// Session Notification Edge Function (Standalone - APNs code inlined)
// Called by Supabase webhook when sessions are created/updated

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as jose from "https://deno.land/x/jose@v4.14.4/index.ts";

// ============================================================================
// APNs Helper Code (inlined from _shared/apns.ts for dashboard deployment)
// ============================================================================

const APNS_PRODUCTION = "https://api.push.apple.com";
const APNS_SANDBOX = "https://api.sandbox.push.apple.com";

interface APNsConfig {
  keyId: string;
  teamId: string;
  bundleId: string;
  privateKey: string;
  production?: boolean;
}

interface APNsPayload {
  aps: {
    alert?: {
      title?: string;
      subtitle?: string;
      body?: string;
    } | string;
    badge?: number;
    sound?: string | { name: string; volume?: number };
    "content-available"?: number;
    "mutable-content"?: number;
    category?: string;
    "thread-id"?: string;
  };
  [key: string]: unknown;
}

interface SendResult {
  success: boolean;
  deviceToken: string;
  apnsId?: string;
  error?: string;
  statusCode?: number;
}

async function generateAPNsToken(config: APNsConfig): Promise<string> {
  const privateKey = await jose.importPKCS8(config.privateKey, "ES256");
  const jwt = await new jose.SignJWT({})
    .setProtectedHeader({
      alg: "ES256",
      kid: config.keyId,
    })
    .setIssuer(config.teamId)
    .setIssuedAt()
    .sign(privateKey);
  return jwt;
}

async function sendPushNotification(
  deviceToken: string,
  payload: APNsPayload,
  config: APNsConfig
): Promise<SendResult> {
  try {
    const token = await generateAPNsToken(config);
    const baseUrl = config.production ? APNS_PRODUCTION : APNS_SANDBOX;
    const url = `${baseUrl}/3/device/${deviceToken}`;

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "authorization": `bearer ${token}`,
        "apns-topic": config.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const apnsId = response.headers.get("apns-id");

    if (response.ok) {
      return { success: true, deviceToken, apnsId: apnsId || undefined };
    } else {
      const errorBody = await response.json().catch(() => ({}));
      return {
        success: false,
        deviceToken,
        apnsId: apnsId || undefined,
        error: errorBody.reason || "Unknown error",
        statusCode: response.status,
      };
    }
  } catch (error) {
    return {
      success: false,
      deviceToken,
      error: error instanceof Error ? error.message : "Unknown error",
    };
  }
}

async function sendPushNotificationBatch(
  deviceTokens: string[],
  payload: APNsPayload,
  config: APNsConfig
): Promise<SendResult[]> {
  const results = await Promise.all(
    deviceTokens.map((token) => sendPushNotification(token, payload, config))
  );
  return results;
}

function createAlertPayload(
  title: string,
  body: string,
  data?: Record<string, unknown>
): APNsPayload {
  return {
    aps: {
      alert: { title, body },
      sound: "default",
    },
    ...(data || {}),
  };
}

function getAPNsConfigFromEnv(): APNsConfig {
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const bundleId = Deno.env.get("APNS_BUNDLE_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
  const production = Deno.env.get("APNS_PRODUCTION") === "true";

  if (!keyId || !teamId || !bundleId || !privateKey) {
    throw new Error(
      "Missing required APNs environment variables: APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY"
    );
  }

  return {
    keyId,
    teamId,
    bundleId,
    privateKey: privateKey.replace(/\\n/g, "\n"),
    production,
  };
}

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
    const sessionDate = sessionData.date as string;
    const organizationId = sessionData.organization_id as string;

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
      .select("id, apns_token, first_name")
      .in("id", assignedEmployees.map((id) => id.toLowerCase()))
      .not("apns_token", "is", null);

    if (error) {
      console.error("Error fetching user tokens:", error);
      throw error;
    }

    console.log(`Users with tokens found: ${users?.length || 0}`);

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
    } else if (type === "DELETE") {
      title = "Session Cancelled";
      body = `Your session at ${schoolName} on ${sessionDate} has been cancelled`;
      notificationType = "session_delete";
    } else {
      // UPDATE - detect what changed
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
      console.log(`Failed notifications:`, failed);
    }

    return new Response(
      JSON.stringify({
        success: true,
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
