import { createClient } from "npm:@supabase/supabase-js@2.49.8";

import {
  bearerToken,
  EdgeError,
  errorResponse,
  fetchWithTimeout,
  jsonResponse,
  readJsonObject,
  requiredEnv,
  strictCorsHeaders,
} from "../_shared/edge.ts";

Deno.serve(async (request) => {
  const requestId = crypto.randomUUID();
  let cors: Record<string, string> = {};
  try {
    cors = strictCorsHeaders(request, "IMAGE_PROCESSING_ALLOWED_WEB_ORIGINS");
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      throw new EdgeError(405, "method_not_allowed", "Use POST");
    }

    const body = await readJsonObject(request, 8 * 1024);
    const productId = String(body.product_id ?? "").toLowerCase();
    if (!isUuid(productId)) {
      throw new EdgeError(
        400,
        "invalid_product_id",
        "product_id must be a UUID",
      );
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
    const { data: authData, error: authError } = await admin.auth.getUser(
      bearerToken(request),
    );
    if (authError || !authData.user) {
      throw new EdgeError(401, "invalid_session", "Authentication required");
    }
    const { data: product, error: productError } = await admin
      .from("products")
      .select("seller_id")
      .eq("id", productId)
      .maybeSingle();
    if (productError) {
      throw new EdgeError(
        503,
        "product_lookup_failed",
        "Product ownership could not be verified",
      );
    }
    if (!product) {
      throw new EdgeError(404, "product_not_found", "Product not found");
    }
    if (product.seller_id !== authData.user.id) {
      throw new EdgeError(
        403,
        "product_owner_required",
        "Only the product owner can process it",
      );
    }

    const { data: job, error: enqueueError } = await admin.rpc(
      "enqueue_product_enrichment_job",
      {
        p_product_id: productId,
        p_reason: "edge_process_product_image",
        p_force: false,
      },
    );
    if (enqueueError) {
      throw new EdgeError(
        503,
        "enrichment_queue_failed",
        "Product enrichment could not be queued",
      );
    }

    const workerWoken = await wakeAnalyzer();
    return jsonResponse(
      {
        queued: true,
        product_id: productId,
        job_id: typeof job === "string" ? job : null,
        worker_woken: workerWoken,
        request_id: requestId,
      },
      202,
      cors,
    );
  } catch (error) {
    return errorResponse(error, requestId, cors);
  }
});

async function wakeAnalyzer(): Promise<boolean> {
  const rawUrl = Deno.env.get("PRODUCT_ANALYZER_URL")?.trim();
  if (!rawUrl) return false;
  const analyzerUrl = validateAnalyzerUrl(rawUrl);
  const sharedSecret = requiredEnv("PRODUCT_ANALYZER_SHARED_SECRET");
  if (sharedSecret.length < 32) {
    throw new EdgeError(
      500,
      "server_misconfigured",
      "Analyzer service secret is invalid",
    );
  }
  try {
    const response = await fetchWithTimeout(
      new URL("/v1/enrichment/wakeup", analyzerUrl),
      {
        method: "POST",
        headers: { "X-Analyzer-Service-Token": sharedSecret },
      },
      3_000,
    );
    await response.body?.cancel().catch(() => undefined);
    return response.ok;
  } catch (error) {
    console.warn(
      "Analyzer wake-up failed; durable queue will be polled",
      error,
    );
    return false;
  }
}

function validateAnalyzerUrl(value: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new EdgeError(
      500,
      "server_misconfigured",
      "PRODUCT_ANALYZER_URL is invalid",
    );
  }
  const loopback = ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname);
  if (
    (url.protocol !== "https:" && !(loopback && url.protocol === "http:")) ||
    url.username ||
    url.password ||
    url.search ||
    url.hash
  ) {
    throw new EdgeError(
      500,
      "server_misconfigured",
      "PRODUCT_ANALYZER_URL must be an HTTPS service origin",
    );
  }
  return url;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    .test(
      value,
    );
}
