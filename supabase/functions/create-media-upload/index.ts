import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.49.8";

import {
  bearerToken,
  EdgeError,
  errorResponse,
  jsonResponse,
  readJsonObject,
  requiredEnv,
  strictCorsHeaders,
} from "../_shared/edge.ts";
import {
  type MediaUploadTarget,
  parseMediaUploadTarget,
} from "../_shared/media_upload_security.ts";

Deno.serve(async (request) => {
  const requestId = crypto.randomUUID();
  let cors: Record<string, string> = {};
  try {
    cors = strictCorsHeaders(request);
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      throw new EdgeError(405, "method_not_allowed", "Use POST");
    }

    const admin = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false,
        },
      },
    );
    const { data: authData, error: authError } = await admin.auth.getUser(
      bearerToken(request),
    );
    if (authError || !authData.user) {
      throw new EdgeError(401, "invalid_session", "Authentication required");
    }

    const userId = authData.user.id.toLowerCase();
    await requireActiveDurableUser(admin, userId);
    const body = await readJsonObject(request, 8 * 1024);
    const action = parseAction(body.action);
    const target = parseMediaUploadTarget(body, userId);
    await requireResourceOwnership(admin, userId, target);

    if (action === "claim") {
      return await claimUploadedObject(
        admin,
        userId,
        target,
        requestId,
        cors,
      );
    }

    await reserveUpload(admin, userId, target, requestId);
    const { data: signed, error: signingError } = await admin.storage
      .from(target.bucket)
      .createSignedUploadUrl(target.objectPath);
    if (signingError || !signed?.token || signed.path !== target.objectPath) {
      console.error(`[create-media-upload:${requestId}] signing failed`, {
        bucket: target.bucket,
        code: signingError?.name,
      });
      throw new EdgeError(
        503,
        "upload_signing_failed",
        "A secure media upload could not be prepared",
      );
    }

    return jsonResponse(
      {
        bucket: target.bucket,
        object_path: target.objectPath,
        content_type: target.contentType,
        size_bytes: target.sizeBytes,
        token: signed.token,
        request_id: requestId,
      },
      200,
      cors,
    );
  } catch (error) {
    return errorResponse(error, requestId, cors);
  }
});

type MediaUploadAction = "prepare" | "claim";

function parseAction(value: unknown): MediaUploadAction {
  if (value === "prepare" || value === "claim") return value;
  throw new EdgeError(
    400,
    "invalid_action",
    "action must be prepare or claim",
  );
}

async function reserveUpload(
  admin: SupabaseClient,
  userId: string,
  target: MediaUploadTarget,
  requestId: string,
): Promise<void> {
  const { data, error } = await admin.rpc("reserve_signed_media_upload", {
    p_user_id: userId,
    p_bucket: target.bucket,
    p_storage_path: target.objectPath,
    p_resource_id: target.resourceId,
    p_content_type: target.contentType,
    p_size_bytes: target.sizeBytes,
  });
  if (error) {
    console.error(`[create-media-upload:${requestId}] reservation failed`, {
      bucket: target.bucket,
      code: error.code,
    });
    if (error.code === "42501") throw uploadForbidden();
    if (error.code === "54000") {
      throw new EdgeError(
        429,
        "media_upload_limit_reached",
        "Too many media uploads were prepared for this account or resource",
      );
    }
    if (["22023", "23505"].includes(error.code ?? "")) {
      throw new EdgeError(
        409,
        "media_upload_reservation_rejected",
        "The secure upload reservation could not be created",
      );
    }
    throw new EdgeError(
      503,
      "media_upload_reservation_failed",
      "The secure upload reservation is temporarily unavailable",
    );
  }
  const result = normalizeRpcObject(data);
  if (result.reserved !== true) {
    throw new EdgeError(
      503,
      "invalid_media_upload_reservation",
      "The secure upload reservation is temporarily unavailable",
    );
  }
}

