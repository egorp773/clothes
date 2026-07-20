import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.49.8";

import {
  bearerToken,
  EdgeError,
  errorResponse,
  fetchWithTimeout,
  jsonResponse,
  readJsonObject,
  readLimitedBody,
  requiredEnv,
  sha256BytesHex,
  strictCorsHeaders,
} from "../_shared/edge.ts";
import {
  accessoryImageBucket,
  canonicalAccessoryStoragePath,
} from "../_shared/accessory_storage.ts";

const bucketName = accessoryImageBucket;
const maxInputBytes = 15 * 1024 * 1024;
const maxOutputBytes = 20 * 1024 * 1024;

type EdgeRuntimeGlobal = {
  EdgeRuntime?: {
    waitUntil: (promise: Promise<unknown>) => void;
  };
};

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
    const accessoryId = String(body.accessory_id ?? "").toLowerCase();
    if (!isUuid(accessoryId)) {
      throw new EdgeError(
        400,
        "invalid_accessory_id",
        "accessory_id must be a UUID",
      );
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const analyzerUrl = validateAnalyzerUrl(
      requiredEnv("PRODUCT_ANALYZER_URL"),
    );
    const analyzerSecret = requiredEnv("PRODUCT_ANALYZER_SHARED_SECRET");
    if (analyzerSecret.length < 32) {
      throw new EdgeError(
        500,
        "server_misconfigured",
        "Analyzer service secret is invalid",
      );
    }
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
    const { data: accessory, error: accessoryError } = await admin
      .from("outfit_accessories")
      .select("owner_id,original_image,scope")
      .eq("id", accessoryId)
      .maybeSingle();
    if (accessoryError) {
      throw new EdgeError(
        503,
        "accessory_lookup_failed",
        "Accessory ownership could not be verified",
      );
    }
    if (!accessory) {
      throw new EdgeError(404, "accessory_not_found", "Accessory not found");
    }
    if (
      accessory.owner_id !== authData.user.id ||
      accessory.scope !== "private"
    ) {
      throw new EdgeError(
        403,
        "accessory_owner_required",
        "Only the private accessory owner can process it",
      );
    }
    const originalPath = canonicalAccessoryStoragePath(
      String(accessory.original_image ?? ""),
      supabaseUrl,
      authData.user.id,
      accessoryId,
    );

    const work = processAccessoryImage({
      admin,
      supabaseUrl,
      serviceRoleKey,
      analyzerUrl,
      analyzerSecret,
      accessoryId,
      originalPath,
      ownerId: authData.user.id,
      requestId,
    });
    const edgeRuntime = (globalThis as EdgeRuntimeGlobal).EdgeRuntime;
    if (edgeRuntime) {
      edgeRuntime.waitUntil(work);
    } else {
      await work;
    }
    return jsonResponse(
      {
        queued: true,
        accessory_id: accessoryId,
        request_id: requestId,
      },
      202,
      cors,
    );
  } catch (error) {
    return errorResponse(error, requestId, cors);
  }
});

