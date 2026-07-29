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
import { lookupTokenTargets, reapDeadTokens } from "../_shared/tokens.ts";
import { callerIsServiceRole, forbiddenResponse } from "../_shared/gate.ts";

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
    // AUTHORIZATION (PSH.2). This function resolves a conversation's participants and
    // pushes a message excerpt to every one of them, on a multi-tenant database. Without
    // this gate any signed-in employee could POST a forged webhook body and push
    // arbitrary text to the members of ANY conversation id. Only the database trigger is
    // a legitimate caller, and it presents the service-role key from the vault. The gate
    // lives in _shared/gate.ts — one copy for all three push functions.
    if (!callerIsServiceRole(req)) {
      console.warn("chat-notification: refused a non-service-role caller.");
      return forbiddenResponse(corsHeaders);
    }

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
    // The column is `text` — both clients write messages.text (verified live; there has
    // never been a message_text column). The old read of record.message_text meant every
    // chat push body would have been empty.
    const messageText = record.text as string || "";

    // Conversation and sender-name lookups run in PARALLEL (review round): both depend
    // only on the webhook record, and this is the per-message hot path — serializing
    // them added a full DB round trip of latency to every chat push.
    const [convResult, senderResult] = await Promise.all([
      supabase
        .from("conversations")
        .select("participants, name")
        .eq("id", conversationId)
        .single(),
      supabase
        .from("users")
        .select("first_name, last_name")
        .eq("id", senderId.toLowerCase())
        .single(),
    ]);

    const { data: conversation, error: convError } = convResult;
    if (convError || !conversation) {
      console.error("Error fetching conversation:", convError);
      throw new Error("Conversation not found");
    }

    const { data: sender } = senderResult;

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

    // Fan out over every registered device of every recipient (PSH.2: user_devices).
    const deviceTokens: TokenTarget[] = await lookupTokenTargets(supabase, recipientIds);

    if (deviceTokens.length === 0) {
      return new Response(
        JSON.stringify({ message: "No device tokens found" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // The iOS GIF send path stores the raw Giphy URL as a FILE-type message's `text`,
    // which is noise on a lock screen. The label applies only when the message type is
    // 'file' AND the text is a bare URL (review round narrowed this): a plain TEXT
    // message that is just a pasted link — "https://forms.school.edu/retake-signup" —
    // is the message's whole content and must pass through verbatim, and real
    // attachment texts ("📷 Photo", a filename) are untouched either way.
    const isBareUrl = /^https?:\/\/\S+$/.test(messageText.trim());
    const displayText =
      (record.type as string) === "file" && isBareUrl ? "Sent an attachment" : messageText;

    // Truncate message for notification
    const truncatedMessage =
      displayText.length > 100
        ? displayText.substring(0, 100) + "..."
        : displayText;

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

    await reapDeadTokens(supabase, results);

    const successful = results.filter((r) => r.success).length;
    const failed = results.filter((r) => !r.success);

    console.log(`Chat notification: ${successful}/${deviceTokens.length} sent`);
    if (failed.length > 0) {
      // Reasons only — SendResult carries the device token, a per-device credential.
      console.log(
        "Failed notifications:",
        failed.map((f) => ({ error: f.error, statusCode: f.statusCode }))
      );
    }

    return new Response(
      JSON.stringify({
        // Honest: true only if a device was actually reached. (PSH.1)
        success: successful > 0,
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
