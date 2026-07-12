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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const serviceAccount = loadFirebaseServiceAccount();

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !serviceAccount) {
    return json({ error: "Missing Supabase or Firebase env vars" }, 500);
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

  const recipientIds = memberIds.filter((id: string) => id !== senderId);
  if (recipientIds.length === 0) {
    return json({ sent: 0, skipped: "empty_recipient" });
  }

  const { data: tokens, error: tokensError } = await serviceClient
    .from("device_push_tokens")
    .select("token")
    .in("user_id", recipientIds);

  if (tokensError) return json({ error: tokensError.message }, 500);
  if (!tokens || tokens.length === 0) return json({ sent: 0 });

  const accessToken = await firebaseAccessToken(serviceAccount);
  const title = message.sender_name?.trim() ||
    (senderId === thread.buyer_id ? thread.buyer_name : thread.seller_name) ||
    "Новое сообщение";
  const body = message.type === "product"
    ? `Объявление: ${message.product?.title ?? "товар"}`
    : message.text?.trim() || "Новое сообщение";

  const results = await Promise.all(
    tokens.map(async ({ token }: { token: string }) => {
      const response = await sendFcmMessage({
        accessToken,
        projectId: serviceAccount.project_id,
        token,
        title,
        body,
        threadId,
        messageId,
      });

      if (!response.ok && (response.status === 400 || response.status === 404)) {
        await serviceClient.from("device_push_tokens").delete().eq(
          "token",
          token,
        );
      }

      return response.ok;
    }),
  );

  return json({ sent: results.filter(Boolean).length, total: results.length });
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

function sendFcmMessage({
  accessToken,
  projectId,
  token,
  title,
  body,
  threadId,
  messageId,
}: {
  accessToken: string;
  projectId: string;
  token: string;
  title: string;
  body: string;
  threadId: string;
  messageId: string;
}) {
  return fetch(
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
            thread_id: threadId,
            message_id: messageId,
            title,
            body,
          },
          android: {
            priority: "high",
            notification: {
              channel_id: "messages",
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
              },
            },
          },
        },
      }),
    },
  );
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
