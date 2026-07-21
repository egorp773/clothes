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
const publishedBucket = "product-images";
const maxListingImages = 8;
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

type PreparedPublication = {
  publication_id: string;
  draft_prefix: string;
  required_final_prefix: string;
};

type FinalMedia = {
  draft_path: string;
  final_path: string;
  content_hash: string;
  mime_type: string;
  position: number;
};

Deno.serve(async (request) => {
  const requestId = crypto.randomUUID();
  let cors: Record<string, string> = {};
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

    const body = await readJsonObject(request, 16 * 1024);
    const listingId = validateUuid(body.listing_id, "listing_id");
    const confirmationVersion = String(body.confirmation_version ?? "");
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(confirmationVersion)) {
      throw new EdgeError(
        400,
        "invalid_confirmation_version",
        "A valid confirmation_version is required",
      );
    }
    const confirmations = validateConfirmations(body.confirmations);
    const metadata = requestMetadata(request);
    const prepared = await preparePublication(admin, {
      userId: authData.user.id,
      listingId,
      confirmationVersion,
      confirmations,
      ip: metadata.ip,
      userAgent: metadata.userAgent,
    });

    return await promoteAndFinalize({
      admin,
      supabaseUrl,
      serviceRoleKey,
      userId: authData.user.id,
      listingId,
      prepared,
      requestId,
      cors,
    });
  } catch (error) {
    return errorResponse(error, requestId, cors);
  }
});

async function promoteAndFinalize({
  admin,
  supabaseUrl,
  serviceRoleKey,
  userId,
  listingId,
  prepared,
  requestId,
  cors,
}: {
  admin: SupabaseClient;
  supabaseUrl: string;
  serviceRoleKey: string;
  userId: string;
  listingId: string;
  prepared: PreparedPublication;
  requestId: string;
  cors: Record<string, string>;
}): Promise<Response> {
  const canonicalPrefix = `${userId}/${listingId}`;
  const draftPrefix = normalizeStoragePrefix(prepared.draft_prefix);
  const finalPrefix = normalizeStoragePrefix(prepared.required_final_prefix);
  if (draftPrefix !== canonicalPrefix || finalPrefix !== canonicalPrefix) {
    await abortPublication(
      admin,
      userId,
      listingId,
      prepared.publication_id,
      "invalid_storage_prefix",
    );
    throw new EdgeError(
      500,
      "invalid_publication_contract",
      "Publication storage contract is invalid",
    );
  }

  const { data: draftObjects, error: listError } = await admin.storage
    .from(draftBucket)
    .list(draftPrefix, {
      limit: maxListingImages + 1,
      offset: 0,
      sortBy: { column: "name", order: "asc" },
    });
  if (listError) {
    await abortPublication(
      admin,
      userId,
      listingId,
      prepared.publication_id,
      "draft_inventory_failed",
    );
    throw new EdgeError(
      503,
      "draft_inventory_failed",
      "Draft images could not be inventoried",
    );
  }
  const files = (draftObjects ?? []).filter((object) =>
    object.name && object.name !== ".emptyFolderPlaceholder"
  );
  if (files.length === 0 || files.length > maxListingImages) {
    await abortPublication(
      admin,
      userId,
      listingId,
      prepared.publication_id,
      "invalid_image_count",
    );
    throw new EdgeError(
      409,
      "invalid_image_count",
      `A listing must contain 1..${maxListingImages} draft images`,
    );
  }

  const createdFinalPaths: string[] = [];
  const finalMedia: FinalMedia[] = [];
  let finalizeAttempted = false;
  try {
    for (let position = 0; position < files.length; position++) {
      const fileName = validateDraftFileName(files[position].name);
      const draftPath = `${draftPrefix}/${fileName}`;
      const downloaded = await downloadStorageObject({
        supabaseUrl,
        serviceRoleKey,
        bucket: draftBucket,
        path: draftPath,
      });
      const contentHash = await sha256BytesHex(downloaded.bytes);
      const extension = extensionForMime(downloaded.mimeType, downloaded.bytes);
      const finalPath = `${finalPrefix}/${String(position).padStart(2, "0")}-` +
        `${contentHash.slice(0, 24)}.${extension}`;
      const created = await uploadIdempotently(
        admin,
        finalPath,
        downloaded.bytes,
        downloaded.mimeType,
        contentHash,
        { supabaseUrl, serviceRoleKey },
      );
      if (created) createdFinalPaths.push(finalPath);
      finalMedia.push({
        draft_path: draftPath,
        final_path: finalPath,
        content_hash: contentHash,
        mime_type: downloaded.mimeType,
        position,
      });
    }

    finalizeAttempted = true;
    const finalized = await finalizePublication(
      admin,
      userId,
      listingId,
      prepared.publication_id,
      finalMedia,
    );
    const finalState = normalizeRpcObject(finalized);
    const status = String(finalState.status ?? "unknown");
    const published = finalState.published === true || status === "published";
    const heldForReview = finalState.held_for_review === true ||
      ["held_for_review", "pending_moderation", "review_required"].includes(
        status,
      );
    const { error: draftRemovalError } = await admin.storage
      .from(draftBucket)
      .remove(finalMedia.map((item) => item.draft_path));
    if (draftRemovalError) {
      console.warn(
        `[publish-listing:${requestId}] published but draft cleanup failed`,
        draftRemovalError,
      );
    }
    return jsonResponse(
      {
        published,
        status,
        held_for_review: heldForReview,
        listing_id: listingId,
        publication_id: prepared.publication_id,
        media_count: finalMedia.length,
        result: finalized,
        draft_cleanup_pending: Boolean(draftRemovalError),
        request_id: requestId,
      },
      published ? 200 : 202,
      cors,
    );
  } catch (error) {
    const reason = error instanceof EdgeError
      ? error.code
      : "publication_failed";
    const aborted = await abortPublication(
      admin,
      userId,
      listingId,
      prepared.publication_id,
      reason,
    );
    // Before finalize, created objects cannot be referenced by a public
    // listing. After a potentially ambiguous finalize response, delete only
    // when the authoritative abort RPC confirms that publication was aborted.
    if (!finalizeAttempted || aborted) {
      await cleanupFinalObjects(admin, createdFinalPaths);
    } else {
      console.error(
        `[publish-listing:${requestId}] publication outcome is ambiguous; ` +
          "leaving private objects for reconciliation",
      );
    }
    throw error;
  }
}

