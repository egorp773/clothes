import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type ChatMessage = {
  id?: string;
  text?: string;
  sender_id?: string;
  sender_name?: string;
  type?: string;
  product?: { title?: string };
};

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

type RecipientPreferences = {
  userId: string;
  pushEnabled: boolean;
  messagesEnabled: boolean;
  soundEnabled: boolean;
};

type PushToken = {
  user_id: string;
  token: string;
};

type ThreadMemberState = {
  user_id: string;
  is_muted: boolean | null;
};

type FcmSendResult = {
  ok: boolean;
  status: number;
  invalidToken: boolean;
  error: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const serviceAccount = loadFirebaseServiceAccount();

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "Missing Supabase env vars" }, 500);
  }

  let threadId = "";
  let messageId = "";
  try {
    const body = await req.json();
    threadId = String(body.thread_id ?? "");
    messageId = String(body.message_id ?? "");
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (!threadId || !messageId) {
    return json({ error: "thread_id and message_id are required" }, 400);
  }

  const authorization = req.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();

  if (userError || !user) {
    return json({ error: "Unauthorized" }, 401);
  }

  const { data: thread, error: threadError } = await userClient
    .from("message_threads")
    .select(
      "id,buyer_id,seller_id,buyer_name,seller_name,title,is_group,member_ids",
    )
    .eq("id", threadId)
    .maybeSingle();

  if (threadError) return json({ error: threadError.message }, 500);
  if (!thread) return json({ error: "Thread not found" }, 404);

  const senderId = user.id;
  const memberIds = Array.isArray(thread.member_ids)
    ? thread.member_ids.map(String)
    : [thread.buyer_id, thread.seller_id].filter(Boolean).map(String);
  if (!memberIds.includes(senderId)) {
    return json({ error: "Forbidden" }, 403);
  }

  const { data: message, error: messageError } = await userClient
    .from("chat_messages")
    .select("id,text,sender_id,sender_name,type,product")
    .eq("id", messageId)
    .eq("thread_id", threadId)
    .maybeSingle() as {
      data: ChatMessage | null;
      error: { message: string } | null;
    };

  if (messageError) return json({ error: messageError.message }, 500);
  if (!message || message.sender_id !== senderId) {
    return json({ error: "Message not found" }, 404);
  }

  const recipientIds = [
    ...new Set(memberIds.filter((id: string) => id !== senderId)),
  ];
  if (recipientIds.length === 0) {
    return json({ sent: 0, skipped: "empty_recipient" });
  }

  const title = truncateNotificationText(
    message.sender_name?.trim() ||
      (senderId === thread.buyer_id ? thread.buyer_name : thread.seller_name) ||
      "Новое сообщение",
    80,
  );
  const rawBody = message.type === "product"
    ? `Объявление: ${message.product?.title ?? "товар"}`
    : message.type === "image"
    ? message.text?.trim() || "Фотография"
    : message.type === "video"
    ? message.text?.trim() || "Видео"
    : message.text?.trim() || "Новое сообщение";
  const body = truncateNotificationText(rawBody, 180);

  const { data: settingsRows, error: settingsError } = await serviceClient
    .from("notification_settings")
    .select("user_id,push_enabled,messages_enabled,sound_enabled")
    .in("user_id", recipientIds) as {
      data: NotificationSettings[] | null;
      error: { message: string } | null;
    };

  if (settingsError) return json({ error: settingsError.message }, 500);

  const { data: threadStateRows, error: threadStateError } = await serviceClient
    .from("chat_thread_member_state")
    .select("user_id,is_muted")
    .eq("thread_id", threadId)
    .in("user_id", recipientIds) as {
      data: ThreadMemberState[] | null;
      error: { message: string } | null;
    };

  if (threadStateError) {
    return json({ error: threadStateError.message }, 500);
  }
  const mutedRecipientIds = new Set(
    (threadStateRows ?? [])
      .filter((state) => state.is_muted === true)
      .map((state) => state.user_id),
  );

  const settingsByUser = new Map(
    (settingsRows ?? []).map((settings) => [settings.user_id, settings]),
  );
  const recipients: RecipientPreferences[] = recipientIds.map((userId) => {
    const settings = settingsByUser.get(userId);
    return {
      userId,
      // A missing settings row (or a nullable legacy value) means enabled.
      pushEnabled: settings?.push_enabled ?? true,
      messagesEnabled: settings?.messages_enabled ?? true,
      soundEnabled: settings?.sound_enabled ?? true,
    };
  });
  const pushRecipients = recipients.filter(
    (item) =>
      item.messagesEnabled &&
      item.pushEnabled &&
      !mutedRecipientIds.has(item.userId),
  );

  if (pushRecipients.length === 0) {
    return json({
      sent: 0,
      total: 0,
      skipped: "messages_push_disabled_or_thread_muted",
    });
  }

  const pushRecipientIds = pushRecipients.map((item) => item.userId);
  const preferencesByUser = new Map(
    pushRecipients.map((preferences) => [preferences.userId, preferences]),
  );
  const { data: tokenRows, error: tokensError } = await serviceClient
    .from("device_push_tokens")
    .select("user_id,token")
    .in("user_id", pushRecipientIds) as {
      data: PushToken[] | null;
      error: { message: string } | null;
    };

  if (tokensError) return json({ error: tokensError.message }, 500);
  const tokens = (tokenRows ?? []).filter((row) =>
    row.token && preferencesByUser.has(row.user_id)
  );
  if (tokens.length === 0) {
    return json({
      sent: 0,
      total: 0,
      skipped: "no_tokens",
    });
  }

  if (!serviceAccount) {
    return json({
      sent: 0,
      total: tokens.length,
      skipped: "firebase_not_configured",
    });
  }

  const badgeByUser = new Map<string, number>();
  await Promise.all(
    pushRecipientIds.map(async (recipientId) => {
      const { count, error } = await serviceClient
        .from("notifications")
        .select("id", { count: "exact", head: true })
        .eq("user_id", recipientId)
        .eq("is_read", false)
        .neq("kind", "message");
      if (error) {
        console.error(`Badge count failed for recipient: ${error.message}`);
        badgeByUser.set(recipientId, 0);
        return;
      }
      badgeByUser.set(recipientId, count ?? 0);
    }),
  );

  let accessToken: string;
  try {
    accessToken = await firebaseAccessToken(serviceAccount);
  } catch (error) {
    console.error("Could not authorize Firebase push delivery", error);
    return json({
      error: "Could not authorize push delivery",
    }, 502);
  }

  const results = await Promise.all(
    tokens.map(async ({ user_id: recipientId, token }) => {
      const preferences = preferencesByUser.get(recipientId);
      if (!preferences) return { sent: false, invalidTokenRemoved: false };

      try {
        const result = await sendFcmMessage({
          accessToken,
          projectId: serviceAccount.project_id,
          token,
          title,
          body,
          threadId,
          messageId,
          badge: badgeByUser.get(recipientId) ?? 0,
          soundEnabled: preferences.soundEnabled,
        });

        let invalidTokenRemoved = false;
        if (result.invalidToken) {
          const { error: deleteError } = await serviceClient
            .from("device_push_tokens")
            .delete()
            .eq("token", token);
          if (deleteError) {
            console.error(
              `Could not remove invalid push token: ${deleteError.message}`,
            );
          } else {
            invalidTokenRemoved = true;
          }
        }

        if (!result.ok) {
          console.error(
            `FCM delivery failed with status ${result.status}: ${result.error}`,
          );
        }
        return { sent: result.ok, invalidTokenRemoved };
      } catch (error) {
        // A network or payload failure for one installation must not prevent
        // delivery attempts to the recipient's other installations.
        console.error("FCM delivery failed for one installation", error);
        return { sent: false, invalidTokenRemoved: false };
      }
    }),
  );

  return json({
    sent: results.filter((result) => result.sent).length,
    failed: results.filter((result) => !result.sent).length,
    total: results.length,
    invalid_tokens_removed: results.filter((result) =>
      result.invalidTokenRemoved
    ).length,
  });
});

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

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    throw new Error(`Could not get Firebase access token: ${response.status}`);
  }

  const data = await response.json();
  return String(data.access_token);
}

