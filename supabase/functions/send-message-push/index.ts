import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.49.8";

import {
  EdgeError,
  errorResponse,
  fetchWithTimeout,
  jsonResponse,
  readJsonObject,
  readLimitedBody,
  requiredEnv,
  safeErrorCode,
  strictCorsHeaders,
} from "../_shared/edge.ts";
import {
  parsePushClaimResponse,
  type PushClaimDecision,
  takeBoundedPushTokens,
} from "../_shared/push_security.ts";

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type NotificationSettings = {
  user_id: string;
  push_enabled: boolean | null;
  messages_enabled: boolean | null;
  sound_enabled: boolean | null;
};

type ThreadMemberState = {
  user_id: string;
  is_muted: boolean | null;
};

type ThreadMember = {
  user_id: string;
};

type PushToken = {
  user_id: string;
  token: string;
};

type FcmSendResult = {
  ok: boolean;
  invalidToken: boolean;
  error: string;
};

const maxPushRecipients = 49;
const maxPushTokensPerRecipient = 5;
const tokenLookupConcurrency = 6;
const fcmSendConcurrency = 8;

Deno.serve(async (request) => {
  const requestId = crypto.randomUUID();
  let cors: Record<string, string> = {};
  try {
    cors = strictCorsHeaders(request, "PUSH_ALLOWED_WEB_ORIGINS");
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      throw new EdgeError(405, "method_not_allowed", "Use POST");
    }

    const body = await readJsonObject(request, 8 * 1024);
    const threadId = validateIdentifier(body.thread_id, "thread_id");
    const messageId = validateIdentifier(body.message_id, "message_id");
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const anonKey = requiredEnv("SUPABASE_ANON_KEY");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const authorization = request.headers.get("Authorization") ?? "";
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
    const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
    const { data: authData, error: authError } = await userClient.auth
      .getUser();
    if (authError || !authData.user) {
      throw new EdgeError(401, "invalid_session", "Authentication required");
    }
    const senderId = authData.user.id;

    const { data: thread, error: threadError } = await userClient
      .from("message_threads")
      .select("id")
      .eq("id", threadId)
      .maybeSingle();
    if (threadError) {
      throw new EdgeError(
        503,
        "thread_lookup_failed",
        "Message thread could not be verified",
      );
    }
    if (!thread) {
      throw new EdgeError(404, "thread_not_found", "Message thread not found");
    }
    const { data: memberRows, error: memberError } = await userClient
      .from("chat_thread_members")
      .select("user_id")
      .eq("thread_id", threadId)
      .is("left_at", null);
    if (memberError) {
      throw new EdgeError(
        503,
        "thread_membership_lookup_failed",
        "Message thread membership could not be verified",
      );
    }
    const memberIds = ((memberRows ?? []) as ThreadMember[])
      .map((member) => member.user_id);
    if (!memberIds.includes(senderId)) {
      throw new EdgeError(
        403,
        "thread_membership_required",
        "Message thread membership is required",
      );
    }

    const { data: message, error: messageError } = await userClient
      .from("chat_messages")
      .select("id,sender_id,deleted_at")
      .eq("id", messageId)
      .eq("thread_id", threadId)
      .maybeSingle();
    if (messageError) {
      throw new EdgeError(
        503,
        "message_lookup_failed",
        "Message could not be verified",
      );
    }
    if (
      !message ||
      message.sender_id !== senderId ||
      message.deleted_at
    ) {
      throw new EdgeError(404, "message_not_found", "Message not found");
    }

    const pushClaim = await claimPushDelivery(
      serviceClient,
      messageId,
      senderId,
      threadId,
    );
    if (!pushClaim.attemptId) {
      return jsonResponse(
        {
          sent: 0,
          skipped: pushClaim.skipped,
          ...(pushClaim.retryAfterSeconds === null
            ? {}
            : { retry_after_seconds: pushClaim.retryAfterSeconds }),
          request_id: requestId,
        },
        200,
        cors,
      );
    }

    try {
      const result = await deliverGenericPush({
        serviceClient,
        serviceAccount: loadFirebaseServiceAccount(),
        recipientIds: [
          ...new Set(
            memberIds.filter((memberId: string) => memberId !== senderId),
          ),
        ],
        threadId,
        messageId,
      });
      await completePushDelivery(
        serviceClient,
        pushClaim.attemptId,
        result.status,
        result.error,
      );
      return jsonResponse(
        {
          sent: result.sent,
          failed: result.failed,
          total: result.total,
          invalid_tokens_removed: result.invalidTokensRemoved,
          skipped: result.skipped,
          request_id: requestId,
        },
        200,
        cors,
      );
    } catch (error) {
      await completePushDelivery(
        serviceClient,
        pushClaim.attemptId,
        "failed",
        error instanceof EdgeError ? error.code : "push_delivery_failed",
      );
      throw error;
    }
  } catch (error) {
    return errorResponse(error, requestId, cors);
  }
});

