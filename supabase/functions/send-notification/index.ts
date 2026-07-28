// Send Push Notification Edge Function
// Sends APNs notifications to iOS devices

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  sendPushNotificationBatch,
  createAlertPayload,
  getAPNsConfigFromEnv,
  type TokenTarget,
} from "../_shared/apns.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface NotificationRequest {
  // Send to specific user IDs
  userIds?: string[];
  // Or send to specific device tokens directly
  deviceTokens?: string[];
  // Notification content
  title: string;
  body: string;
  subtitle?: string;
  // Optional notification options
  badge?: number;
  sound?: string;
  category?: string;
  threadId?: string;
  // Custom data to include in the notification
  data?: Record<string, unknown>;
  // Notification type for iOS app to handle
  type?: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // AUTHORIZATION. This function takes an arbitrary recipient list and arbitrary text and
    // sends it with the service-role key. Without this gate any signed-in employee could
    // push whatever they liked to ANY user id in a database shared with the web app and
    // Captura — including other organizations — and spoof a convincing `type` such as
    // "time_off_denied". It was theoretical while the function was undeployed; deploying it
    // in PSH.1 made it live, and this closes it in the same phase rather than leaving it.
    //
    // Only server-side callers are legitimate: the database triggers, and the scheduled
    // functions. All of them present the service-role key. A user JWT is refused.
    const authHeader = req.headers.get("Authorization") ?? "";
    const bearer = authHeader.replace(/^Bearer\s+/i, "");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    let callerIsServiceRole = bearer.length > 0 && bearer === serviceRoleKey;

    // The service-role key can also arrive as a signed JWT whose payload names the role,
    // rather than as the literal key string. Accept that form too, without verifying the
    // signature here — Supabase has already rejected an unsigned or invalid JWT before the
    // request reaches this function (verify_jwt is on).
    if (!callerIsServiceRole && bearer.split(".").length === 3) {
      try {
        const claims = JSON.parse(atob(bearer.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
        callerIsServiceRole = claims?.role === "service_role";
      } catch {
        callerIsServiceRole = false;
      }
    }

    if (!callerIsServiceRole) {
      console.warn("send-notification: refused a non-service-role caller.");
      return new Response(
        JSON.stringify({ error: "Forbidden" }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const apnsConfig = getAPNsConfigFromEnv();

    const requestBody: NotificationRequest = await req.json();
    const {
      userIds,
      deviceTokens: directTokens,
      title,
      body,
      subtitle,
      badge,
      sound,
      category,
      threadId,
      data,
      type,
    } = requestBody;

    if (!title || !body) {
      return new Response(
        JSON.stringify({ error: "title and body are required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Tokens passed in directly carry no recorded environment, so they are resolved the
    // same way a pre-PSH.1 stored token is: production first, sandbox on BadDeviceToken.
    let deviceTokens: TokenTarget[] = (directTokens || []).map((token) => ({
      token,
      environment: null,
    }));

    // If userIds provided, look up their device tokens
    if (userIds && userIds.length > 0) {
      const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
      const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
      const supabase = createClient(supabaseUrl, supabaseServiceKey);

      const { data: users, error } = await supabase
        .from("users")
        .select("id, apns_token, apns_environment")
        .in("id", userIds.map((id) => id.toLowerCase()))
        .not("apns_token", "is", null);

      if (error) {
        console.error("Error fetching user tokens:", error);
        return new Response(
          JSON.stringify({ error: "Failed to fetch user tokens" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      deviceTokens = [
        ...deviceTokens,
        ...(users || [])
          .filter((u) => Boolean(u.apns_token))
          .map((u) => ({
            token: u.apns_token as string,
            environment: (u.apns_environment as string | null) ?? null,
          })),
      ];
    }

    if (deviceTokens.length === 0) {
      // Reported as success:false deliberately. Nobody was reached, and PSH.1 exists
      // because this system reported success at every layer while delivering nothing.
      // "Asked to notify somebody who has no device" is a real, actionable outcome —
      // it is how you discover a user whose token never got stored.
      console.warn(
        `No device tokens found for ${userIds?.length ?? 0} requested user(s) — nobody was notified.`
      );
      return new Response(
        JSON.stringify({
          success: false,
          reason: "no_device_tokens",
          message: "No device tokens found for the requested recipients",
          sent: 0,
          failed: 0,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Create the notification payload
    const payload = createAlertPayload(title, body, {
      ...data,
      type: type || "unknown",
    }, {
      subtitle,
      badge,
      sound,
      category,
      threadId,
    });

    // Send notifications
    const results = await sendPushNotificationBatch(
      deviceTokens,
      payload,
      apnsConfig
    );

    const successful = results.filter((r) => r.success).length;
    const failed = results.filter((r) => !r.success);

    console.log(
      `Sent ${successful}/${deviceTokens.length} notifications successfully`
    );

    if (failed.length > 0) {
      // Reasons only — SendResult carries the device token, a per-device credential.
      console.log(
        "Failed notifications:",
        JSON.stringify(failed.map((f) => ({ error: f.error, statusCode: f.statusCode })), null, 2)
      );
    }

    return new Response(
      JSON.stringify({
        // True only if at least one device was actually reached. Previously this was
        // hardcoded true, so a send in which Apple rejected every single token — which
        // is what happened to every push this app sent before PSH.1 — was reported as
        // a success to the caller.
        success: successful > 0,
        sent: successful,
        failed: failed.length,
        // Device tokens are deliberately omitted. The caller does not need them and
        // they are per-device credentials; only the failure reasons are returned.
        failures: failed.map((f) => ({ error: f.error, statusCode: f.statusCode })),
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error sending notification:", error);
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
