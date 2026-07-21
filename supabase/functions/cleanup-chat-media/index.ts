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
  isMissingChatMembersRelation,
  validateOwnedChatMediaPath,
} from "../_shared/chat_media_security.ts";

const chatMediaBucket = "chat-media";
const requestBodyLimit = 8 * 1024;

Deno.serve(async (request) => {
  const requestId = crypto.randomUUID();
  let cors: Record<string, string> = {};
  try {
    cors = strictCorsHeaders(request, "CHAT_MEDIA_ALLOWED_WEB_ORIGINS");
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      throw new EdgeError(405, "method_not_allowed", "Use POST");
    }

    const accessToken = bearerToken(request);
    const body = await readJsonObject(request, requestBodyLimit);
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    const { data: authData, error: authError } = await serviceClient.auth
      .getUser(accessToken);
    if (authError || !authData.user) {
      throw new EdgeError(401, "invalid_session", "Authentication required");
    }

    const ownedPath = validateOwnedChatMediaPath(
      body.thread_id,
      body.storage_path,
      authData.user.id,
    );
    const membershipSource = await assertThreadMembership(
      serviceClient,
      ownedPath.threadId,
      ownedPath.ownerId,
    );
    await assertMediaIsUnreferenced(
      serviceClient,
      ownedPath.threadId,
      ownedPath.storagePath,
    );

    // Storage.remove is idempotent for an absent key. The response deliberately
    // does not expose whether the object existed; callers only need to know that
    // no referenced object was deleted and the cleanup request is complete.
    const { error: removeError } = await serviceClient.storage
      .from(chatMediaBucket)
      .remove([ownedPath.storagePath]);
    if (removeError) {
      throw new EdgeError(
        503,
        "storage_cleanup_failed",
        "Chat media could not be cleaned up",
      );
    }

    return jsonResponse(
      {
        cleaned: true,
        membership_source: membershipSource,
        request_id: requestId,
      },
      200,
      cors,
    );
  } catch (error) {
    return errorResponse(error, requestId, cors);
  }
});

async function assertThreadMembership(
  serviceClient: SupabaseClient<any, "public", any>,
  threadId: string,
  userId: string,
): Promise<"canonical" | "legacy"> {
  const { data: canonicalMember, error: canonicalError } = await serviceClient
    .from("chat_thread_members")
    .select("thread_id,user_id,left_at")
    .eq("thread_id", threadId)
    .eq("user_id", userId)
    .maybeSingle();

  if (!canonicalError) {
    if (!canonicalMember || canonicalMember.left_at !== null) {
      throw new EdgeError(
        403,
        "thread_membership_required",
        "Active thread membership is required",
      );
    }
    return "canonical";
  }
  if (!isMissingChatMembersRelation(canonicalError)) {
    throw new EdgeError(
      503,
      "membership_lookup_failed",
      "Thread membership could not be verified",
    );
  }

  // Compatibility is fail-closed: legacy member_ids are consulted only when
  // the canonical relation itself is absent, never when it exists but denies
  // access or has an incompatible schema.
  const { data: thread, error: legacyError } = await serviceClient
    .from("message_threads")
    .select("id,buyer_id,seller_id,member_ids")
    .eq("id", threadId)
    .maybeSingle();
  if (legacyError) {
    throw new EdgeError(
      503,
      "membership_lookup_failed",
      "Thread membership could not be verified",
    );
  }
  if (!thread) {
    throw new EdgeError(404, "thread_not_found", "Message thread not found");
  }

  const memberIds = new Set<string>(
    [
      ...(Array.isArray(thread.member_ids) ? thread.member_ids : []),
      thread.buyer_id,
      thread.seller_id,
    ].filter((value): value is string => typeof value === "string"),
  );
  if (!memberIds.has(userId)) {
    throw new EdgeError(
      403,
      "thread_membership_required",
      "Active thread membership is required",
    );
  }
  return "legacy";
}

async function assertMediaIsUnreferenced(
  serviceClient: SupabaseClient<any, "public", any>,
  threadId: string,
  storagePath: string,
): Promise<void> {
  const { data: references, error } = await serviceClient
    .from("chat_messages")
    .select("id")
    .eq("thread_id", threadId)
    .contains("attachment", {
      bucket: chatMediaBucket,
      storage_path: storagePath,
    })
    .limit(1);
  if (error) {
    throw new EdgeError(
      503,
      "message_reference_lookup_failed",
      "Chat media references could not be verified",
    );
  }
  if ((references ?? []).length > 0) {
    throw new EdgeError(
      409,
      "chat_media_is_referenced",
      "Referenced chat media cannot be removed",
    );
  }
}
