// Send Push Notification Edge Function
// Sends APNs notifications to iOS devices

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  sendPushNotification,
  sendPushNotificationBatch,
  createAlertPayload,
  getAPNsConfigFromEnv,
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

    let deviceTokens: string[] = directTokens || [];

    // If userIds provided, look up their device tokens
    if (userIds && userIds.length > 0) {
      const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
      const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
      const supabase = createClient(supabaseUrl, supabaseServiceKey);

      const { data: users, error } = await supabase
        .from("users")
        .select("id, apns_token")
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
        ...(users?.map((u) => u.apns_token).filter(Boolean) || []),
      ];
    }

    if (deviceTokens.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: "No device tokens found",
          sent: 0,
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
      console.log("Failed notifications:", JSON.stringify(failed, null, 2));
    }

    return new Response(
      JSON.stringify({
        success: true,
        sent: successful,
        failed: failed.length,
        results,
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
