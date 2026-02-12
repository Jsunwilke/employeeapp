// Route Optimization Edge Function
// Uses Google Route Optimization API with OAuth2 service account authentication
// to find the optimal order to visit multiple locations

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { encode as base64Encode } from "https://deno.land/std@0.168.0/encoding/base64url.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface Location {
  latitude: number;
  longitude: number;
  label?: string;
}

interface OptimizeRouteRequest {
  origin: Location;
  destinations: Location[];
  endLocation?: Location;  // Optional end point (e.g., return to home)
}

interface RouteLeg {
  distanceMeters: number;
  durationSeconds: number;
}

interface SkippedShipment {
  index: number;
  label?: string;
}

interface OptimizeRouteResponse {
  success: boolean;
  optimizedOrder?: number[];
  totalDistanceMeters?: number;
  totalDurationSeconds?: number;
  legs?: RouteLeg[];
  error?: string;
  skippedShipments?: SkippedShipment[];
}

interface RouteOptimizationResult {
  optimizedOrder: number[];
  totalDistanceMeters: number;
  totalDurationSeconds: number;
  legs: RouteLeg[];
  skippedShipments: SkippedShipment[];
}

// Generate a JWT for Google OAuth2 authentication
async function generateJWT(
  privateKey: string,
  clientEmail: string,
  scope: string
): Promise<string> {
  const header = {
    alg: "RS256",
    typ: "JWT",
  };

  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: clientEmail,
    scope: scope,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600, // 1 hour expiry
  };

  const encodedHeader = base64Encode(
    new TextEncoder().encode(JSON.stringify(header))
  );
  const encodedPayload = base64Encode(
    new TextEncoder().encode(JSON.stringify(payload))
  );

  const signatureInput = `${encodedHeader}.${encodedPayload}`;

  // Import the private key for signing
  const pemContents = privateKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\n/g, "");

  const binaryKey = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signatureInput)
  );

  const encodedSignature = base64Encode(new Uint8Array(signature));

  return `${encodedHeader}.${encodedPayload}.${encodedSignature}`;
}

