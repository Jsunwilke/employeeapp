// Chat Notification Edge Function
// Called by Supabase webhook when new chat messages are created

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  sendPushNotificationBatch,
  type TokenTarget,
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
    const { type, record } = payload;

    // Only handle new messages
    if (type !== "INSERT") {
      return new Response(
        JSON.stringify({ message: "Not an insert, skipping" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const messageId = record.id as string;
    const conversationId = record.conversation_id as string;
    const senderId = record.sender_id as string;
    const messageText = record.message_text as string || "";

    // Get the conversation to find participants
    const { data: conversation, error: convError } = await supabase
      .from("conversations")
      .select("participants, name")
      .eq("id", conversationId)
      .single();

    if (convError || !conversation) {
      console.error("Error fetching conversation:", convError);
      throw new Error("Conversation not found");
    }

    // Get sender name
    const { data: sender, error: senderError } = await supabase
      .from("users")
      .select("first_name, last_name")
      .eq("id", senderId.toLowerCase())
      .single();

    const senderName = sender
      ? `${sender.first_name || ""} ${sender.last_name || ""}`.trim()
      : "Someone";

    // Get participants except the sender
    const participants = (conversation.participants as string[]) || [];
    const recipientIds = participants.filter(
      (id) => id.toLowerCase() !== senderId.toLowerCase()
    );

    if (recipientIds.length === 0) {
      return new Response(
        JSON.stringify({ message: "No recipients to notify" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get APNs tokens for recipients
    const { data: users, error } = await supabase
      .from("users")
      .select("id, apns_token, apns_environment")
      .in("id", recipientIds.map((id) => id.toLowerCase()))
      .not("apns_token", "is", null);

    if (error) {
      console.error("Error fetching user tokens:", error);
      throw error;
    }

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

    // Truncate message for notification
    const truncatedMessage =
      messageText.length > 100
        ? messageText.substring(0, 100) + "..."
        : messageText;

    const title = conversation.name || senderName;
    const body = conversation.name
      ? `${senderName}: ${truncatedMessage}`
      : truncatedMessage;

    const notificationPayload = createAlertPayload(title, body, {
      type: "chat_message",
      conversationId,
      messageId,
      senderId,
      senderName,
    }, {
      threadId: conversationId,
      category: "CHAT_MESSAGE",
    });

    const results = await sendPushNotificationBatch(
      deviceTokens,
      notificationPayload,
      apnsConfig
    );

    const successful = results.filter((r) => r.success).length;

    console.log(`Chat notification: ${successful}/${deviceTokens.length} sent`);

    return new Response(
      JSON.stringify({
        success: true,
        sent: successful,
        conversationId,
        messageId,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Error in chat notification:", error);
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
