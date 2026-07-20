import {
  createClient,
  type SupabaseClient,
  type User,
} from "npm:@supabase/supabase-js@2.49.8";

import {
  assertPkceChallenge,
  assertPkceVerifier,
  EdgeError,
  fetchWithTimeout,
  jsonResponse,
  randomBase64Url,
  readJsonObject,
  readJsonResponse,
  requiredEnv,
  sha256Hex,
} from "./edge.ts";
import {
  isTrustedProvisionalOAuthCandidate,
  normalizeOAuthSubject,
} from "./oauth_identity.ts";

export type OAuthProvider = "telegram" | "yandex" | "vk";

export type OAuthAttempt = {
  id: string;
  provider: OAuthProvider;
  redirect_uri: string;
  app_code_challenge: string;
  provider_code_verifier: string | null;
  expires_at: string;
};

export type ExternalProfile = {
  subject: string;
  username: string;
  fullName: string;
  avatarUrl: string;
};

const attemptTtlSeconds = 10 * 60;
const exchangeTtlSeconds = 2 * 60;

export function oauthAdmin(): SupabaseClient {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    },
  );
}

export async function beginOAuthAttempt(
  admin: SupabaseClient,
  {
    provider,
    redirectUri,
    appCodeChallenge,
    providerCodeVerifier = null,
  }: {
    provider: OAuthProvider;
    redirectUri: string;
    appCodeChallenge: string;
    providerCodeVerifier?: string | null;
  },
): Promise<{ id: string; state: string }> {
  const challenge = assertPkceChallenge(appCodeChallenge);
  const state = randomBase64Url(32);
  const stateHash = await sha256Hex(state);
  const expiresAt = new Date(Date.now() + attemptTtlSeconds * 1000)
    .toISOString();
  const { data, error } = await admin.rpc("create_oauth_login_attempt", {
    p_provider: provider,
    p_state_hash: stateHash,
    p_redirect_uri: redirectUri,
    p_app_code_challenge: challenge,
    p_provider_code_verifier: providerCodeVerifier,
    p_expires_at: expiresAt,
  });
  if (error || typeof data !== "string") {
    console.error("Could not persist OAuth state", error);
    throw new EdgeError(
      503,
      "oauth_state_unavailable",
      "Authentication cannot be started",
    );
  }
  return { id: data, state };
}

export async function claimOAuthCallback(
  admin: SupabaseClient,
  provider: OAuthProvider,
  state: string | null,
): Promise<OAuthAttempt> {
  if (!state || !/^[A-Za-z0-9_-]{32,128}$/.test(state)) {
    throw new EdgeError(400, "invalid_oauth_state", "OAuth state is invalid");
  }
  const stateHash = await sha256Hex(state);
  const { data, error } = await admin.rpc("claim_oauth_callback", {
    p_provider: provider,
    p_state_hash: stateHash,
  });
  if (error) {
    console.error("Could not claim OAuth callback", error);
    throw new EdgeError(
      503,
      "oauth_state_unavailable",
      "Authentication state cannot be verified",
    );
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new EdgeError(
      400,
      "invalid_oauth_state",
      "OAuth state is expired or already used",
    );
  }
  return data as OAuthAttempt;
}

export async function failOAuthAttempt(
  admin: SupabaseClient,
  attemptId: string,
): Promise<void> {
  const { error } = await admin.rpc("fail_oauth_attempt", {
    p_attempt_id: attemptId,
    p_reason: "provider_callback_failed",
  });
  if (error) console.error("Could not mark OAuth attempt failed", error);
}

export async function completeOAuthCallback(
  admin: SupabaseClient,
  attempt: OAuthAttempt,
  profile: ExternalProfile,
): Promise<string> {
  const sanitized = sanitizeProfile(profile);
  const userId = await resolveExternalIdentity(
    admin,
    attempt.provider,
    sanitized,
  );
  const exchangeCode = randomBase64Url(32);
  const exchangeCodeHash = await sha256Hex(exchangeCode);
  const now = new Date();
  const { error } = await admin.rpc("complete_oauth_callback", {
    p_attempt_id: attempt.id,
    p_provider_subject: sanitized.subject,
    p_profile: {
      username: sanitized.username,
      full_name: sanitized.fullName,
      avatar_url: sanitized.avatarUrl,
    },
    p_auth_user_id: userId,
    p_exchange_code_hash: exchangeCodeHash,
    p_exchange_expires_at: new Date(
      now.getTime() + exchangeTtlSeconds * 1000,
    ).toISOString(),
  });
  if (error) {
    console.error("Could not complete OAuth callback", error);
    throw new EdgeError(
      503,
      "oauth_exchange_unavailable",
      "Authentication cannot be completed",
    );
  }
  return exchangeCode;
}

