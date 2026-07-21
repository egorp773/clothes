import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  isTrustedProvisionalOAuthCandidate,
  normalizeOAuthSubject,
} from "./oauth_identity.ts";

Deno.test("provider subject accepts opaque and composite VK identifiers", () => {
  assertEquals(normalizeOAuthSubject("123456789"), "123456789");
  assertEquals(
    normalizeOAuthSubject("vk:mailru|b8f67c90-31a2-4d89-a955/tenant=1"),
    "vk:mailru|b8f67c90-31a2-4d89-a955/tenant=1",
  );
  assertEquals(normalizeOAuthSubject("subject with spaces"), null);
  assertEquals(normalizeOAuthSubject(`subject\ninjection`), null);
  assertEquals(normalizeOAuthSubject("x".repeat(501)), null);
});

Deno.test("pre-created Auth account cannot be bound to an OAuth subject", () => {
  const attackerControlledAccount = {
    app_metadata: { provider: "email", providers: ["email"] },
    user_metadata: {
      provider: "vk",
      provider_subject: "vk:123456",
    },
  };

  assertEquals(
    isTrustedProvisionalOAuthCandidate(
      attackerControlledAccount,
      "vk",
      "vk:123456",
    ),
    false,
  );
});

Deno.test("only exact service-controlled provisional binding is trusted", () => {
  const candidate = {
    app_metadata: {
      registration_status: "provisional",
      oauth_provider: "vk",
      oauth_provider_subject: "vk:123456",
    },
    user_metadata: {
      provider: "vk",
      provider_subject: "vk:123456",
    },
  };

  assertEquals(
    isTrustedProvisionalOAuthCandidate(candidate, "vk", "vk:123456"),
    true,
  );
  assertEquals(
    isTrustedProvisionalOAuthCandidate(candidate, "vk", "vk:other"),
    false,
  );
  assertEquals(
    isTrustedProvisionalOAuthCandidate(candidate, "yandex", "vk:123456"),
    false,
  );
});