async function deliverGenericPush({
  serviceClient,
  serviceAccount,
  recipientIds,
  threadId,
  messageId,
}: {
  serviceClient: SupabaseClient<any, "public", any>;
  serviceAccount: ServiceAccount | null;
  recipientIds: string[];
  threadId: string;
  messageId: string;
}): Promise<{
  status: "sent" | "skipped" | "failed";
  sent: number;
  failed: number;
  total: number;
  invalidTokensRemoved: number;
  skipped: string | null;
  error: string;
}> {
  const uniqueRecipientIds = [...new Set(recipientIds)]
    .filter((recipientId) => isUuid(recipientId));
  if (uniqueRecipientIds.length === 0) {
    return skippedResult("empty_recipient");
  }
  if (uniqueRecipientIds.length > maxPushRecipients) {
    throw new EdgeError(
      422,
      "push_fanout_too_large",
      "Push recipient fan-out exceeds the supported limit",
    );
  }
  const [
    { data: settingsRows, error: settingsError },
    { data: memberStates, error: statesError },
  ] = await Promise.all([
    serviceClient
      .from("notification_settings")
      .select("user_id,push_enabled,messages_enabled,sound_enabled")
      .in("user_id", uniqueRecipientIds),
    serviceClient
      .from("chat_thread_member_state")
      .select("user_id,is_muted")
      .eq("thread_id", threadId)
      .in("user_id", uniqueRecipientIds),
  ]);
  if (settingsError || statesError) {
    throw new EdgeError(
      503,
      "push_preferences_unavailable",
      "Push preferences could not be loaded",
    );
  }

  const muted = new Set(
    ((memberStates ?? []) as ThreadMemberState[])
      .filter((state) => state.is_muted === true)
      .map((state) => state.user_id),
  );
  const settings = new Map(
    ((settingsRows ?? []) as NotificationSettings[])
      .map((row) => [row.user_id, row]),
  );
  const enabledRecipients = uniqueRecipientIds.filter((recipientId) => {
    const preferences = settings.get(recipientId);
    return !muted.has(recipientId) &&
      (preferences?.push_enabled ?? true) &&
      (preferences?.messages_enabled ?? true);
  });
  if (enabledRecipients.length === 0) {
    return skippedResult("push_disabled_or_thread_muted");
  }

  const tokens = await loadBoundedPushTokens(
    serviceClient,
    enabledRecipients,
  );
  if (tokens.length === 0) return skippedResult("no_tokens");
  if (!serviceAccount) {
    throw new EdgeError(
      503,
      "push_provider_unconfigured",
      "Push provider is not configured",
    );
  }

  let accessToken: string;
  try {
    accessToken = await firebaseAccessToken(serviceAccount);
  } catch {
    throw new EdgeError(
      502,
      "push_provider_unavailable",
      "Push provider is unavailable",
    );
  }
  const soundByRecipient = new Map(
    enabledRecipients.map((recipientId) => [
      recipientId,
      settings.get(recipientId)?.sound_enabled ?? true,
    ]),
  );
  const results = await mapWithConcurrency(
    tokens,
    fcmSendConcurrency,
    async (row) => {
      const result = await sendFcmMessage({
        accessToken,
        projectId: serviceAccount.project_id,
        token: row.token,
        threadId,
        messageId,
        soundEnabled: soundByRecipient.get(row.user_id) ?? true,
      }).catch((): FcmSendResult => ({
        ok: false,
        invalidToken: false,
        error: "network_error",
      }));
      let invalidTokenRemoved = false;
      if (result.invalidToken) {
        const { error } = await serviceClient
          .from("device_push_tokens")
          .delete()
          .eq("token", row.token)
          .eq("user_id", row.user_id);
        invalidTokenRemoved = !error;
      }
      return { ...result, invalidTokenRemoved };
    },
  );
  const sent = results.filter((result) => result.ok).length;
  const failed = results.length - sent;
  return {
    status: sent > 0 ? "sent" : "failed",
    sent,
    failed,
    total: results.length,
    invalidTokensRemoved:
      results.filter((result) => result.invalidTokenRemoved).length,
    skipped: null,
    error: failed > 0 ? `failed_installations:${failed}` : "",
  };
}

