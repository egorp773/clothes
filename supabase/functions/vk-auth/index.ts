import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const defaultRedirectTo = "com.example.clothes://login-callback/";
const vkScopes = "vkid.personal_info email";
const stateCookieName = "vk_auth_state";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const url = new URL(req.url);
  if (req.method !== "GET") {
    return json({ error: "Method not allowed" }, 405);
  }

  if (url.searchParams.has("code") || url.searchParams.has("error")) {
    return handleVkCallback(req, url);
  }

  return redirectToVk(url);
});

async function redirectToVk(url: URL) {
  const clientId = Deno.env.get("VK_CLIENT_ID");
  if (!clientId) {
    return renderMessage(
      "VK ID login is not configured",
      "Set VK_CLIENT_ID for the vk-auth function.",
      500,
    );
  }

  const redirectTo = safeRedirectTo(url.searchParams.get("redirect_to"));
  const callbackUrl = vkCallbackUrl(url);
  const codeVerifier = randomBase64Url(64);
  const codeChallenge = await sha256Base64Url(codeVerifier);
  const nonce = randomBase64Url(24);
  const state = encodeState({ nonce });
  const cookieState = encodeState({ redirectTo, nonce, codeVerifier });

  const authUrl = new URL("https://id.vk.ru/authorize");
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("client_id", clientId);
  authUrl.searchParams.set("redirect_uri", callbackUrl);
  authUrl.searchParams.set("scope", vkScopes);
  authUrl.searchParams.set("state", state);
  authUrl.searchParams.set("code_challenge", codeChallenge);
  authUrl.searchParams.set("code_challenge_method", "S256");

  return redirect(authUrl.toString(), {
    "Set-Cookie": `${stateCookieName}=${cookieState}; Path=/functions/v1/vk-auth; Max-Age=600; HttpOnly; Secure; SameSite=Lax`,
  });
}

async function handleVkCallback(req: Request, url: URL) {
  const cookieState = decodeState(readCookie(req, stateCookieName));
  const state = decodeState(url.searchParams.get("state"));
  const redirectTo = safeRedirectTo(cookieState.redirectTo);

  if (!cookieState.codeVerifier || !cookieState.nonce || cookieState.nonce !== state.nonce) {
    return redirectWithError(redirectTo, "VK ID authorization session expired. Try again.");
  }

  const error = url.searchParams.get("error");
  if (error) {
    return redirectWithError(
      redirectTo,
      url.searchParams.get("error_description") ?? error,
    );
  }

  const code = url.searchParams.get("code");
  const deviceId = url.searchParams.get("device_id") ?? "";
  if (!code) {
    return redirectWithError(redirectTo, "Missing authorization code.");
  }
  if (!deviceId) {
    return redirectWithError(redirectTo, "Missing VK ID device_id.");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const vkClientId = Deno.env.get("VK_CLIENT_ID");

  if (!supabaseUrl || !serviceRoleKey || !vkClientId) {
    return renderMessage(
      "VK ID login is not configured",
      "Set SUPABASE_SERVICE_ROLE_KEY and VK_CLIENT_ID.",
      500,
    );
  }

  const token = await exchangeCodeForVkToken({
    code,
    deviceId,
    callbackUrl: vkCallbackUrl(url),
    clientId: vkClientId,
    codeVerifier: cookieState.codeVerifier,
    state: url.searchParams.get("state") ?? "",
  });

  if (!token.ok) {
    return redirectWithError(redirectTo, token.error);
  }

  const profile = await fetchVkProfile({
    accessToken: token.accessToken,
    clientId: vkClientId,
    idToken: token.idToken,
  });
  if (!profile.ok) {
    return redirectWithError(redirectTo, profile.error);
  }

  const session = await createSupabaseSession({
    supabaseUrl,
    serviceRoleKey,
    profile: profile.data,
  });
  if (!session.ok) {
    return redirectWithError(redirectTo, session.error);
  }

  return redirectWithSession(redirectTo, session.data);
}

async function exchangeCodeForVkToken({
  code,
  deviceId,
  callbackUrl,
  clientId,
  codeVerifier,
  state,
}: {
  code: string;
  deviceId: string;
  callbackUrl: string;
  clientId: string;
  codeVerifier: string;
  state: string;
}) {
  try {
    const response = await fetch("https://id.vk.ru/oauth2/auth", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        client_id: clientId,
        code,
        code_verifier: codeVerifier,
        device_id: deviceId,
        redirect_uri: callbackUrl,
        state,
      }),
    });
    const data = await response.json().catch(() => null);
    if (!response.ok || !data?.access_token) {
      return {
        ok: false as const,
        error: data?.error_description ?? data?.error ?? "Could not get VK ID token.",
      };
    }
    return {
      ok: true as const,
      accessToken: String(data.access_token),
      idToken: data.id_token ? String(data.id_token) : "",
    };
  } catch (error) {
    return {
      ok: false as const,
      error: error instanceof Error ? error.message : "Could not get VK ID token.",
    };
  }
}