async function preparePublication(
  admin: SupabaseClient,
  input: {
    userId: string;
    listingId: string;
    confirmationVersion: string;
    confirmations: Record<string, true>;
    ip: string | null;
    userAgent: string;
  },
): Promise<PreparedPublication> {
  const { data, error } = await admin.rpc("prepare_listing_publication", {
    p_user_id: input.userId,
    p_listing_id: input.listingId,
    p_confirmation_version: input.confirmationVersion,
    p_confirmations: input.confirmations,
    p_ip: input.ip,
    p_user_agent: input.userAgent,
  });
  if (error) throw mapDatabaseError(error, "listing_not_publishable");
  const value = normalizeRpcObject(data);
  if (
    !value.publication_id ||
    !value.draft_prefix ||
    !value.required_final_prefix
  ) {
    throw new EdgeError(
      500,
      "invalid_publication_contract",
      "Publication preparation returned an invalid contract",
    );
  }
  return {
    publication_id: validateUuid(value.publication_id, "publication_id"),
    draft_prefix: String(value.draft_prefix),
    required_final_prefix: String(value.required_final_prefix),
  };
}

async function finalizePublication(
  admin: SupabaseClient,
  userId: string,
  listingId: string,
  publicationId: string,
  finalMedia: FinalMedia[],
): Promise<unknown> {
  let lastError: { code?: string; message?: string } | null = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    const { data, error } = await admin.rpc("publish_listing_authoritatively", {
      p_user_id: userId,
      p_listing_id: listingId,
      p_publication_id: publicationId,
      p_final_media: finalMedia,
    });
    if (!error) return data;
    lastError = error;
    const { data: recovered } = await admin
      .from("listing_publication_attempts")
      .select("status,risk_result")
      .eq("id", publicationId)
      .eq("listing_id", listingId)
      .eq("user_id", userId)
      .maybeSingle();
    if (recovered?.status === "published" || recovered?.status === "held") {
      const published = recovered.status === "published";
      return {
        listing_id: listingId,
        publication_id: publicationId,
        published,
        held_for_review: !published,
        status: published ? "published" : "ready",
        risk: recovered.risk_result ?? {},
        recovered_after_ambiguous_response: true,
      };
    }
  }
  throw mapDatabaseError(lastError ?? {}, "publication_finalize_failed");
}

async function abortPublication(
  admin: SupabaseClient,
  userId: string,
  listingId: string,
  publicationId: string,
  reason: string,
): Promise<boolean> {
  const { data, error } = await admin.rpc("abort_listing_publication", {
    p_user_id: userId,
    p_listing_id: listingId,
    p_publication_id: publicationId,
    p_reason: reason.slice(0, 200),
  });
  if (error) {
    console.error("Could not abort listing publication", error);
    return false;
  }
  const value = normalizeRpcObject(data);
  return value.aborted === true || value.status === "aborted";
}