async function claimPushDelivery(
  serviceClient: SupabaseClient<any, "public", any>,
  messageId: string,
  senderId: string,
  threadId: string,
): Promise<PushClaimDecision> {
  const { data, error } = await serviceClient.rpc("claim_push_delivery", {
    p_message_id: messageId,
    p_sender_id: senderId,
    p_thread_id: threadId,
  });
  if (error) {
    const code = safeErrorCode(error.message);
    if (error.code === "55000" || code.includes("rate_limit")) {
      throw new EdgeError(429, "push_rate_limited", "Too many push requests");
    }
    console.error("Push delivery claim failed", {
      code: safeErrorCode(String(error.code ?? error.message)),
    });
    throw new EdgeError(
      503,
      "push_claim_failed",
      "Push delivery could not be claimed",
    );
  }
  return parsePushClaimResponse(data);
}

async function completePushDelivery(
  serviceClient: SupabaseClient<any, "public", any>,
  attemptId: string,
  status: "sent" | "skipped" | "failed",
  errorMessage: string,
): Promise<void> {
  const { error } = await serviceClient.rpc("complete_push_delivery", {
    p_attempt_id: attemptId,
    p_status: status,
    p_error: errorMessage.slice(0, 500),
  });
  if (error) {
    console.error("Push delivery completion failed", {
      code: safeErrorCode(String(error.code ?? error.message)),
    });
  }
}

async function loadBoundedPushTokens(
  serviceClient: SupabaseClient<any, "public", any>,
  recipientIds: string[],
): Promise<PushToken[]> {
  const byRecipient = await mapWithConcurrency(
    recipientIds,
    tokenLookupConcurrency,
    async (recipientId): Promise<PushToken[]> => {
      const { data, error } = await serviceClient
        .from("device_push_tokens")
        .select("user_id,token,updated_at")
        .eq("user_id", recipientId)
        .order("updated_at", { ascending: false })
        .limit(maxPushTokensPerRecipient * 3);
      if (error) {
        throw new EdgeError(
          503,
          "push_tokens_unavailable",
          "Push tokens could not be loaded",
        );
      }
      return takeBoundedPushTokens(
        recipientId,
        (data ?? []) as PushToken[],
        maxPushTokensPerRecipient,
      );
    },
  );
  return byRecipient.flat();
}

async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  mapper: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  if (items.length === 0) return [];
  const results = new Array<R>(items.length);
  let nextIndex = 0;
  const workers = Array.from(
    { length: Math.min(concurrency, items.length) },
    async () => {
      while (true) {
        const index = nextIndex++;
        if (index >= items.length) return;
        results[index] = await mapper(items[index], index);
      }
    },
  );
  await Promise.all(workers);
  return results;
}