async function fetchVkProfile({
  accessToken,
  clientId,
  idToken,
}: {
  accessToken: string;
  clientId: string;
  idToken: string;
}) {
  try {
    const response = await fetch("https://id.vk.ru/oauth2/user_info", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        access_token: accessToken,
        client_id: clientId,
      }),
    });
    const data = await response.json().catch(() => null);
    const user = data?.user ?? data;
    const jwt = decodeJwtPayload(idToken);
    const id = String(user?.user_id ?? user?.id ?? user?.sub ?? jwt?.sub ?? "");
    if (!response.ok || !id) {
      return {
        ok: false as const,
        error: data?.error_description ?? data?.error ?? "Could not get VK ID profile.",
      };
    }

    const firstName = String(user?.first_name ?? jwt?.given_name ?? "").trim();
    const lastName = String(user?.last_name ?? jwt?.family_name ?? "").trim();
    const fullName = String(
      user?.name ?? jwt?.name ?? `${firstName} ${lastName}`.trim(),
    ).trim();
    const email = String(
      user?.email ?? data?.email ?? jwt?.email ?? `vk_${id}@vk.local`,
    );
    const username = String(
      user?.screen_name ?? user?.nickname ?? jwt?.preferred_username ?? `vk_${id}`,
    );
    const avatarUrl = String(
      user?.avatar ?? user?.photo_200 ?? user?.picture ?? jwt?.picture ?? "",
    );

    return {
      ok: true as const,
      data: {
        id,
        username,
        email,
        fullName: fullName || username || `VK ${id}`,
        avatarUrl,
      },
    };
  } catch (error) {
    return {
      ok: false as const,
      error: error instanceof Error ? error.message : "Could not get VK ID profile.",
    };
  }
}

async function createSupabaseSession({
  supabaseUrl,
  serviceRoleKey,
  profile,
}: {
  supabaseUrl: string;
  serviceRoleKey: string;
  profile: {
    id: string;
    username: string;
    email: string;
    fullName: string;
    avatarUrl: string;
  };
}) {
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { data, error } = await supabase.auth.admin.generateLink({
    type: "magiclink",
    email: profile.email,
    options: {
      data: {
        provider: "vk",
        vk_id: profile.id,
        username: profile.username,
        full_name: profile.fullName,
        avatar_url: profile.avatarUrl,
      },
      redirectTo: defaultRedirectTo,
    },
  });

  const properties = data?.properties as
    | {
      hashed_token?: string;
      hashedToken?: string;
    }
    | undefined;
  const hashedToken = properties?.hashed_token ?? properties?.hashedToken ?? "";
  if (error || !hashedToken) {
    return {
      ok: false as const,
      error: error?.message ?? "Could not create Supabase magic link.",
    };
  }

  return verifySupabaseToken({ supabaseUrl, serviceRoleKey, hashedToken });
}

