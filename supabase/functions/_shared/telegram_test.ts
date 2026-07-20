import { assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";

import { verifyTelegramLogin } from "./telegram.ts";

const botToken = "123456789:abcdefghijklmnopqrstuvwxyz0123456789";

Deno.test("Telegram payload signature is valid only once within a short age", async () => {
  const now = 1_800_000_000;
  const params = new URLSearchParams({
    id: "123456789",
    first_name: "Test",
    auth_date: String(now - 10),
    state: "edge-owned-state",
  });
  params.set("hash", await telegramHash(params, botToken));
  await verifyTelegramLogin(params, botToken, {
    nowSeconds: now,
    maxAgeSeconds: 300,
  });

  await assertRejects(
    () =>
      verifyTelegramLogin(params, botToken, {
        nowSeconds: now + 301,
        maxAgeSeconds: 300,
      }),
    Error,
    "expired",
  );
});

Deno.test("Telegram signature excludes only Edge state, not provider fields", async () => {
  const now = 1_800_000_000;
  const params = new URLSearchParams({
    id: "123456789",
    first_name: "Test",
    auth_date: String(now),
    state: "edge-owned-state",
  });
  params.set("hash", await telegramHash(params, botToken));
  params.set("first_name", "Attacker");
  await assertRejects(
    () => verifyTelegramLogin(params, botToken, { nowSeconds: now }),
    Error,
    "signature",
  );
});

Deno.test("Telegram age check fails closed when configured age is not numeric", async () => {
  const now = 1_800_000_000;
  const params = new URLSearchParams({
    id: "123456789",
    auth_date: String(now - 301),
    state: "edge-owned-state",
  });
  params.set("hash", await telegramHash(params, botToken));
  await assertRejects(
    () =>
      verifyTelegramLogin(params, botToken, {
        nowSeconds: now,
        maxAgeSeconds: Number.NaN,
      }),
    Error,
    "expired",
  );
});

async function telegramHash(
  params: URLSearchParams,
  token: string,
): Promise<string> {
  const dataCheckString = [...params.entries()]
    .filter(([key]) => key !== "hash" && key !== "state")
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");
  const secret = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    secret,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(dataCheckString),
  );
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
