const textEncoder = new TextEncoder();

export class EdgeError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "EdgeError";
    this.status = status;
    this.code = code;
  }
}

export function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) {
    throw new EdgeError(
      500,
      "server_misconfigured",
      `${name} is not configured`,
    );
  }
  return value;
}

export function jsonResponse(
  body: unknown,
  status = 200,
  headers: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": "application/json; charset=utf-8",
      ...headers,
    },
  });
}

export function errorResponse(
  error: unknown,
  requestId = crypto.randomUUID(),
  headers: HeadersInit = {},
): Response {
  if (error instanceof EdgeError) {
    return jsonResponse(
      {
        code: error.code,
        message: error.message,
        request_id: requestId,
      },
      error.status,
      headers,
    );
  }
  console.error(`[edge:${requestId}] unexpected failure`, error);
  return jsonResponse(
    {
      code: "internal_error",
      message: "The request could not be completed",
      request_id: requestId,
    },
    500,
    headers,
  );
}

export async function readJsonObject(
  request: Request,
  maxBytes = 32 * 1024,
): Promise<Record<string, unknown>> {
  const advertised = Number(request.headers.get("content-length") ?? 0);
  if (Number.isFinite(advertised) && advertised > maxBytes) {
    throw new EdgeError(413, "request_too_large", "Request body is too large");
  }
  const bytes = await readLimitedBody(request.body, maxBytes);
  try {
    const parsed = JSON.parse(new TextDecoder().decode(bytes));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("not an object");
    }
    return parsed as Record<string, unknown>;
  } catch {
    throw new EdgeError(
      400,
      "invalid_json",
      "Request body must be a JSON object",
    );
  }
}

export async function readLimitedBody(
  body: ReadableStream<Uint8Array> | null,
  maxBytes: number,
): Promise<Uint8Array> {
  if (!body) return new Uint8Array();
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maxBytes) {
        await reader.cancel("body limit exceeded").catch(() => undefined);
        throw new EdgeError(
          413,
          "response_too_large",
          "Response body is too large",
        );
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const result = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

export function bearerToken(request: Request): string {
  const authorization = request.headers.get("Authorization") ?? "";
  const match = authorization.match(/^Bearer\s+([^\s]+)$/i);
  if (!match) {
    throw new EdgeError(
      401,
      "authentication_required",
      "Authentication required",
    );
  }
  return match[1];
}

export function randomBase64Url(byteLength = 32): string {
  if (!Number.isInteger(byteLength) || byteLength < 16 || byteLength > 128) {
    throw new EdgeError(
      500,
      "invalid_random_length",
      "Invalid random token length",
    );
  }
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return base64Url(bytes);
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    textEncoder.encode(value),
  );
  return hex(new Uint8Array(digest));
}