async function sendFcmMessage({
  accessToken,
  projectId,
  token,
  title,
  body,
  threadId,
  messageId,
  badge,
  soundEnabled,
}: {
  accessToken: string;
  projectId: string;
  token: string;
  title: string;
  body: string;
  threadId: string;
  messageId: string;
  badge: number;
  soundEnabled: boolean;
}): Promise<FcmSendResult> {
  const androidNotification: Record<string, unknown> = {
    channel_id: soundEnabled ? "messages" : "messages_silent",
    click_action: "FLUTTER_NOTIFICATION_CLICK",
  };
  if (soundEnabled) androidNotification.sound = "default";

  const aps: Record<string, unknown> = {
    badge,
    "thread-id": threadId,
  };
  if (soundEnabled) aps.sound = "default";

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
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
            title,
            body,
            sound_enabled: String(soundEnabled),
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
            payload: {
              aps,
            },
          },
        },
      }),
    },
  );

  const responseText = await response.text();
  if (response.ok) {
    return { ok: true, status: response.status, invalidToken: false, error: "" };
  }

  return {
    ok: false,
    status: response.status,
    invalidToken: isUnregisteredFcmToken(responseText),
    error: responseText.slice(0, 1000),
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
      error?: {
        details?: Array<{
          errorCode?: string;
          [key: string]: unknown;
        }>;
      };
    };
    return payload.error?.details?.some((detail) =>
      detail.errorCode?.toUpperCase() === "UNREGISTERED"
    ) ?? false;
  } catch {
    return false;
  }
}

function truncateNotificationText(value: string, maxCharacters: number) {
  const characters = Array.from(value.trim());
  if (characters.length <= maxCharacters) return characters.join("");
  return `${characters.slice(0, Math.max(1, maxCharacters - 1)).join("")}…`;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
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
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
