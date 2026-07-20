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
  requestMetadata,
  requiredEnv,
  sha256BytesHex,
  strictCorsHeaders,
} from "../_shared/edge.ts";

const draftBucket = "listing-drafts";
const finalBucket = "product-images";
const maxImages = 8;
const maxImageBytes = 15 * 1024 * 1024;
const confirmationKeys = [
  "owns_item",
  "has_right_to_sell",
  "has_item_in_possession",
  "owns_photos",
  "description_is_accurate",
  "item_is_authentic",
  "item_is_not_prohibited",
] as const;

type FinalMedia = {
  draft_path: string;
  final_path: string;
  content_hash: string;
  mime_type: string;
  position: number;
};

Deno.serve(async (request) => {
  const edgeRequestId = crypto.randomUUID();
  let cors: Record<string, string> = {};
  const createdFinalPaths: string[] = [];
  try {
    cors = strictCorsHeaders(request, "LISTING_ALLOWED_WEB_ORIGINS");
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      throw new EdgeError(405, "method_not_allowed", "Use POST");
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

    const body = await readJsonObject(request, 32 * 1024);
    const listingId = validateUuid(body.listing_id, "listing_id");
    const idempotencyKey = validateUuid(
      body.idempotency_key,
      "idempotency_key",
    );
    const changes = validateChanges(body.changes);
    const confirmationVersion = String(body.confirmation_version ?? "");
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(confirmationVersion)) {
      throw new EdgeError(
        400,
        "invalid_confirmation_version",
        "A valid confirmation_version is required",
      );
    }
    const confirmations = validateConfirmations(body.confirmations);
    if (typeof body.replace_photos !== "boolean") {
      throw new EdgeError(
        400,
        "replace_photos_required",
        "replace_photos must be a boolean",
      );
    }

    const prefix = `${authData.user.id}/${listingId}`;
    let finalMedia: FinalMedia[] | null = null;
    if (body.replace_photos) {
      finalMedia = await promoteDraftMedia({
        admin,
        supabaseUrl,
        serviceRoleKey,
        prefix,
        createdFinalPaths,
      });
    }

    const metadata = requestMetadata(request);
    const { data, error } = await admin.rpc(
      "submit_listing_edit_authoritatively",
      {
        p_user_id: authData.user.id,
        p_listing_id: listingId,
        p_request_id: idempotencyKey,
        p_payload: changes,
        p_confirmation_version: confirmationVersion,
        p_confirmations: confirmations,
        p_final_media: finalMedia,
        p_ip: metadata.ip,
        p_user_agent: metadata.userAgent,
      },
    );
    let result = normalizeRpcObject(data);
    if (error) {
      // A transport failure after COMMIT must not cause referenced immutable
      // objects to be deleted. Recover via the idempotency ledger first.
      const { data: recovered } = await admin.from("listing_edit_revisions")
        .select("id,revision_number,changed_fields")
        .eq("request_id", idempotencyKey)
        .eq("listing_id", listingId)
        .eq("editor_id", authData.user.id)
        .maybeSingle();
      if (!recovered) throw mapDatabaseError(error, "listing_edit_failed");
      result = {
        edited: true,
        replayed: true,
        revision_id: recovered.id,
        revision_number: recovered.revision_number,
        changed_fields: recovered.changed_fields ?? [],
        status: "pending_moderation",
      };
    }

    if (result.edited !== true && createdFinalPaths.length > 0) {
      await admin.storage.from(finalBucket).remove(createdFinalPaths);
      createdFinalPaths.length = 0;
    }

    // Draft inputs and superseded final objects are deliberately retained at
    // this boundary. They are evidence for the immutable before/after revision
    // and also make an idempotent network retry possible. A retention worker
    // may purge them only after the moderation-audit policy is approved.

    const { data: listing, error: listingError } = await admin
      .from("products")
      .select("*")
      .eq("id", listingId)
      .eq("seller_id", authData.user.id)
      .single();
    if (listingError) {
      console.warn(
        `[edit-listing:${edgeRequestId}] snapshot read failed`,
        listingError,
      );
    }
    return jsonResponse(
      {
        edited: result.edited === true,
        status: String(result.status ?? listing?.status ?? "unknown"),
        listing_id: listingId,
        revision_id: result.revision_id ?? null,
        revision_number: result.revision_number ?? null,
        changed_fields: result.changed_fields ?? [],
        listing: listing ?? null,
        request_id: edgeRequestId,
      },
      result.edited === true ? 202 : 200,
      cors,
    );
  } catch (error) {
    if (createdFinalPaths.length > 0) {
      // The authoritative SQL command is atomic. Objects created before a
      // rejected command cannot be referenced and are safe to roll back.
      const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
      const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
      if (supabaseUrl && serviceRoleKey) {
        const cleanupClient = createClient(supabaseUrl, serviceRoleKey, {
          auth: { persistSession: false, autoRefreshToken: false },
        });
        // The RPC may have committed even if its HTTP response was lost. Only
        // remove objects after proving that no durable product-media row
        // references them; on an inconclusive lookup we deliberately retain
        // the objects for the retention worker.
        const { data: referencedRows, error: referenceError } =
          await cleanupClient
            .from("product_images")
            .select("storage_path")
            .eq("storage_bucket", finalBucket)
            .in("storage_path", createdFinalPaths);
        if (!referenceError) {
          const referenced = new Set(
            (referencedRows ?? []).map((row) => String(row.storage_path ?? "")),
          );
          const unreferenced = createdFinalPaths.filter((path) =>
            !referenced.has(path)
          );
          if (unreferenced.length > 0) {
            await cleanupClient.storage.from(finalBucket)
              .remove(unreferenced).catch(() => undefined);
          }
        }
      }
    }
    return errorResponse(error, edgeRequestId, cors);
  }
});

