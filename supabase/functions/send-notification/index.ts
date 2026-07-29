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
import { lookupTokenTargets, reapDeadTokens } from "../_shared/tokens.ts";
import { callerIsServiceRole, forbiddenResponse } from "../_shared/gate.ts";

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
    // "time_off_denied". Only server-side callers are legitimate, and they present the
    // service-role key. The gate itself lives in _shared/gate.ts — ONE copy for all three
    // push functions, with the full history of why it has the shape it has.
    if (!callerIsServiceRole(req)) {
      console.warn("send-notification: refused a non-service-role caller.");
      return forbiddenResponse(corsHeaders);
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

    // If userIds provided, fan out over their registered devices (PSH.2: one row per
    // device in user_devices, so an iPhone+iPad user is reached on both).
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    if (userIds && userIds.length > 0) {
      try {
        deviceTokens = [
          ...deviceTokens,
          ...(await lookupTokenTargets(supabase, userIds)),
        ];
      } catch (lookupError) {
        console.error("Error fetching device tokens:", lookupError);
        return new Response(
          JSON.stringify({ error: "Failed to fetch device tokens" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }
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

    // Rows Apple pronounced dead (410 Unregistered / BadDeviceToken) are deleted so
    // user_devices self-cleans. Directly-passed deviceTokens have no row; the delete
    // simply matches nothing for them.
    await reapDeadTokens(supabase, results);

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