async function downloadStorageObject({
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
      "A draft image could not be read",
    );
  }
  const advertised = Number(response.headers.get("content-length") ?? 0);
  if (
    !Number.isFinite(advertised) || advertised < 0 || advertised > maxImageBytes
  ) {
    throw new EdgeError(413, "image_too_large", "Draft image is too large");
  }
  const mimeType = (response.headers.get("content-type") ?? "")
    .split(";", 1)[0]
    .trim()
    .toLowerCase();
  if (!["image/jpeg", "image/png", "image/webp"].includes(mimeType)) {
    throw new EdgeError(
      415,
      "invalid_image_type",
      "Draft image type is not supported",
    );
  }
  const bytes = await readLimitedBody(response.body, maxImageBytes);
  if (bytes.byteLength === 0) {
    throw new EdgeError(422, "empty_image", "Draft image is empty");
  }
  extensionForMime(mimeType, bytes);
  return { bytes, mimeType };
}

async function uploadIdempotently(
  admin: SupabaseClient,
  finalPath: string,
  bytes: Uint8Array,
  mimeType: string,
  expectedHash: string,
  storage: { supabaseUrl: string; serviceRoleKey: string },
): Promise<boolean> {
  const { error } = await admin.storage
    .from(publishedBucket)
    .upload(finalPath, bytes, {
      contentType: mimeType,
      cacheControl: "31536000",
      upsert: false,
    });
  if (!error) return true;
  const existing = await downloadStorageObject({
    ...storage,
    bucket: publishedBucket,
    path: finalPath,
  }).catch(() => null);
  if (
    existing &&
    existing.mimeType === mimeType &&
    await sha256BytesHex(existing.bytes) === expectedHash
  ) {
    return false;
  }
  throw new EdgeError(
    503,
    "final_media_upload_failed",
    "Published image could not be stored",
  );
}

async function cleanupFinalObjects(
  admin: SupabaseClient,
  paths: string[],
): Promise<void> {
  if (paths.length === 0) return;
  const { error } = await admin.storage.from(publishedBucket).remove(paths);
  if (error) console.error("Could not roll back published media", error);
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
  return Object.fromEntries(
    confirmationKeys.map((key) => [key, true]),
  ) as Record<string, true>;
}

function validateUuid(value: unknown, field: string): string {
  const uuid = String(value ?? "").toLowerCase();
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(
        uuid,
      )
  ) {
    throw new EdgeError(400, `invalid_${field}`, `${field} must be a UUID`);
  }
  return uuid;
}

function normalizeStoragePrefix(value: string): string {
  const normalized = String(value ?? "").replace(/^\/+|\/+$/g, "");
  if (
    normalized.includes("..") ||
    normalized.includes("\\") ||
    !/^[0-9a-f-]+\/[0-9a-f-]+$/i.test(normalized)
  ) {
    throw new EdgeError(
      500,
      "invalid_publication_contract",
      "Publication storage prefix is invalid",
    );
  }
  return normalized.toLowerCase();
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
      "Draft image filename is invalid",
    );
  }
  return fileName;
}

function extensionForMime(mimeType: string, bytes: Uint8Array): string {
  if (
    mimeType === "image/jpeg" &&
    bytes.length >= 3 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  ) {
    return "jpg";
  }
  if (
    mimeType === "image/png" &&
    bytes.length >= 8 &&
    [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every(
      (byte, index) => bytes[index] === byte,
    )
  ) {
    return "png";
  }
  if (
    mimeType === "image/webp" &&
    bytes.length >= 12 &&
    new TextDecoder().decode(bytes.slice(0, 4)) === "RIFF" &&
    new TextDecoder().decode(bytes.slice(8, 12)) === "WEBP"
  ) {
    return "webp";
  }
  throw new EdgeError(
    422,
    "image_signature_mismatch",
    "Draft image bytes do not match the declared MIME type",
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
    .replace(/^.*?:\s*/, "")
    .trim();
  if (error.code === "42501") {
    return new EdgeError(403, message || fallbackCode, message);
  }
  if (error.code === "23514" || error.code === "55000") {
    return new EdgeError(409, message || fallbackCode, message);
  }
  if (error.code === "P0002") {
    return new EdgeError(404, message || "listing_not_found", message);
  }
  console.error("Listing publication RPC failed", error);
  return new EdgeError(
    503,
    fallbackCode,
    "Listing publication is temporarily unavailable",
  );
}