async function promoteDraftMedia({
  admin,
  supabaseUrl,
  serviceRoleKey,
  prefix,
  createdFinalPaths,
}: {
  admin: SupabaseClient;
  supabaseUrl: string;
  serviceRoleKey: string;
  prefix: string;
  createdFinalPaths: string[];
}): Promise<FinalMedia[]> {
  const { data: objects, error } = await admin.storage.from(draftBucket).list(
    prefix,
    { limit: maxImages + 1, sortBy: { column: "name", order: "asc" } },
  );
  if (error) {
    throw new EdgeError(
      503,
      "draft_inventory_failed",
      "Replacement photos could not be inventoried",
    );
  }
  const files = (objects ?? []).filter((item) =>
    item.name && item.name !== ".emptyFolderPlaceholder"
  );
  if (files.length < 1 || files.length > maxImages) {
    throw new EdgeError(
      409,
      "invalid_image_count",
      `A listing edit must contain 1..${maxImages} replacement photos`,
    );
  }

  const media: FinalMedia[] = [];
  for (let position = 0; position < files.length; position++) {
    const fileName = validateDraftFileName(files[position].name);
    const draftPath = `${prefix}/${fileName}`;
    const downloaded = await downloadObject({
      supabaseUrl,
      serviceRoleKey,
      bucket: draftBucket,
      path: draftPath,
    });
    const contentHash = await sha256BytesHex(downloaded.bytes);
    const extension = extensionForMime(downloaded.mimeType, downloaded.bytes);
    const finalPath = `${prefix}/${String(position).padStart(2, "0")}-` +
      `${contentHash.slice(0, 24)}.${extension}`;
    const created = await uploadIdempotently({
      admin,
      supabaseUrl,
      serviceRoleKey,
      finalPath,
      bytes: downloaded.bytes,
      mimeType: downloaded.mimeType,
      expectedHash: contentHash,
    });
    if (created) createdFinalPaths.push(finalPath);
    media.push({
      draft_path: draftPath,
      final_path: finalPath,
      content_hash: contentHash,
      mime_type: downloaded.mimeType,
      position,
    });
  }
  return media;
}

async function downloadObject({
  supabaseUrl,
  serviceRoleKey,
  bucket,
  path,
}: {
  supabaseUrl: string;
  serviceRoleKey: string;
  bucket: string;
  path: string;
}): Promise<{ bytes: Uint8Array; mimeType: string }> {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetchWithTimeout(
    `${supabaseUrl}/storage/v1/object/${bucket}/${encodedPath}`,
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
      response.status === 404 ? 409 : 502,
      "draft_download_failed",
      "A replacement photo could not be read",
    );
  }
  const advertised = Number(response.headers.get("content-length") ?? 0);
  if (!Number.isFinite(advertised) || advertised > maxImageBytes) {
    throw new EdgeError(413, "image_too_large", "A photo is too large");
  }
  const mimeType = (response.headers.get("content-type") ?? "")
    .split(";", 1)[0].trim().toLowerCase();
  if (!["image/jpeg", "image/png", "image/webp"].includes(mimeType)) {
    throw new EdgeError(415, "invalid_image_type", "Unsupported image type");
  }
  const bytes = await readLimitedBody(response.body, maxImageBytes);
  if (bytes.byteLength === 0) {
    throw new EdgeError(422, "empty_image", "A replacement photo is empty");
  }
  extensionForMime(mimeType, bytes);
  return { bytes, mimeType };
}

