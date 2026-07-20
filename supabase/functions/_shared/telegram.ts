import { constantTimeEqual, EdgeError } from "./edge.ts";

export async function verifyTelegramLogin(
  parameters: URLSearchParams,
  botToken: string,
  {
    nowSeconds = Math.floor(Date.now() / 1000),
    maxAgeSeconds = 300,
  }: {
    nowSeconds?: number;
    maxAgeSeconds?: number;
  } = {},
): Promise<void> {
  const hash = parameters.get("hash")?.toLowerCase() ?? "";
  const subject = parameters.get("id") ?? "";
  const authDate = Number(parameters.get("auth_date"));
  if (
    !/^[a-f0-9]{64}$/.test(hash) ||
    !/^\d{1,32}$/.test(subject) ||
    !Number.isSafeInteger(authDate)
  ) {
    throw new EdgeError(
      400,
      "invalid_provider_payload",
      "Telegram payload is incomplete",
    );
  }
  const boundedMaxAge = Number.isFinite(maxAgeSeconds)
    ? Math.max(60, Math.min(maxAgeSeconds, 600))
    : 300;
  if (authDate > nowSeconds + 30 || nowSeconds - authDate > boundedMaxAge) {
    throw new EdgeError(
      400,
      "provider_payload_expired",
      "Telegram payload is expired",
    );
  }

  const dataCheckString = [...parameters.entries()]
    .filter(([key]) => key !== "hash" && key !== "state")
    .sort(([left], [right]) => left.localeCompare(right))
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
  const expected = [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  if (!constantTimeEqual(expected, hash)) {
    throw new EdgeError(
      400,
      "invalid_provider_signature",
      "Telegram signature is invalid",
    );
  }
}