export async function exchangeOAuthCode(
  request: Request,
  provider: OAuthProvider,
  responseHeaders: HeadersInit = {},
): Promise<Response> {
  const body = await readJsonObject(request, 8 * 1024);
  if (body.action !== "exchange") {
    throw new EdgeError(400, "invalid_action", "Unsupported OAuth action");
  }
  const exchangeCode = String(body.exchange_code ?? "");
  if (!/^[A-Za-z0-9_-]{32,128}$/.test(exchangeCode)) {
    throw new EdgeError(
      400,
      "invalid_exchange_code",
      "OAuth exchange code is invalid",
    );
  }
  const verifier = assertPkceVerifier(body.code_verifier);
  const exchangeCodeHash = await sha256Hex(exchangeCode);
  const admin = oauthAdmin();
  const { data, error } = await admin.rpc("consume_oauth_exchange", {
    p_exchange_code_hash: exchangeCodeHash,
    p_app_code_verifier: verifier,
  });
  if (error) {
    console.error("Could not consume OAuth exchange code", error);
    throw new EdgeError(
      503,
      "oauth_exchange_unavailable",
      "Authentication exchange is unavailable",
    );
  }
  if (
    !data ||
    typeof data !== "object" ||
    Array.isArray(data) ||
    !data.auth_user_id ||
    data.provider !== provider
  ) {
    throw new EdgeError(
      400,
      "invalid_exchange_code",
      "OAuth exchange code is expired, already used, or not bound to this client",
    );
  }

  const session = await issueSession(admin, String(data.auth_user_id));
  return jsonResponse(
    {
      access_token: session.accessToken,
      refresh_token: session.refreshToken,
      expires_in: session.expiresIn,
      token_type: session.tokenType,
      user: {
        id: session.user.id,
        app_metadata: session.user.app_metadata,
        user_metadata: session.user.user_metadata,
      },
    },
    200,
    responseHeaders,
  );
}

async function resolveExternalIdentity(
  admin: SupabaseClient,
  provider: OAuthProvider,
  profile: ExternalProfile,
): Promise<string> {
  const providerProfile = {
    username: profile.username,
    full_name: profile.fullName,
    avatar_url: profile.avatarUrl,
  };
  const { data: existing, error: lookupError } = await admin.rpc(
    "resolve_oauth_identity",
    {
      p_provider: provider,
      p_provider_subject: profile.subject,
      p_profile: providerProfile,
      p_candidate_user_id: null,
    },
  );
  if (lookupError) {
    console.error("Could not resolve OAuth identity", lookupError);
    throw new EdgeError(
      503,
      "identity_lookup_failed",
      "Authentication identity cannot be resolved",
    );
  }
  if (typeof existing === "string") return existing;

  // Provider email is deliberately not used for lookup or linking. The
  // synthetic address is random per candidate, so an attacker cannot
  // pre-register a deterministic address for a known provider subject.
  // Concurrent callbacks are resolved atomically by resolve_oauth_identity;
  // the losing candidate is deleted below.
  const syntheticEmail =
    `oauth-${provider}-${randomBase64Url(24).toLowerCase()}@login.invalid`;
  const { data: created, error: createError } = await admin.auth.admin
    .createUser({
      email: syntheticEmail,
      email_confirm: true,
      app_metadata: {
        oauth_provider: provider,
        oauth_provider_subject: profile.subject,
        registration_status: "provisional",
      },
      user_metadata: {
        provider,
        provider_subject: profile.subject,
        username: profile.username,
        full_name: profile.fullName,
        avatar_url: profile.avatarUrl,
      },
    });
  if (createError || !created.user) {
    console.error("Could not create provisional OAuth identity", createError);
    throw new EdgeError(
      503,
      "identity_creation_failed",
      "Authentication identity cannot be created",
    );
  }
  const candidateUser = created.user;
  if (
    !isTrustedProvisionalOAuthCandidate(
      candidateUser,
      provider,
      profile.subject,
    )
  ) {
    await admin.auth.admin.deleteUser(candidateUser.id).catch(() => undefined);
    console.error("Supabase returned an untrusted OAuth candidate");
    throw new EdgeError(
      503,
      "identity_creation_failed",
      "Authentication identity cannot be created",
    );
  }

  const { data: resolved, error: resolveError } = await admin.rpc(
    "resolve_oauth_identity",
    {
      p_provider: provider,
      p_provider_subject: profile.subject,
      p_profile: providerProfile,
      p_candidate_user_id: candidateUser.id,
    },
  );
  if (resolveError || typeof resolved !== "string") {
    await admin.auth.admin.deleteUser(candidateUser.id).catch(() => undefined);
    console.error("Could not persist OAuth identity mapping", resolveError);
    throw new EdgeError(
      503,
      "identity_creation_failed",
      "Authentication identity cannot be persisted",
    );
  }
  if (resolved !== candidateUser.id) {
    const { error: orphanError } = await admin.auth.admin.deleteUser(
      candidateUser.id,
    );
    if (orphanError) {
      console.error(
        "Could not remove raced provisional OAuth user",
        orphanError,
      );
    }
  }
  return resolved;
}

