import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const maxAuthAgeSeconds = 24 * 60 * 60;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const url = new URL(req.url);

  if (req.method === "GET" && url.searchParams.has("hash")) {
    return handleTelegramCallback(url.searchParams);
  }

  if (req.method === "POST") {
    try {
      const body = await req.json();
      return handleTelegramCallback(new URLSearchParams(body));
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }
  }

  if (req.method === "GET") {
    return renderLoginPage(url);
  }

  return json({ error: "Method not allowed" }, 405);
});

async function handleTelegramCallback(params: URLSearchParams) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN");

  if (!supabaseUrl || !serviceRoleKey || !botToken) {
    return renderMessage(
      "Telegram login is not configured",
      "Set SUPABASE_SERVICE_ROLE_KEY and TELEGRAM_BOT_TOKEN for the telegram-auth function.",
      500,
    );
  }

  const redirectTo =
    params.get("redirect_to") ?? "com.example.clothes://login-callback/";
  const verification = await verifyTelegramPayload(params, botToken);
  if (!verification.ok) {
    return renderMessage("Telegram login failed", verification.error, 401);
  }

  const telegramId = params.get("id")!;
  const firstName = params.get("first_name") ?? "";
  const lastName = params.get("last_name") ?? "";
  const username = params.get("username") ?? "";
  const photoUrl = params.get("photo_url") ?? "";
  const fullName = [firstName, lastName].filter(Boolean).join(" ").trim();
  const email = `telegram_${telegramId}@telegram.local`;

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data, error } = await supabase.auth.admin.generateLink({
    type: "magiclink",
    email,
    options: {
      data: {
        provider: "telegram",
        telegram_id: telegramId,
        username,
        full_name: fullName || username || `Telegram ${telegramId}`,
        avatar_url: photoUrl,
      },
      redirectTo,
    },
  });

  if (error || !data?.properties?.action_link) {
    return renderMessage(
      "Supabase login failed",
      error?.message ?? "Could not create Telegram session.",
      500,
    );
  }

  return Response.redirect(data.properties.action_link, 302);
}

async function verifyTelegramPayload(params: URLSearchParams, botToken: string) {
  const hash = params.get("hash");
  const authDate = Number(params.get("auth_date"));

  if (!hash || !params.get("id") || !authDate) {
    return { ok: false, error: "Telegram payload is missing required fields." };
  }

  const now = Math.floor(Date.now() / 1000);
  if (now - authDate > maxAuthAgeSeconds) {
    return { ok: false, error: "Telegram login payload has expired." };
  }

  const dataCheckString = [...params.entries()]
    .filter(([key]) => key !== "hash" && key !== "redirect_to")
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");

  const secretKey = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(botToken),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    secretKey,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(dataCheckString),
  );

  const expected = bytesToHex(new Uint8Array(signature));
  if (!timingSafeEqual(expected, hash)) {
    return { ok: false, error: "Telegram signature is invalid." };
  }

  return { ok: true };
}

function renderLoginPage(url: URL) {
  const botUsername = Deno.env.get("TELEGRAM_BOT_USERNAME");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const redirectTo =
    url.searchParams.get("redirect_to") ?? "com.example.clothes://login-callback/";

  if (!botUsername || !supabaseUrl) {
    return renderMessage(
      "Telegram login is not configured",
      "Set TELEGRAM_BOT_USERNAME and SUPABASE_URL for the telegram-auth function.",
      500,
    );
  }

  const authUrl = new URL(`${supabaseUrl}/functions/v1/telegram-auth`);
  authUrl.searchParams.set("redirect_to", redirectTo);

  return html(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Telegram login</title>
  <style>
    body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#fff;color:#070707}
    main{min-height:100vh;display:grid;place-items:center;padding:24px}
    section{width:min(360px,100%);text-align:center}
    h1{font-size:22px;margin:0 0 10px;font-weight:800}
    p{font-size:14px;line-height:1.45;color:#72727a;margin:0 0 24px}
  </style>
</head>
<body>
  <main>
    <section>
      <h1>Telegram login</h1>
      <p>Telegram will confirm your account and return you to the app.</p>
      <script async src="https://telegram.org/js/telegram-widget.js?22"
        data-telegram-login="${escapeHtml(botUsername)}"
        data-size="large"
        data-auth-url="${escapeHtml(authUrl.toString())}"
        data-request-access="write"></script>
    </section>
  </main>
</body>
</html>`);
}

function renderMessage(title: string, message: string, status = 200) {
  return html(`<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(title)}</title>
  <style>
    body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#fff;color:#070707}
    main{min-height:100vh;display:grid;place-items:center;padding:24px}
    section{width:min(420px,100%);text-align:center}
    h1{font-size:22px;margin:0 0 10px;font-weight:800}
    p{font-size:14px;line-height:1.45;color:#72727a;margin:0}
  </style>
</head>
<body>
  <main><section><h1>${escapeHtml(title)}</h1><p>${escapeHtml(message)}</p></section></main>
</body>
</html>`, status);
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function html(body: string, status = 200) {
  return new Response(body, {
    status,
    headers: { ...corsHeaders, "Content-Type": "text/html; charset=utf-8" },
  });
}

function bytesToHex(bytes: Uint8Array) {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