async function verifySupabaseToken({
  supabaseUrl,
  serviceRoleKey,
  hashedToken,
}: {
  supabaseUrl: string;
  serviceRoleKey: string;
  hashedToken: string;
}) {
  try {
    const response = await fetch(`${supabaseUrl}/auth/v1/verify`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: serviceRoleKey,
        authorization: `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({
        type: "magiclink",
        token_hash: hashedToken,
      }),
    });

    const data = await response.json().catch(() => null);
    if (!response.ok || !data?.access_token || !data?.refresh_token) {
      return {
        ok: false as const,
        error: data?.msg ?? data?.message ?? "Could not verify Supabase token.",
      };
    }

    return {
      ok: true as const,
      data: {
        accessToken: String(data.access_token),
        refreshToken: String(data.refresh_token),
        expiresIn: String(data.expires_in ?? 3600),
        tokenType: String(data.token_type ?? "bearer"),
      },
    };
  } catch (error) {
    return {
      ok: false as const,
      error: error instanceof Error ? error.message : "Could not verify Supabase token.",
    };
  }
}

function redirectWithSession(
  redirectTo: string,
  session: {
    accessToken: string;
    refreshToken: string;
    expiresIn: string;
    tokenType: string;
  },
) {
  const uri = new URL(redirectTo);
  uri.hash = new URLSearchParams({
    access_token: session.accessToken,
    refresh_token: session.refreshToken,
    expires_in: session.expiresIn,
    token_type: session.tokenType,
    type: "magiclink",
  }).toString();

  return redirect(uri.toString(), clearStateCookieHeaders());
}

function redirectWithError(redirectTo: string, message: string) {
  const uri = new URL(redirectTo);
  uri.hash = new URLSearchParams({
    error: "auth_failed",
    error_description: message,
  }).toString();
  return redirect(uri.toString(), clearStateCookieHeaders());
}

function vkCallbackUrl(url: URL) {
  return `https://${url.host}/functions/v1/vk-auth`;
}

function safeRedirectTo(value: string | null | undefined) {
  if (!value) return defaultRedirectTo;
  try {
    const uri = new URL(value);
    if (
      uri.protocol === "com.example.clothes:" ||
      uri.protocol === "http:" ||
      uri.protocol === "https:"
    ) {
      return uri.toString();
    }
  } catch {
    // Fall through to the app redirect.
  }
  return defaultRedirectTo;
}

function encodeState(state: Record<string, string>) {
  return btoa(JSON.stringify(state))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function decodeState(value: string | null) {
  if (!value) return {};
  try {
    const padded = value.replaceAll("-", "+").replaceAll("_", "/");
    const json = atob(padded.padEnd(Math.ceil(padded.length / 4) * 4, "="));
    return JSON.parse(json) as {
      redirectTo?: string;
      nonce?: string;
      codeVerifier?: string;
    };
  } catch {
    return {};
  }
}

function randomBase64Url(byteLength: number) {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return base64Url(bytes);
}

async function sha256Base64Url(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return base64Url(new Uint8Array(digest));
}

function base64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function readCookie(req: Request, name: string) {
  const cookie = req.headers.get("cookie") ?? "";
  const parts = cookie.split(";").map((part) => part.trim());
  const prefix = `${name}=`;
  const value = parts.find((part) => part.startsWith(prefix));
  return value ? value.slice(prefix.length) : null;
}

function clearStateCookieHeaders() {
  return {
    "Set-Cookie": `${stateCookieName}=; Path=/functions/v1/vk-auth; Max-Age=0; HttpOnly; Secure; SameSite=Lax`,
  };
}

function decodeJwtPayload(token: string) {
  if (!token) return null;
  try {
    const payload = token.split(".")[1];
    if (!payload) return null;
    const padded = payload.replaceAll("-", "+").replaceAll("_", "/");
    return JSON.parse(
      atob(padded.padEnd(Math.ceil(padded.length / 4) * 4, "=")),
    ) as Record<string, unknown>;
  } catch {
    return null;
  }
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

function redirect(location: string, extraHeaders: Record<string, string> = {}) {
  return new Response(null, {
    status: 302,
    headers: { ...corsHeaders, ...extraHeaders, Location: location },
  });
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