async function issueSession(
  admin: SupabaseClient,
  userId: string,
): Promise<{
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  tokenType: string;
  user: User;
}> {
  const { data: userData, error: userError } = await admin.auth.admin
    .getUserById(userId);
  const email = userData.user?.email;
  if (userError || !userData.user || !email) {
    console.error("OAuth mapped user is unavailable", userError);
    throw new EdgeError(
      409,
      "identity_unavailable",
      "Authentication identity is unavailable",
    );
  }
  const { data, error } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  const properties = data?.properties as
    | { hashed_token?: string; hashedToken?: string }
    | undefined;
  const hashedToken = properties?.hashed_token ?? properties?.hashedToken;
  if (error || !hashedToken) {
    console.error("Could not issue OAuth exchange session", error);
    throw new EdgeError(
      503,
      "session_issue_failed",
      "Authentication session cannot be issued",
    );
  }

  const supabaseUrl = requiredEnv("SUPABASE_URL");
  const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const response = await fetchWithTimeout(
    `${supabaseUrl}/auth/v1/verify`,
    {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        type: "magiclink",
        token_hash: hashedToken,
      }),
    },
    8_000,
  );
  const payload = await readJsonResponse(response, 64 * 1024);
  if (
    !response.ok ||
    !payload.access_token ||
    !payload.refresh_token
  ) {
    console.error("Supabase rejected internal OAuth exchange", response.status);
    throw new EdgeError(
      503,
      "session_issue_failed",
      "Authentication session cannot be issued",
    );
  }
  return {
    accessToken: String(payload.access_token),
    refreshToken: String(payload.refresh_token),
    expiresIn: Number(payload.expires_in ?? 3600),
    tokenType: String(payload.token_type ?? "bearer"),
    user: userData.user,
  };
}

function sanitizeProfile(profile: ExternalProfile): ExternalProfile {
  const subject = normalizeOAuthSubject(profile.subject);
  if (!subject) {
    throw new EdgeError(
      400,
      "invalid_provider_identity",
      "Identity provider returned an invalid subject",
    );
  }
  return {
    subject,
    username: cleanText(profile.username, 100),
    fullName: cleanText(profile.fullName, 200),
    avatarUrl: safeAvatarUrl(profile.avatarUrl),
  };
}

function cleanText(value: string, limit: number): string {
  return String(value ?? "")
    .replace(/[\u0000-\u001f\u007f]/g, "")
    .trim()
    .slice(0, limit);
}

function safeAvatarUrl(value: string): string {
  if (!value) return "";
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password) return "";
    url.hash = "";
    return url.toString().slice(0, 2_000);
  } catch {
    return "";
  }
}