export async function sha256BytesHex(value: Uint8Array): Promise<string> {
  // Copy into an ArrayBuffer-backed view. TypeScript 6 correctly models an
  // arbitrary Uint8Array as potentially SharedArrayBuffer-backed, while Web
  // Crypto only accepts an ordinary BufferSource.
  const bytes = Uint8Array.from(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return hex(new Uint8Array(digest));
}

function hex(bytes: Uint8Array): string {
  return [...bytes]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function sha256Base64Url(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    textEncoder.encode(value),
  );
  return base64Url(new Uint8Array(digest));
}

export function constantTimeEqual(left: string, right: string): boolean {
  const a = textEncoder.encode(left);
  const b = textEncoder.encode(right);
  const length = Math.max(a.length, b.length);
  let difference = a.length ^ b.length;
  for (let index = 0; index < length; index++) {
    difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return difference === 0;
}

export function assertPkceChallenge(value: unknown): string {
  const challenge = String(value ?? "");
  if (!/^[A-Za-z0-9_-]{43,128}$/.test(challenge)) {
    throw new EdgeError(
      400,
      "invalid_code_challenge",
      "A valid S256 code_challenge is required",
    );
  }
  return challenge;
}

export function assertPkceVerifier(value: unknown): string {
  const verifier = String(value ?? "");
  if (!/^[A-Za-z0-9._~-]{43,128}$/.test(verifier)) {
    throw new EdgeError(
      400,
      "invalid_code_verifier",
      "A valid PKCE code_verifier is required",
    );
  }
  return verifier;
}

export function exactRedirect(value: string | null): string {
  const configured = configuredRedirects();
  const candidate = value?.trim() || defaultRedirect(configured);
  const normalized = normalizeRedirect(candidate);
  if (!configured.includes(normalized)) {
    throw new EdgeError(
      400,
      "redirect_not_allowed",
      "The callback URI is not allowlisted",
    );
  }
  return normalized;
}

export function configuredRedirects(): string[] {
  const values = (Deno.env.get("OAUTH_ALLOWED_REDIRECT_URIS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean)
    .map(normalizeRedirect);
  const unique = [...new Set(values)];
  if (unique.length === 0) {
    throw new EdgeError(
      500,
      "server_misconfigured",
      "OAUTH_ALLOWED_REDIRECT_URIS is not configured",
    );
  }
  return unique;
}

function defaultRedirect(configured: string[]): string {
  const explicit = Deno.env.get("OAUTH_DEFAULT_REDIRECT_URI")?.trim();
  if (!explicit) return configured[0];
  const normalized = normalizeRedirect(explicit);
  if (!configured.includes(normalized)) {
    throw new EdgeError(
      500,
      "server_misconfigured",
      "OAUTH_DEFAULT_REDIRECT_URI is not allowlisted",
    );
  }
  return normalized;
}

export function normalizeRedirect(value: string): string {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new EdgeError(400, "invalid_redirect", "The callback URI is invalid");
  }
  if (url.username || url.password || url.hash) {
    throw new EdgeError(
      400,
      "invalid_redirect",
      "The callback URI must not contain credentials or a fragment",
    );
  }
  if (url.protocol === "http:") {
    if (!["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)) {
      throw new EdgeError(
        400,
        "invalid_redirect",
        "Insecure callback URIs are limited to loopback development",
      );
    }
  } else if (url.protocol !== "https:") {
    if (
      !/^[a-z][a-z0-9+.-]*:$/.test(url.protocol) || !url.protocol.includes(".")
    ) {
      throw new EdgeError(
        400,
        "invalid_redirect",
        "The callback URI scheme is not allowed",
      );
    }
  }
  return url.toString();
}

export function redirectWithParams(
  redirectUri: string,
  parameters: Record<string, string>,
): Response {
  const target = new URL(redirectUri);
  target.hash = "";
  for (const [key, value] of Object.entries(parameters)) {
    target.searchParams.set(key, value);
  }
  if (target.protocol === "http:" || target.protocol === "https:") {
    return new Response(null, {
      status: 303,
      headers: {
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
        Location: target.toString(),
      },
    });
  }
  const appUrl = target.toString();
  return new Response(
    `<!doctype html><html><head><meta charset="utf-8"><meta name="referrer" content="no-referrer">` +
      `<meta http-equiv="Cache-Control" content="no-store">` +
      `<title>Return to application</title></head><body>` +
      `<p>Authentication finished. Return to the application.</p>` +
      `<a rel="noreferrer" href="${escapeHtml(appUrl)}">Open application</a>` +
      `<script>window.location.replace(${JSON.stringify(appUrl)});</script>` +
      `</body></html>`,
    {
      status: 200,
      headers: {
        "Cache-Control": "no-store",
        "Content-Security-Policy":
          "default-src 'none'; script-src 'unsafe-inline'; style-src 'none'; base-uri 'none'; frame-ancestors 'none'",
        "Content-Type": "text/html; charset=utf-8",
        "Referrer-Policy": "no-referrer",
        "X-Content-Type-Options": "nosniff",
      },
    },
  );
}

export function requestMetadata(request: Request): {
  ip: string | null;
  userAgent: string;
} {
  const candidates = [
    request.headers.get("cf-connecting-ip"),
    request.headers.get("x-real-ip"),
    (request.headers.get("x-forwarded-for") ?? "").split(",").at(-1)?.trim(),
  ];
  const ip = candidates.find((value) => value && isIpLiteral(value)) ?? null;
  const userAgent = (request.headers.get("user-agent") ?? "unknown")
    .replace(/[\u0000-\u001f\u007f]/g, "")
    .slice(0, 512);
  return { ip, userAgent };
}

export function strictCorsHeaders(
  request: Request,
  envName = "EDGE_ALLOWED_WEB_ORIGINS",
): Record<string, string> {
  const origin = request.headers.get("Origin");
  const base = {
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };
  if (!origin) return base;
  const allowed = new Set(
    (Deno.env.get(envName) ?? "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
  );
  if (!allowed.has(origin)) {
    throw new EdgeError(403, "origin_not_allowed", "Origin is not allowed");
  }
  return { ...base, "Access-Control-Allow-Origin": origin };
}

export async function fetchWithTimeout(
  input: string | URL,
  init: RequestInit = {},
  timeoutMs = 8_000,
): Promise<Response> {
  if (timeoutMs < 100 || timeoutMs > 30_000) {
    throw new EdgeError(500, "invalid_timeout", "Invalid upstream timeout");
  }
  try {
    return await fetch(input, {
      ...init,
      redirect: init.redirect ?? "error",
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    if (error instanceof EdgeError) throw error;
    throw new EdgeError(
      502,
      "upstream_unavailable",
      "Identity provider unavailable",
    );
  }
}

export async function readJsonResponse(
  response: Response,
  maxBytes = 128 * 1024,
): Promise<Record<string, unknown>> {
  const bytes = await readLimitedBody(response.body, maxBytes);
  try {
    const value = JSON.parse(new TextDecoder().decode(bytes));
    return value && typeof value === "object" && !Array.isArray(value)
      ? value as Record<string, unknown>
      : {};
  } catch {
    return {};
  }
}

export function safeErrorCode(value: string | null | undefined): string {
  const normalized = String(value ?? "authentication_failed")
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 64);
  return normalized || "authentication_failed";
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function isIpLiteral(value: string): boolean {
  const candidate = value.trim().replace(/^\[|\]$/g, "");
  if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(candidate)) {
    return candidate.split(".").every((part) => Number(part) <= 255);
  }
  return candidate.includes(":") && /^[0-9a-f:.]+$/i.test(candidate);
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
