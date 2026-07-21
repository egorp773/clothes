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
  sha256Base64Url,
  strictCorsHeaders,
} from "../_shared/edge.ts";

const provider = "vk" as const;
const vkScopes = "vkid.personal_info email";

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
  const clientId = requiredEnv("VK_CLIENT_ID");
  const redirectUri = exactRedirect(url.searchParams.get("redirect_to"));
  const providerCodeVerifier = randomBase64Url(64);
  const providerCodeChallenge = await sha256Base64Url(providerCodeVerifier);
  const attempt = await beginOAuthAttempt(oauthAdmin(), {
    provider,
    redirectUri,
    appCodeChallenge: url.searchParams.get("code_challenge") ?? "",
    providerCodeVerifier,
  });

  const authorizationUrl = new URL("https://id.vk.ru/authorize");
  authorizationUrl.searchParams.set("response_type", "code");
  authorizationUrl.searchParams.set("client_id", clientId);
  authorizationUrl.searchParams.set("redirect_uri", callbackUrl());
  authorizationUrl.searchParams.set("scope", vkScopes);
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
        "VK authentication was not completed",
      );
    }
    const code = url.searchParams.get("code");
    const deviceId = url.searchParams.get("device_id");
    if (!code || !deviceId || !attempt.provider_code_verifier) {
      throw new EdgeError(
        400,
        "invalid_provider_callback",
        "VK authorization callback is incomplete",
      );
    }
    const accessToken = await exchangeProviderCode({
      code,
      deviceId,
      codeVerifier: attempt.provider_code_verifier,
      state: url.searchParams.get("state") ?? "",
    });
    const profile = await loadVkProfile(accessToken);
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

async function exchangeProviderCode({
  code,
  deviceId,
  codeVerifier,
  state,
}: {
  code: string;
  deviceId: string;
  codeVerifier: string;
  state: string;
}): Promise<string> {
  const response = await fetchWithTimeout(
    "https://id.vk.ru/oauth2/auth",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        client_id: requiredEnv("VK_CLIENT_ID"),
        code,
        code_verifier: codeVerifier,
        device_id: deviceId,
        redirect_uri: callbackUrl(),
        state,
      }),
    },
    8_000,
  );
  const payload = await readJsonResponse(response, 64 * 1024);
  if (!response.ok || !payload.access_token) {
    throw new EdgeError(
      502,
      "provider_token_exchange_failed",
      "VK token exchange failed",
    );
  }
  return String(payload.access_token);
}

async function loadVkProfile(accessToken: string) {
  const response = await fetchWithTimeout(
    "https://id.vk.ru/oauth2/user_info",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        access_token: accessToken,
        client_id: requiredEnv("VK_CLIENT_ID"),
      }),
    },
    8_000,
  );
  const payload = await readJsonResponse(response, 64 * 1024);
  const user = payload.user && typeof payload.user === "object"
    ? payload.user as Record<string, unknown>
    : payload;

  // Do not fall back to unverified id_token claims. Only the authenticated
  // user_info response is accepted as the identity source.
  const subject = String(user.user_id ?? user.id ?? user.sub ?? "");
  if (!response.ok || !subject) {
    throw new EdgeError(
      502,
      "provider_profile_failed",
      "VK profile could not be verified",
    );
  }
  const firstName = String(user.first_name ?? "");
  const lastName = String(user.last_name ?? "");
  const username = String(
    user.screen_name ?? user.nickname ?? `vk_${subject}`,
  );
  const fullName = String(
    user.name ?? `${firstName} ${lastName}`.trim() ?? username,
  );
  return {
    subject,
    username,
    fullName: fullName || username || `VK ${subject}`,
    avatarUrl: String(user.avatar ?? user.photo_200 ?? user.picture ?? ""),
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
  return new URL("/functions/v1/vk-auth", base).toString();
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