function loadFirebaseServiceAccount(): ServiceAccount | null {
  const rawJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (rawJson) {
    try {
      const parsed = JSON.parse(rawJson) as ServiceAccount;
      if (parsed.project_id && parsed.client_email && parsed.private_key) {
        return parsed;
      }
    } catch {
      return null;
    }
  }
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY")?.replaceAll(
    "\\n",
    "\n",
  );
  if (!projectId || !clientEmail || !privateKey) return null;
  return {
    project_id: projectId,
    client_email: clientEmail,
    private_key: privateKey,
  };
}

async function firebaseAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlJson({ alg: "RS256", typ: "JWT" });
  const payload = base64UrlJson({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  });
  const unsignedJwt = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedJwt),
  );
  const assertion = `${unsignedJwt}.${base64UrlBytes(signature)}`;
  const response = await fetchWithTimeout(
    "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    },
    8_000,
  );
  const bytes = await readLimitedBody(response.body, 32 * 1024);
  let data: Record<string, unknown> = {};
  try {
    data = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    // Handled as an unavailable provider below.
  }
  if (!response.ok || !data.access_token) {
    throw new Error("Firebase access token request failed");
  }
  return String(data.access_token);
}

async function sendFcmMessage({
  accessToken,
  projectId,
  token,
  threadId,
  messageId,
  soundEnabled,
}: {
  accessToken: string;
  projectId: string;
  token: string;
  threadId: string;
  messageId: string;
  soundEnabled: boolean;
}): Promise<FcmSendResult> {
  const title = "Новое сообщение";
  const body = "Откройте приложение, чтобы прочитать.";
  const androidNotification: Record<string, unknown> = {
    channel_id: soundEnabled ? "messages" : "messages_silent",
    click_action: "FLUTTER_NOTIFICATION_CLICK",
  };
  if (soundEnabled) androidNotification.sound = "default";
  const aps: Record<string, unknown> = { "thread-id": threadId };
  if (soundEnabled) aps.sound = "default";
  const response = await fetchWithTimeout(
    `https://fcm.googleapis.com/v1/projects/${
      encodeURIComponent(projectId)
    }/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: {
            type: "message",
            kind: "message",
            target_id: messageId,
            thread_id: threadId,
            message_id: messageId,
          },
          android: {
            priority: "high",
            notification: androidNotification,
          },
          apns: {
            headers: {
              "apns-priority": "10",
              "apns-push-type": "alert",
            },
            payload: { aps },
          },
        },
      }),
    },
    8_000,
  );
  const responseText = new TextDecoder().decode(
    await readLimitedBody(response.body, 16 * 1024),
  );
  return {
    ok: response.ok,
    invalidToken: !response.ok && isUnregisteredFcmToken(responseText),
    error: response.ok ? "" : `fcm_http_${response.status}`,
  };
}

function isUnregisteredFcmToken(responseText: string): boolean {
  if (
    responseText.toLowerCase().includes("registration-token-not-registered")
  ) {
    return true;
  }
  try {
    const payload = JSON.parse(responseText) as {
      error?: { details?: Array<{ errorCode?: string }> };
    };
    return payload.error?.details?.some((detail) =>
      detail.errorCode?.toUpperCase() === "UNREGISTERED"
    ) ?? false;
  } catch {
    return false;
  }
}

function skippedResult(reason: string) {
  return {
    status: "skipped" as const,
    sent: 0,
    failed: 0,
    total: 0,
    invalidTokensRemoved: 0,
    skipped: reason,
    error: reason,
  };
}

function validateIdentifier(value: unknown, field: string): string {
  const identifier = String(value ?? "");
  if (
    identifier.length < 1 ||
    identifier.length > 200 ||
    !/^[A-Za-z0-9._:-]+$/.test(identifier)
  ) {
    throw new EdgeError(400, `invalid_${field}`, `${field} is invalid`);
  }
  return identifier;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(
      value,
    );
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function base64UrlJson(value: unknown): string {
  return base64UrlString(JSON.stringify(value));
}

function base64UrlString(value: string): string {
  return btoa(value)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function base64UrlBytes(value: ArrayBuffer): string {
  const bytes = new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}