// Exchange JWT for OAuth2 access token
async function getAccessToken(
  privateKey: string,
  clientEmail: string
): Promise<string> {
  const scope = "https://www.googleapis.com/auth/cloud-platform";
  const jwt = await generateJWT(privateKey, clientEmail, scope);

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Failed to get access token: ${error}`);
  }

  const data = await response.json();
  return data.access_token;
}

// Parse duration string like "1234s" to seconds
function parseDuration(duration: string | undefined): number {
  if (!duration) return 0;
  const match = duration.match(/(\d+(?:\.\d+)?)s/);
  return match ? parseFloat(match[1]) : 0;
}

// Call Google Route Optimization API
async function optimizeRoute(
  accessToken: string,
  projectId: string,
  origin: Location,
  destinations: Location[],
  endLocation?: Location
): Promise<RouteOptimizationResult> {
  const url = `https://routeoptimization.googleapis.com/v1/projects/${projectId}:optimizeTours`;

  // Build shipments - use delivery-only approach (simpler for route optimization)
  const shipments = destinations.map((dest, index) => ({
    label: dest.label || `Stop ${index + 1}`,
    deliveries: [
      {
        arrivalWaypoint: {
          location: {
            latLng: {
              latitude: dest.latitude,
              longitude: dest.longitude,
            },
          },
        },
        duration: "300s",  // 5 min service time at each stop
      },
    ],
  }));

  // Build vehicle starting from origin
  const vehicle: Record<string, unknown> = {
    label: "Route",
    startWaypoint: {
      location: {
        latLng: {
          latitude: origin.latitude,
          longitude: origin.longitude,
        },
      },
    },
    travelMode: "DRIVING",
    // Cost model - heavily prioritize minimizing distance
    costPerKilometer: 1000.0,  // Very high cost per km to minimize distance
    costPerHour: 0.1,  // Minimal cost per hour
  };

  // Add end location if specified
  if (endLocation) {
    vehicle.endWaypoint = {
      location: {
        latLng: {
          latitude: endLocation.latitude,
          longitude: endLocation.longitude,
        },
      },
    };
  }

  const requestBody = {
    model: {
      shipments,
      vehicles: [vehicle],
    },
    // Ensure all shipments are included, even if it's not optimal
    considerRoadTraffic: false,
    // Use longer timeout for more thorough optimization
    timeout: "30s",
    // Request populated transition polylines to get distance data
    populateTransitionPolylines: false,
  };

  console.log("🗺️ Route Optimization Request:");
  console.log(`  Origin: ${origin.latitude}, ${origin.longitude}`);
  console.log(`  Destinations (${destinations.length}):`);
  destinations.forEach((dest, i) => {
    console.log(`    [${i}] ${dest.label}: ${dest.latitude}, ${dest.longitude}`);
  });
  if (endLocation) {
    console.log(`  End location: ${endLocation.latitude}, ${endLocation.longitude}`);
  }
  console.log("Full request body:", JSON.stringify(requestBody, null, 2));

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(requestBody),
  });

  if (!response.ok) {
    const error = await response.text();
    console.error("Route Optimization API error:", error);
    throw new Error(`Route Optimization API error: ${response.status} - ${error}`);
  }

  const data = await response.json();
  console.log("Route Optimization API response:", JSON.stringify(data, null, 2));

  // Extract optimized order from visits
  const route = data.routes?.[0];
  const visits = route?.visits || [];
  const transitions = route?.transitions || [];
  const skippedShipments = route?.skippedShipments || [];


  console.log(`\n📊 Route Analysis:`);
  console.log(`  Total shipments sent: ${destinations.length}`);
  console.log(`  Visits in route: ${visits.length}`);
  console.log(`  Skipped shipments: ${skippedShipments.length}`);

  if (skippedShipments.length > 0) {
    console.log(`  ⚠️  Skipped shipments:`);
    skippedShipments.forEach((skipped: any) => {
      console.log(`    - Shipment ${skipped.index}: ${skipped.label || 'Unknown'}`);
      console.log(`      Full skipped data: ${JSON.stringify(skipped, null, 2)}`);
      if (skipped.reasons) {
        skipped.reasons.forEach((reason: any) => {
          console.log(`      Reason code: ${reason.code || 'UNKNOWN'}`);
          console.log(`      Full reason: ${JSON.stringify(reason, null, 2)}`);
        });
      }
    });
  }

  // Get the optimized order of shipments (0-indexed)
  // Some visits may not have shipmentIndex, so we need to match by label
  const optimizedOrder: number[] = [];
  for (const visit of visits) {
    if (visit.shipmentIndex !== undefined) {
      optimizedOrder.push(visit.shipmentIndex);
    } else if (visit.shipmentLabel) {
      // Find the shipment index by matching the label
      const matchIndex = destinations.findIndex(dest => dest.label === visit.shipmentLabel);
      if (matchIndex !== -1) {
        optimizedOrder.push(matchIndex);
        console.log(`  ⚠️  Visit without shipmentIndex matched by label: ${visit.shipmentLabel} → index ${matchIndex}`);
      }
    }
  }

  // Extract distance and duration from transitions
  // transitions[0] = origin to first stop
  // transitions[1..n] = between stops
  // transitions[n+1] = last stop to end (if endLocation specified)
  let totalDistanceMeters = 0;
  let totalDurationSeconds = 0;
  const legs: RouteLeg[] = [];

  for (const transition of transitions) {
    const distanceMeters = transition.travelDistanceMeters || 0;
    const durationSeconds = parseDuration(transition.travelDuration);

    totalDistanceMeters += distanceMeters;
    totalDurationSeconds += durationSeconds;

    legs.push({
      distanceMeters,
      durationSeconds,
    });
  }

  console.log(`\n✅ Route Optimization Result:`);
  console.log(`  Optimized order: [${optimizedOrder.join(', ')}]`);
  console.log(`  Total distance: ${totalDistanceMeters}m (${(totalDistanceMeters * 0.000621371).toFixed(1)} mi)`);
  console.log(`  Total duration: ${totalDurationSeconds}s (${Math.round(totalDurationSeconds / 60)} min)`);
  console.log(`  Leg details:`);
  legs.forEach((leg, i) => {
    console.log(`    Leg ${i}: ${leg.distanceMeters}m (${(leg.distanceMeters * 0.000621371).toFixed(1)} mi), ${leg.durationSeconds}s (${Math.round(leg.durationSeconds / 60)} min)`);
  });

  // Map skipped shipments to simple format
  const skippedShipmentsData: SkippedShipment[] = skippedShipments.map((skipped: any) => ({
    index: skipped.index || 0,
    label: skipped.label,
  }));

  return {
    optimizedOrder,
    totalDistanceMeters,
    totalDurationSeconds,
    legs,
    skippedShipments: skippedShipmentsData,
  };
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get service account credentials from environment
    const privateKey = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY");
    const clientEmail = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL");
    const projectId = Deno.env.get("GOOGLE_CLOUD_PROJECT_ID");

    if (!privateKey || !clientEmail || !projectId) {
      console.error("Missing environment variables:", {
        hasPrivateKey: !!privateKey,
        hasClientEmail: !!clientEmail,
        hasProjectId: !!projectId,
      });
      return new Response(
        JSON.stringify({
          success: false,
          error: "Server configuration error: missing credentials",
        } as OptimizeRouteResponse),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Parse request body
    const requestBody: OptimizeRouteRequest = await req.json();
    const { origin, destinations, endLocation } = requestBody;

    if (!origin || !destinations || destinations.length === 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "origin and destinations are required",
        } as OptimizeRouteResponse),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (destinations.length === 1) {
      // Only one destination, no optimization needed
      // But we still need to calculate distance if requested
      console.log("Single destination - returning order [0]");
      return new Response(
        JSON.stringify({
          success: true,
          optimizedOrder: [0],
          totalDistanceMeters: 0,  // Would need separate API call for single destination
          totalDurationSeconds: 0,
          legs: [],
        } as OptimizeRouteResponse),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    console.log(`Optimizing route from origin to ${destinations.length} destinations${endLocation ? ' with end location' : ''}`);

    // Get OAuth2 access token
    const accessToken = await getAccessToken(privateKey, clientEmail);
    console.log("Successfully obtained access token");

    // Call Route Optimization API
    const result = await optimizeRoute(
      accessToken,
      projectId,
      origin,
      destinations,
      endLocation
    );

    console.log("Optimized order:", result.optimizedOrder);

    return new Response(
      JSON.stringify({
        success: true,
        optimizedOrder: result.optimizedOrder,
        totalDistanceMeters: result.totalDistanceMeters,
        totalDurationSeconds: result.totalDurationSeconds,
        legs: result.legs,
        skippedShipments: result.skippedShipments,
      } as OptimizeRouteResponse),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error optimizing route:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
      } as OptimizeRouteResponse),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
