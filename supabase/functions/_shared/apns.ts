// APNs (Apple Push Notification Service) Helper
// Handles JWT token generation and HTTP/2 communication with Apple's push servers

import * as jose from "https://deno.land/x/jose@v4.14.4/index.ts";

// APNs endpoints
const APNS_PRODUCTION = "https://api.push.apple.com";
const APNS_SANDBOX = "https://api.sandbox.push.apple.com";

export interface APNsConfig {
  keyId: string;
  teamId: string;
  bundleId: string;
  privateKey: string;
  // NOTE (PSH.1, 2026-07-27): there is deliberately NO project-wide `production` flag.
  // Apple runs two separate push services and a token minted by one is rejected by the
  // other. A single global switch cannot serve a development install and a TestFlight
  // install at the same time — and having one is what broke every push this app ever
  // sent: it said production while the app was signed for sandbox, so Apple answered
  // 400 BadDeviceToken to all of them. The endpoint is chosen per TOKEN, from
  // users.apns_environment. Do not reintroduce a config-wide flag.
}

/** A device token together with the Apple push service that minted it. */
export interface TokenTarget {
  token: string;
  /** 'sandbox' | 'production', or null for tokens stored before PSH.1. */
  environment: string | null;
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
  config: APNsConfig,
  useProduction: boolean
): Promise<SendResult> {
  try {
    const token = await generateAPNsToken(config);
    const baseUrl = useProduction ? APNS_PRODUCTION : APNS_SANDBOX;
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
 * Send to each device on the endpoint that matches ITS OWN token.
 *
 * A token whose environment is unknown (stored before PSH.1, so NULL in the database) is
 * tried on production first and retried on sandbox ONLY when Apple specifically says
 * BadDeviceToken. That costs one wasted request for older development devices and nothing
 * once the device's next launch records its real environment. Any other error is returned
 * as-is rather than retried, so a genuine failure is not masked by a second attempt.
 */
export async function sendPushNotificationBatch(
  targets: TokenTarget[],
  payload: APNsPayload,
  config: APNsConfig
): Promise<SendResult[]> {
  const results = await Promise.all(
    targets.map(async ({ token, environment }) => {
      if (environment === "production" || environment === "sandbox") {
        return await sendPushNotification(
          token, payload, config, environment === "production"
        );
      }

      const first = await sendPushNotification(token, payload, config, true);
      if (first.success || first.error !== "BadDeviceToken") {
        return first;
      }
      return await sendPushNotification(token, payload, config, false);
    })
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
  // APNS_PRODUCTION is deliberately NOT read. See the note on APNsConfig.

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
  };
}
