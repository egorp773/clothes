import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const defaultRedirectTo = "com.example.clothes://login-callback/";
const yandexScopes = "login:info login:email";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const url = new URL(req.url);
  if (req.method !== "GET") {
    return json({ error: "Method not allowed" }, 405);
  }

  if (url.searchParams.has("code") || url.searchParams.has("error")) {
    return handleYandexCallback(url);
  }

  return redirectToYandex(url);
});

function redirectToYandex(url: URL) {
  const clientId = Deno.env.get("YANDEX_CLIENT_ID");
  if (!clientId) {
    return renderMessage(
      "Yandex login is not configured",
      "Set YANDEX_CLIENT_ID and YANDEX_CLIENT_SECRET for the yandex-auth function.",
      500,
    );
  }

  const redirectTo = safeRedirectTo(url.searchParams.get("redirect_to"));
  const callbackUrl = yandexCallbackUrl(url);
  const authUrl = new URL("https://oauth.yandex.ru/authorize");
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("client_id", clientId);
  authUrl.searchParams.set("redirect_uri", callbackUrl);
  authUrl.searchParams.set("scope", yandexScopes);
  authUrl.searchParams.set("state", encodeState({ redirectTo }));

  return Response.redirect(authUrl.toString(), 302);
}

async function handleYandexCallback(url: URL) {
  const error = url.searchParams.get("error");
  const state = decodeState(url.searchParams.get("state"));
  const redirectTo = safeRedirectTo(state.redirectTo);
  if (error) {
    return redirectWithError(
      redirectTo,
      url.searchParams.get("error_description") ?? error,
    );
  }

  const code = url.searchParams.get("code");
  if (!code) {
    return redirectWithError(redirectTo, "Missing authorization code.");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const yandexClientId = Deno.env.get("YANDEX_CLIENT_ID");
  const yandexClientSecret = Deno.env.get("YANDEX_CLIENT_SECRET");

  if (!supabaseUrl || !serviceRoleKey || !yandexClientId || !yandexClientSecret) {
    return renderMessage(
      "Yandex login is not configured",
      "Set SUPABASE_SERVICE_ROLE_KEY, YANDEX_CLIENT_ID and YANDEX_CLIENT_SECRET.",
      500,
    );
  }

  const callbackUrl = yandexCallbackUrl(url);
  const token = await exchangeCodeForYandexToken({
    code,
    callbackUrl,
    clientId: yandexClientId,
    clientSecret: yandexClientSecret,
  });

  if (!token.ok) {
    return redirectWithError(redirectTo, token.error);
  }

  const profile = await fetchYandexProfile(token.accessToken);
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

async function exchangeCodeForYandexToken({
  code,
  callbackUrl,
  clientId,
  clientSecret,
}: {
  code: string;
  callbackUrl: string;
  clientId: string;
  clientSecret: string;
}) {
  try {
    const response = await fetch("https://oauth.yandex.ru/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
      },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code,
        redirect_uri: callbackUrl,
      }),
    });
    const data = await response.json().catch(() => null);
    if (!response.ok || !data?.access_token) {
      return {
        ok: false as const,
        error: data?.error_description ?? data?.error ?? "Could not get Yandex token.",
      };
    }
    return { ok: true as const, accessToken: String(data.access_token) };
  } catch (error) {
    return {
      ok: false as const,
      error: error instanceof Error ? error.message : "Could not get Yandex token.",
    };
  }
}

async function fetchYandexProfile(accessToken: string) {
  try {
    const response = await fetch("https://login.yandex.ru/info?format=json", {
      headers: { Authorization: `OAuth ${accessToken}` },
    });
    const data = await response.json().catch(() => null);
    if (!response.ok || !data?.id) {
      return {
        ok: false as const,
        error: data?.error_description ?? data?.error ?? "Could not get Yandex profile.",
      };
    }

    const login = String(data.login ?? "");
    const displayName = String(
      data.real_name ?? data.display_name ?? data.name ?? login,
    ).trim();
    const email = String(
      data.default_email ?? data.email ?? `yandex_${data.id}@yandex.local`,
    );

    return {
      ok: true as const,
      data: {
        id: String(data.id),
        login,
        email,
        fullName: displayName || login || `Yandex ${data.id}`,
        avatarUrl: data.default_avatar_id
          ? `https://avatars.yandex.net/get-yapic/${data.default_avatar_id}/islands-200`
          : "",
      },
    };
  } catch (error) {
    return {
      ok: false as const,
      error: error instanceof Error ? error.message : "Could not get Yandex profile.",
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
    login: string;
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
        provider: "yandex",
        yandex_id: profile.id,
        username: profile.login,
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

  return Response.redirect(uri.toString(), 302);
}

function redirectWithError(redirectTo: string, message: string) {
  const uri = new URL(redirectTo);
  uri.hash = new URLSearchParams({
    error: "auth_failed",
    error_description: message,
  }).toString();
  return Response.redirect(uri.toString(), 302);
}

function yandexCallbackUrl(url: URL) {
  return `https://${url.host}/functions/v1/yandex-auth`;
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

function encodeState(state: { redirectTo: string }) {
  return btoa(JSON.stringify(state))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function decodeState(value: string | null) {
  if (!value) return { redirectTo: defaultRedirectTo };
  try {
    const padded = value.replaceAll("-", "+").replaceAll("_", "/");
    const json = atob(padded.padEnd(Math.ceil(padded.length / 4) * 4, "="));
    const state = JSON.parse(json) as { redirectTo?: string };
    return { redirectTo: state.redirectTo ?? defaultRedirectTo };
  } catch {
    return { redirectTo: defaultRedirectTo };
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

function renderAppRedirect(appUrl: string) {
  const encodedUrl = escapeHtml(appUrl);
  const jsUrl = JSON.stringify(appUrl);
  return html(`<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Возвращаем в приложение</title>
  <style>
    body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#fff;color:#070707}
    main{min-height:100vh;display:grid;place-items:center;padding:24px}
    section{width:min(420px,100%);text-align:center}
    h1{font-size:22px;margin:0 0 10px;font-weight:800}
    p{font-size:14px;line-height:1.45;color:#72727a;margin:0 0 22px}
    a{display:inline-flex;align-items:center;justify-content:center;min-height:46px;padding:0 18px;border-radius:8px;background:#050505;color:#fff;text-decoration:none;font-weight:700}
  </style>
</head>
<body>
  <main>
    <section>
      <h1>Вход выполнен</h1>
      <p>Сейчас вернём вас в приложение.</p>
      <a href="${encodedUrl}">Открыть приложение</a>
    </section>
  </main>
  <script>
    window.location.replace(${jsUrl});
    setTimeout(function () { window.location.href = ${jsUrl}; }, 500);
  </script>
</body>
</html>`);
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

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
