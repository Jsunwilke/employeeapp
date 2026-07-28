// Clock Reminder Edge Function
// Called by pg_cron to send clock-in/clock-out reminders

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

interface ReminderRequest {
  type: "clock_in" | "clock_out";
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

    const body = await req.json().catch(() => ({}));
    const reminderType = body.type || "clock_in";

    const now = new Date();
    const today = now.toISOString().split("T")[0];

    if (reminderType === "clock_in") {
      // Clock-in reminder: Find sessions starting in the next 30 minutes
      const thirtyMinutesFromNow = new Date(now.getTime() + 30 * 60 * 1000);
      const targetTime = thirtyMinutesFromNow.toTimeString().slice(0, 5);
      const currentTime = now.toTimeString().slice(0, 5);

      // Get day-rows starting soon. A session's date/time live in the
      // `session_days` child table; the parent session (school + assigned
      // photographers + published flag) is embedded.
      const { data: dayRows, error: sessionsError } = await supabase
        .from("session_days")
        .select(
          "start_time, session:sessions!inner(id, school_name, photographers, is_published)"
        )
        .eq("date", today)
        .gte("start_time", currentTime)
        .lte("start_time", targetTime);

      if (sessionsError) {
        console.error("Error fetching sessions:", sessionsError);
        throw sessionsError;
      }

      if (!dayRows || dayRows.length === 0) {
        return new Response(
          JSON.stringify({ message: "No upcoming sessions found" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // For each upcoming day, notify assigned photographers who haven't clocked in
      let totalSent = 0;

      for (const day of dayRows) {
        const session = (day as Record<string, unknown>).session as
          | { id: string; school_name: string; photographers?: { id: string }[]; is_published?: boolean }
          | null;

        if (!session || !session.is_published) continue;

        const startTime = (day as Record<string, unknown>).start_time as string;
        const assignedEmployees = (session.photographers || []).map((p) => p.id);

        if (assignedEmployees.length === 0) continue;

        // Check who has already clocked in
        const { data: clockedIn } = await supabase
          .from("time_entries")
          .select("user_id")
          .eq("session_id", session.id)
          .not("clock_in_time", "is", null);

        const clockedInIds = new Set(
          clockedIn?.map((e) => e.user_id.toLowerCase()) || []
        );

        // Filter to employees who haven't clocked in
        const needsReminder = assignedEmployees.filter(
          (id) => !clockedInIds.has(id.toLowerCase())
        );

        if (needsReminder.length === 0) continue;

        // Get device tokens
        const { data: users } = await supabase
          .from("users")
          .select("apns_token, apns_environment")
          .in("id", needsReminder.map((id) => id.toLowerCase()))
          .not("apns_token", "is", null);

        const deviceTokens =
          (users || [])
            .filter((u) => Boolean(u.apns_token))
            .map((u) => ({
              token: u.apns_token as string,
              environment: (u.apns_environment as string | null) ?? null,
            }));

        if (deviceTokens.length === 0) continue;

        const payload = createAlertPayload(
          "Clock-In Reminder",
          `Your session at ${session.school_name} starts at ${startTime}. Don't forget to clock in!`,
          {
            type: "clock_reminder",
            reminderType: "clock_in",
            sessionId: session.id,
            schoolName: session.school_name,
          }
        );

        const results = await sendPushNotificationBatch(
          deviceTokens,
          payload,
          apnsConfig
        );

        totalSent += results.filter((r) => r.success).length;
      }

      return new Response(
        JSON.stringify({
          success: true,
          type: "clock_in",
          sent: totalSent,
          sessionsChecked: dayRows.length,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    } else {
      // Clock-out reminder: Find employees still clocked in at end of day
      const { data: activeEntries, error: entriesError } = await supabase
        .from("time_entries")
        .select("user_id, session_id, sessions(school_name)")
        .is("clock_out_time", null)
        .not("clock_in_time", "is", null);

      if (entriesError) {
        console.error("Error fetching active entries:", entriesError);
        throw entriesError;
      }

      if (!activeEntries || activeEntries.length === 0) {
        return new Response(
          JSON.stringify({ message: "No active clock-ins found" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Get unique user IDs
      const userIds = [...new Set(activeEntries.map((e) => e.user_id))];

      // Get device tokens
      const { data: users } = await supabase
        .from("users")
        .select("id, apns_token, apns_environment")
        .in("id", userIds.map((id) => id.toLowerCase()))
        .not("apns_token", "is", null);

      const deviceTokens =
        (users || [])
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

      const payload = createAlertPayload(
        "Clock-Out Reminder",
        "You're still clocked in! Don't forget to clock out before the end of the day.",
        {
          type: "clock_reminder",
          reminderType: "clock_out",
        }
      );

      const results = await sendPushNotificationBatch(
        deviceTokens,
        payload,
        apnsConfig
      );

      const successful = results.filter((r) => r.success).length;

      return new Response(
        JSON.stringify({
          success: true,
          type: "clock_out",
          sent: successful,
          activeEntries: activeEntries.length,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
  } catch (error) {
    console.error("Error in clock reminder:", error);
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
