import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  assertPkceChallenge,
  exactRedirect,
  normalizeRedirect,
  sha256Base64Url,
} from "./edge.ts";

Deno.test("strict redirect allowlist rejects an arbitrary HTTPS origin", {
  permissions: { env: true },
}, () => {
  const previous = Deno.env.get("OAUTH_ALLOWED_REDIRECT_URIS");
  try {
    Deno.env.set(
      "OAUTH_ALLOWED_REDIRECT_URIS",
      "com.example.clothes://login-callback/,https://app.example.ru/oauth",
    );
    assertEquals(
      exactRedirect("https://app.example.ru/oauth"),
      "https://app.example.ru/oauth",
    );
    assertThrows(
      () => exactRedirect("https://attacker.example/oauth"),
      Error,
      "not allowlisted",
    );
  } finally {
    if (previous === undefined) {
      Deno.env.delete("OAUTH_ALLOWED_REDIRECT_URIS");
    } else {
      Deno.env.set("OAUTH_ALLOWED_REDIRECT_URIS", previous);
    }
  }
});

Deno.test("redirect URI rejects credentials, fragments, and non-loopback HTTP", () => {
  for (
    const value of [
      "https://user:pass@app.example.ru/oauth",
      "https://app.example.ru/oauth#token",
      "http://app.example.ru/oauth",
    ]
  ) {
    assertThrows(() => normalizeRedirect(value));
  }
});

Deno.test("application PKCE requires S256 challenge", async () => {
  const verifier = "v".repeat(64);
  const challenge = await sha256Base64Url(verifier);
  assertEquals(assertPkceChallenge(challenge), challenge);
  assertThrows(() => assertPkceChallenge("short"));
});
