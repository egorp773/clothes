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
  redirectWithParams,
  requiredEnv,
  strictCorsHeaders,
} from "../_shared/edge.ts";
import { verifyTelegramLogin } from "../_shared/telegram.ts";

const provider = "telegram" as const;

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
    if (url.searchParams.has("hash") || url.searchParams.has("state")) {
      return await handleCallback(url);
    }
    return await beginAuthorization(url);
  } catch (error) {
    return errorResponse(error, requestId);
  }
});

async function beginAuthorization(url: URL): Promise<Response> {
  const botId = requiredEnv("TELEGRAM_BOT_ID");
  const botToken = requiredEnv("TELEGRAM_BOT_TOKEN");
  if (!/^\d{1,32}$/.test(botId) || botToken.length < 20) {
    throw new EdgeError(
      500,
      "server_misconfigured",
      "Telegram credentials are invalid",
    );
  }
  const redirectUri = exactRedirect(url.searchParams.get("redirect_to"));
  const attempt = await beginOAuthAttempt(oauthAdmin(), {
    provider,
    redirectUri,
    appCodeChallenge: url.searchParams.get("code_challenge") ?? "",
  });

  const returnTo = new URL(callbackUrl());
  returnTo.searchParams.set("state", attempt.state);
  const authorizationUrl = new URL("https://oauth.telegram.org/auth");
  authorizationUrl.searchParams.set("bot_id", botId);
  authorizationUrl.searchParams.set(
    "origin",
    new URL(requiredEnv("SUPABASE_URL")).origin,
  );
  authorizationUrl.searchParams.set("return_to", returnTo.toString());
  return externalRedirect(authorizationUrl.toString());
}

async function handleCallback(url: URL): Promise<Response> {
  const admin = oauthAdmin();
  let attempt: OAuthAttempt | null = null;
  try {
    await verifyTelegramLogin(
      url.searchParams,
      requiredEnv("TELEGRAM_BOT_TOKEN"),
      {
        maxAgeSeconds: Number(
          Deno.env.get("TELEGRAM_AUTH_MAX_AGE_SECONDS") ?? 300,
        ),
      },
    );
    attempt = await claimOAuthCallback(
      admin,
      provider,
      url.searchParams.get("state"),
    );
    const subject = url.searchParams.get("id") ?? "";
    const firstName = url.searchParams.get("first_name") ?? "";
    const lastName = url.searchParams.get("last_name") ?? "";
    const username = url.searchParams.get("username") ?? "";
    const fullName = `${firstName} ${lastName}`.trim();
    const exchangeCode = await completeOAuthCallback(admin, attempt, {
      subject,
      username,
      fullName: fullName || username || `Telegram ${subject}`,
      avatarUrl: url.searchParams.get("photo_url") ?? "",
    });
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

function callbackUrl(): string {
  const base = new URL(requiredEnv("SUPABASE_URL"));
  if (base.protocol !== "https:" && base.hostname !== "127.0.0.1") {
    throw new EdgeError(
      500,
      "server_misconfigured",
      "SUPABASE_URL must use HTTPS",
    );
  }
  return new URL("/functions/v1/telegram-auth", base).toString();
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
