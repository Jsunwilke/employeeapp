// APNs (Apple Push Notification Service) Helper
// Handles JWT token generation and HTTP/2 communication with Apple's push servers

import * as jose from "https://deno.land/x/jose@v4.14.4/index.ts";

// APNs endpoints
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

/**
 * Generate a JWT token for APNs authentication
 */
async function generateAPNsToken(config: APNsConfig): Promise<string> {
  // Parse the private key
  const privateKey = await jose.importPKCS8(config.privateKey, "ES256");

  // Create JWT
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

/**
 * Send a push notification to a single device
 */
export async function sendPushNotification(
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
      return {
        success: true,
        deviceToken,
        apnsId: apnsId || undefined,
      };
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

/**
 * Send push notifications to multiple devices
 */
export async function sendPushNotificationBatch(
  deviceTokens: string[],
  payload: APNsPayload,
  config: APNsConfig
): Promise<SendResult[]> {
  const results = await Promise.all(
    deviceTokens.map((token) => sendPushNotification(token, payload, config))
  );
  return results;
}

/**
 * Create a standard alert notification payload
 */
export function createAlertPayload(
  title: string,
  body: string,
  data?: Record<string, unknown>,
  options?: {
    subtitle?: string;
    badge?: number;
    sound?: string;
    category?: string;
    threadId?: string;
  }
): APNsPayload {
  const payload: APNsPayload = {
    aps: {
      alert: {
        title,
        body,
        ...(options?.subtitle && { subtitle: options.subtitle }),
      },
      sound: options?.sound || "default",
      ...(options?.badge !== undefined && { badge: options.badge }),
      ...(options?.category && { category: options.category }),
      ...(options?.threadId && { "thread-id": options.threadId }),
    },
    ...(data || {}),
  };
  return payload;
}

/**
 * Create a silent notification payload (for background updates)
 */
export function createSilentPayload(
  data?: Record<string, unknown>
): APNsPayload {
  return {
    aps: {
      "content-available": 1,
    },
    ...(data || {}),
  };
}

/**
 * Get APNs config from environment variables
 */
export function getAPNsConfigFromEnv(): APNsConfig {
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
    // Replace escaped newlines with actual newlines
    privateKey: privateKey.replace(/\\n/g, "\n"),
    production,
  };
}
