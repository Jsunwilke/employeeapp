// Claude API Proxy Edge Function
//
// The app used to fetch the org's Anthropic API key from the app_config
// table and call api.anthropic.com directly — which meant every
// authenticated employee could read (and exfiltrate) the billable key.
// This function keeps the key server-side: the client calls this endpoint
// with its Supabase JWT (verified by the platform gateway by default),
// and the function forwards the request to Anthropic's Messages API.
//
// Secret required (never in code):
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

// Ceiling on max_tokens — high enough never to clip a legitimate roster
// scan (the app requests 32000), low enough to bound abuse. Claude
// Sonnet 4.6's max output is 64000.
const MAX_TOKENS_CAP = 64000;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    console.error("ANTHROPIC_API_KEY secret is not configured");
    return json({ error: "Service not configured" }, 503);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // Forward only the Messages API fields the app actually uses.
  const payload = {
    model: body.model,
    max_tokens: Math.min(Number(body.max_tokens) || 4096, MAX_TOKENS_CAP),
    messages: body.messages,
    ...(body.system ? { system: body.system } : {}),
    ...(body.temperature !== undefined ? { temperature: body.temperature } : {}),
  };

  if (!payload.model || !Array.isArray(payload.messages)) {
    return json({ error: "model and messages are required" }, 400);
  }

  try {
    const upstream = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    // Pass Anthropic's response (success or error) straight through so
    // the client's existing response parsing keeps working unchanged.
    const text = await upstream.text();
    return new Response(text, {
      status: upstream.status,
      headers: { ...corsHeaders, "content-type": "application/json" },
    });
  } catch (err) {
    console.error("Upstream request failed:", err);
    return json({ error: "Upstream request failed" }, 502);
  }
});

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