async function processAccessoryImage({
  admin,
  supabaseUrl,
  serviceRoleKey,
  analyzerUrl,
  analyzerSecret,
  accessoryId,
  originalPath,
  ownerId,
  requestId,
}: {
  admin: SupabaseClient;
  supabaseUrl: string;
  serviceRoleKey: string;
  analyzerUrl: URL;
  analyzerSecret: string;
  accessoryId: string;
  originalPath: string;
  ownerId: string;
  requestId: string;
}): Promise<void> {
  await admin
    .from("outfit_accessories")
    .update({ background_status: "processing", background_error: null })
    .eq("id", accessoryId)
    .eq("owner_id", ownerId);

  try {
    const original = await downloadStorageObject({
      supabaseUrl,
      serviceRoleKey,
      path: originalPath,
      maxBytes: maxInputBytes,
    });
    const form = new FormData();
    form.append(
      "file",
      new Blob([Uint8Array.from(original.bytes).buffer], {
        type: original.mimeType,
      }),
      `${accessoryId}.${extensionForMime(original.mimeType)}`,
    );
    const response = await fetchWithTimeout(
      new URL("/v1/remove-background", analyzerUrl),
      {
        method: "POST",
        headers: { "X-Analyzer-Service-Token": analyzerSecret },
        body: form,
      },
      30_000,
    );
    if (!response.ok) {
      await response.body?.cancel().catch(() => undefined);
      throw new EdgeError(
        502,
        "background_removal_failed",
        "Background removal service failed",
      );
    }
    const mimeType = (response.headers.get("content-type") ?? "")
      .split(";", 1)[0]
      .trim()
      .toLowerCase();
    if (mimeType !== "image/png") {
      await response.body?.cancel().catch(() => undefined);
      throw new EdgeError(
        502,
        "invalid_analyzer_response",
        "Background removal returned an invalid image type",
      );
    }
    const advertised = Number(response.headers.get("content-length") ?? 0);
    if (
      !Number.isFinite(advertised) || advertised < 0 ||
      advertised > maxOutputBytes
    ) {
      throw new EdgeError(
        502,
        "invalid_analyzer_response",
        "Background removal response is too large",
      );
    }
    const cutout = await readLimitedBody(response.body, maxOutputBytes);
    assertPng(cutout);
    const contentHash = await sha256BytesHex(cutout);
    const cutoutPath = `${ownerId}/${accessoryId}/cutout-` +
      `${contentHash.slice(0, 24)}.png`;
    const uploaded = await admin.storage
      .from(bucketName)
      .upload(cutoutPath, cutout, {
        contentType: "image/png",
        cacheControl: "31536000",
        upsert: false,
      });
    if (
      uploaded.error && !await sameStoredObject(
        {
          supabaseUrl,
          serviceRoleKey,
          path: cutoutPath,
          maxBytes: maxOutputBytes,
        },
        contentHash,
      )
    ) {
      throw new EdgeError(
        503,
        "cutout_upload_failed",
        "Processed image could not be stored",
      );
    }

    // Store the canonical object path rather than a public URL. The bucket is
    // private and access is mediated by RLS/signed delivery.
    const updated = await admin
      .from("outfit_accessories")
      .update({
        cutout_image: cutoutPath,
        background_status: "completed",
        background_error: null,
      })
      .eq("id", accessoryId)
      .eq("owner_id", ownerId);
    if (updated.error) {
      throw new EdgeError(
        503,
        "accessory_update_failed",
        "Accessory processing result could not be saved",
      );
    }
  } catch (error) {
    const code = error instanceof EdgeError
      ? error.code
      : "background_processing_failed";
    console.error(`[process-accessory-image:${requestId}] ${code}`, error);
    await admin
      .from("outfit_accessories")
      .update({
        background_status: "failed",
        background_error: code,
      })
      .eq("id", accessoryId)
      .eq("owner_id", ownerId);
  }
}

async function downloadStorageObject({
  supabaseUrl,
  serviceRoleKey,
  path,
  maxBytes,
}: {
  supabaseUrl: string;
  serviceRoleKey: string;
  path: string;
  maxBytes: number;
}): Promise<{ bytes: Uint8Array; mimeType: string }> {
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetchWithTimeout(
    `${supabaseUrl}/storage/v1/object/${bucketName}/${encoded}`,
    {
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        Accept: "image/jpeg,image/png,image/webp",
      },
    },
    8_000,
  );
  if (!response.ok) {
    throw new EdgeError(
      response.status === 404 ? 404 : 502,
      "storage_download_failed",
      "Stored image could not be read",
    );
  }
  const advertised = Number(response.headers.get("content-length") ?? 0);
  if (!Number.isFinite(advertised) || advertised < 0 || advertised > maxBytes) {
    throw new EdgeError(413, "image_too_large", "Stored image is too large");
  }
  const mimeType = (response.headers.get("content-type") ?? "")
    .split(";", 1)[0]
    .trim()
    .toLowerCase();
  if (!["image/jpeg", "image/png", "image/webp"].includes(mimeType)) {
    throw new EdgeError(
      415,
      "invalid_image_type",
      "Stored image type is invalid",
    );
  }
  const bytes = await readLimitedBody(response.body, maxBytes);
  return { bytes, mimeType };
}

async function sameStoredObject(
  input: {
    supabaseUrl: string;
    serviceRoleKey: string;
    path: string;
    maxBytes: number;
  },
  expectedHash: string,
): Promise<boolean> {
  try {
    const existing = await downloadStorageObject(input);
    return await sha256BytesHex(existing.bytes) === expectedHash;
  } catch {
    return false;
  }
}

function assertPng(bytes: Uint8Array): void {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (
    bytes.length < signature.length ||
    signature.some((byte, index) => bytes[index] !== byte)
  ) {
    throw new EdgeError(
      502,
      "invalid_analyzer_response",
      "Background removal response is not a PNG",
    );
  }
}

function extensionForMime(mimeType: string): string {
  if (mimeType === "image/jpeg") return "jpg";
  if (mimeType === "image/png") return "png";
  if (mimeType === "image/webp") return "webp";
  throw new EdgeError(415, "invalid_image_type", "Image type is invalid");
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