async function claimUploadedObject(
  admin: SupabaseClient,
  userId: string,
  target: MediaUploadTarget,
  requestId: string,
  cors: Record<string, string>,
): Promise<Response> {
  const { data, error } = await admin.rpc("claim_signed_media_upload", {
    p_user_id: userId,
    p_bucket: target.bucket,
    p_storage_path: target.objectPath,
    p_content_type: target.contentType,
    p_size_bytes: target.sizeBytes,
  });
  if (error) {
    console.error(`[create-media-upload:${requestId}] claim failed`, {
      bucket: target.bucket,
      code: error.code,
    });
    if (error.code === "42501") throw uploadForbidden();
    if (["22023", "23514", "P0002"].includes(error.code ?? "")) {
      throw new EdgeError(
        409,
        "media_claim_rejected",
        "The uploaded object did not match its secure upload grant",
      );
    }
    throw new EdgeError(
      503,
      "media_claim_failed",
      "The uploaded object could not be finalized",
    );
  }
  const result = normalizeRpcObject(data);
  if (result.claimed !== true) {
    throw new EdgeError(
      503,
      "invalid_media_claim_result",
      "The uploaded object could not be finalized",
    );
  }
  return jsonResponse(
    {
      claimed: true,
      already_claimed: result.already_claimed === true,
      bucket: target.bucket,
      object_path: target.objectPath,
      content_type: target.contentType,
      size_bytes: target.sizeBytes,
      request_id: requestId,
    },
    200,
    cors,
  );
}

async function requireActiveDurableUser(
  admin: SupabaseClient,
  userId: string,
): Promise<void> {
  const { data, error } = await admin
    .from("users")
    .select("id")
    .eq("id", userId)
    .eq("auth_user_id", userId)
    .eq("account_status", "active")
    .maybeSingle();
  if (error) {
    console.error("Active durable user lookup failed", { code: error.code });
    throw temporarilyUnavailable();
  }
  if (!data) {
    throw new EdgeError(
      403,
      "active_account_required",
      "An active account is required",
    );
  }
}

async function requireResourceOwnership(
  admin: SupabaseClient,
  userId: string,
  target: MediaUploadTarget,
): Promise<void> {
  switch (target.bucket) {
    case "profile-images": {
      // The durable active user owns this canonical uid/avatar namespace.
      // A profile row may legitimately be created only after its first avatar.
      return;
    }
    case "chat-media": {
      const { data, error } = await admin
        .from("chat_thread_members")
        .select("thread_id")
        .eq("thread_id", target.resourceId)
        .eq("user_id", userId)
        .is("left_at", null)
        .maybeSingle();
      return requireOwnedRow(data, error);
    }
    case "listing-drafts": {
      const { data, error } = await admin
        .from("products")
        .select("id")
        .eq("id", target.resourceId)
        .eq("seller_id", userId)
        .in("status", [
          "draft",
          "processing",
          "ready",
          "published",
          "pending_moderation",
        ])
        .maybeSingle();
      return requireOwnedRow(data, error);
    }
    case "outfit-images": {
      const { data, error } = await admin
        .from("outfits")
        .select("id")
        .eq("id", target.resourceId)
        .eq("owner_id", userId)
        .eq("publication_status", "draft")
        .maybeSingle();
      return requireOwnedRow(data, error);
    }
    case "accessory-images": {
      const { data, error } = await admin
        .from("outfit_accessories")
        .select("id")
        .eq("id", target.resourceId)
        .eq("owner_id", userId)
        .eq("scope", "private")
        .eq("media_status", "uploading")
        .maybeSingle();
      return requireOwnedRow(data, error);
    }
    case "dispute-evidence":
      return requireDisputeOwnership(admin, userId, target.resourceId);
  }
}

async function requireDisputeOwnership(
  admin: SupabaseClient,
  userId: string,
  disputeId: string,
): Promise<void> {
  const { data: dispute, error: disputeError } = await admin
    .from("disputes")
    .select("order_id")
    .eq("id", disputeId)
    .in("status", ["open", "under_review"])
    .maybeSingle();
  if (disputeError) {
    console.error("Dispute upload lookup failed", { code: disputeError.code });
    throw temporarilyUnavailable();
  }
  if (!dispute?.order_id) throw uploadForbidden();

  const { data: order, error: orderError } = await admin
    .from("orders")
    .select("id")
    .eq("id", dispute.order_id)
    .or(`buyer_id.eq.${userId},seller_id.eq.${userId}`)
    .maybeSingle();
  return requireOwnedRow(order, orderError);
}

function requireOwnedRow(
  data: unknown,
  error: { code?: string } | null,
): void {
  if (error) {
    console.error("Media ownership lookup failed", { code: error.code });
    throw temporarilyUnavailable();
  }
  if (!data) throw uploadForbidden();
}

function uploadForbidden(): EdgeError {
  return new EdgeError(
    403,
    "media_upload_forbidden",
    "Media upload is not allowed for this resource",
  );
}

function temporarilyUnavailable(): EdgeError {
  return new EdgeError(
    503,
    "media_authorization_unavailable",
    "Media upload authorization is temporarily unavailable",
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