async function uploadIdempotently({
  admin,
  supabaseUrl,
  serviceRoleKey,
  finalPath,
  bytes,
  mimeType,
  expectedHash,
}: {
  admin: SupabaseClient;
  supabaseUrl: string;
  serviceRoleKey: string;
  finalPath: string;
  bytes: Uint8Array;
  mimeType: string;
  expectedHash: string;
}): Promise<boolean> {
  const { error } = await admin.storage.from(finalBucket).upload(
    finalPath,
    bytes,
    { contentType: mimeType, cacheControl: "31536000", upsert: false },
  );
  if (!error) return true;
  const existing = await downloadObject({
    supabaseUrl,
    serviceRoleKey,
    bucket: finalBucket,
    path: finalPath,
  }).catch(() => null);
  if (
    existing && existing.mimeType === mimeType &&
    await sha256BytesHex(existing.bytes) === expectedHash
  ) return false;
  throw new EdgeError(
    503,
    "final_media_upload_failed",
    "Replacement photo could not be stored",
  );
}

function validateChanges(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new EdgeError(400, "invalid_changes", "changes must be an object");
  }
  return value as Record<string, unknown>;
}

function validateConfirmations(value: unknown): Record<string, true> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new EdgeError(
      400,
      "invalid_seller_confirmations",
      "Seven seller confirmations are required",
    );
  }
  const object = value as Record<string, unknown>;
  const keys = Object.keys(object).sort();
  const expected = [...confirmationKeys].sort();
  if (
    keys.length !== expected.length ||
    keys.some((key, index) => key !== expected[index]) ||
    confirmationKeys.some((key) => object[key] !== true)
  ) {
    throw new EdgeError(
      403,
      "seller_confirmations_required",
      "Every seller declaration must be explicitly accepted",
    );
  }
  return Object.fromEntries(confirmationKeys.map((key) => [key, true])) as
    Record<string, true>;
}

function validateUuid(value: unknown, field: string): string {
  const uuid = String(value ?? "").toLowerCase();
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(uuid)
  ) {
    throw new EdgeError(400, `invalid_${field}`, `${field} must be a UUID`);
  }
  return uuid;
}

function validateDraftFileName(value: string): string {
  const fileName = String(value ?? "");
  if (
    fileName.length > 180 ||
    !/^[A-Za-z0-9][A-Za-z0-9._-]*\.(?:jpe?g|png|webp)$/i.test(fileName)
  ) {
    throw new EdgeError(
      422,
      "invalid_draft_filename",
      "Replacement photo filename is invalid",
    );
  }
  return fileName;
}

function extensionForMime(mimeType: string, bytes: Uint8Array): string {
  if (
    mimeType === "image/jpeg" && bytes.length >= 3 && bytes[0] === 0xff &&
    bytes[1] === 0xd8 && bytes[2] === 0xff
  ) return "jpg";
  if (
    mimeType === "image/png" && bytes.length >= 8 &&
    [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every(
      (byte, index) => bytes[index] === byte,
    )
  ) return "png";
  if (
    mimeType === "image/webp" && bytes.length >= 12 &&
    new TextDecoder().decode(bytes.slice(0, 4)) === "RIFF" &&
    new TextDecoder().decode(bytes.slice(8, 12)) === "WEBP"
  ) return "webp";
  throw new EdgeError(
    422,
    "image_signature_mismatch",
    "Photo bytes do not match the declared MIME type",
  );
}

function normalizeRpcObject(value: unknown): Record<string, unknown> {
  if (Array.isArray(value)) {
    return value[0] && typeof value[0] === "object"
      ? value[0] as Record<string, unknown>
      : {};
  }
  return value && typeof value === "object"
    ? value as Record<string, unknown>
    : {};
}

function mapDatabaseError(
  error: { code?: string; message?: string },
  fallbackCode: string,
): EdgeError {
  const message = String(error.message ?? fallbackCode)
    .replace(/^.*?:\s*/, "").trim();
  if (error.code === "42501") {
    return new EdgeError(403, message || fallbackCode, message);
  }
  if (
    error.code === "23514" || error.code === "55000" ||
    error.code === "23505"
  ) {
    return new EdgeError(409, message || fallbackCode, message);
  }
  if (error.code === "P0002") {
    return new EdgeError(404, message || "listing_not_found", message);
  }
  console.error("Listing edit RPC failed", error);
  return new EdgeError(
    503,
    fallbackCode,
    "Listing editing is temporarily unavailable",
  );
}
