import {
  beginOAuthAttempt,
  claimOAuthCallback,
  completeOAuthCallback,
  exchangeOAuthCode,
  failOAuthAttempt,
  oauthAdmin,
  type OAuthAttempt,
} from "../_shared/oauth.ts";
import {
  EdgeError,
  errorResponse,
  exactRedirect,
  fetchWithTimeout,
  randomBase64Url,
  readJsonResponse,
  redirectWithParams,
  requiredEnv,
  safeErrorCode,
  strictCorsHeaders,
} from "../_shared/edge.ts";

const provider = "yandex" as const;
const yandexScopes = "login:info login:email";

Deno.serve(async (request) => {
  const requestId = crypto.randomUUID();
  try {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: strictCorsHeaders(request, "OAUTH_ALLOWED_WEB_ORIGINS"),
      });
    }
    if (request.method === "POST") {
      return await exchangeOAuthCode(
        request,
        provider,
        strictCorsHeaders(request, "OAUTH_ALLOWED_WEB_ORIGINS"),
      );
    }
    if (request.method !== "GET") {
      throw new EdgeError(
        405,
        "method_not_allowed",
        "Use GET, POST, or OPTIONS",
      );
    }

    const url = new URL(request.url);
    if (
      url.searchParams.has("code") ||
      url.searchParams.has("error") ||
      url.searchParams.has("state")
    ) {
      return await handleCallback(url);
    }
    return await beginAuthorization(url);
  } catch (error) {
    return errorResponse(error, requestId);
  }
});

async function beginAuthorization(url: URL): Promise<Response> {
  const clientId = requiredEnv("YANDEX_CLIENT_ID");
  requiredEnv("YANDEX_CLIENT_SECRET");
  const redirectUri = exactRedirect(url.searchParams.get("redirect_to"));
  const providerCodeVerifier = randomBase64Url(64);
  const providerCodeChallenge = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(providerCodeVerifier),
  ).then((digest) => {
    let binary = "";
    for (const byte of new Uint8Array(digest)) {
      binary += String.fromCharCode(byte);
    }
    return btoa(binary)
      .replaceAll("+", "-")
      .replaceAll("/", "_")
      .replaceAll("=", "");
  });
  const attempt = await beginOAuthAttempt(oauthAdmin(), {
    provider,
    redirectUri,
    appCodeChallenge: url.searchParams.get("code_challenge") ?? "",
    providerCodeVerifier,
  });

  const authorizationUrl = new URL("https://oauth.yandex.ru/authorize");
  authorizationUrl.searchParams.set("response_type", "code");
  authorizationUrl.searchParams.set("client_id", clientId);
  authorizationUrl.searchParams.set("redirect_uri", callbackUrl());
  authorizationUrl.searchParams.set("scope", yandexScopes);
  authorizationUrl.searchParams.set("state", attempt.state);
  authorizationUrl.searchParams.set("code_challenge", providerCodeChallenge);
  authorizationUrl.searchParams.set("code_challenge_method", "S256");
  return externalRedirect(authorizationUrl.toString());
}

async function handleCallback(url: URL): Promise<Response> {
  const admin = oauthAdmin();
  let attempt: OAuthAttempt | null = null;
  try {
    attempt = await claimOAuthCallback(
      admin,
      provider,
      url.searchParams.get("state"),
    );
    const providerError = url.searchParams.get("error");
    if (providerError) {
      throw new EdgeError(
        400,
        safeErrorCode(providerError),
        "Yandex authentication was not completed",
      );
    }
    const code = url.searchParams.get("code");
    if (!code || !attempt.provider_code_verifier) {
      throw new EdgeError(
        400,
        "invalid_provider_callback",
        "Yandex authorization code is missing",
      );
    }
    const accessToken = await exchangeProviderCode(
      code,
      attempt.provider_code_verifier,
    );
    const profile = await loadYandexProfile(accessToken);
    const exchangeCode = await completeOAuthCallback(admin, attempt, profile);
    return redirectWithParams(attempt.redirect_uri, {
      oauth_code: exchangeCode,
      oauth_provider: provider,
    });
  } catch (error) {
    if (!attempt) throw error;
    await failOAuthAttempt(admin, attempt.id);
    return redirectWithParams(attempt.redirect_uri, {
      oauth_error: error instanceof EdgeError
        ? error.code
        : "authentication_failed",
      oauth_provider: provider,
    });
  }
}

async function exchangeProviderCode(
  code: string,
  codeVerifier: string,
): Promise<string> {
  const clientId = requiredEnv("YANDEX_CLIENT_ID");
  const clientSecret = requiredEnv("YANDEX_CLIENT_SECRET");
  const response = await fetchWithTimeout(
    "https://oauth.yandex.ru/token",
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code,
        redirect_uri: callbackUrl(),
        code_verifier: codeVerifier,
      }),
    },
    8_000,
  );
  const payload = await readJsonResponse(response, 64 * 1024);
  if (!response.ok || !payload.access_token) {
    throw new EdgeError(
      502,
      "provider_token_exchange_failed",
      "Yandex token exchange failed",
    );
  }
  return String(payload.access_token);
}

async function loadYandexProfile(accessToken: string) {
  const response = await fetchWithTimeout(
    "https://login.yandex.ru/info?format=json",
    {
      headers: { Authorization: `OAuth ${accessToken}` },
    },
    8_000,
  );
  const payload = await readJsonResponse(response, 64 * 1024);
  const subject = String(payload.id ?? "");
  if (!response.ok || !subject) {
    throw new EdgeError(
      502,
      "provider_profile_failed",
      "Yandex profile could not be verified",
    );
  }
  const username = String(payload.login ?? "");
  const fullName = String(
    payload.real_name ?? payload.display_name ?? payload.name ?? username,
  );
  const avatarId = String(payload.default_avatar_id ?? "");
  return {
    subject,
    username,
    fullName: fullName || username || `Yandex ${subject}`,
    avatarUrl: avatarId
      ? `https://avatars.yandex.net/get-yapic/${
        encodeURIComponent(avatarId)
      }/islands-200`
      : "",
  };
}

function callbackUrl(): string {
  const base = new URL(requiredEnv("SUPABASE_URL"));
  if (base.protocol !== "https:" && base.hostname !== "127.0.0.1") {
    throw new EdgeError(
      500,
      "server_misconfigured",
      "SUPABASE_URL must use HTTPS",
    );
  }
  return new URL("/functions/v1/yandex-auth", base).toString();
}

function externalRedirect(location: string): Response {
  return new Response(null, {
    status: 303,
    headers: {
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      Location: location,
    },
  });
}
