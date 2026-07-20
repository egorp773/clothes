import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  parsePushClaimResponse,
  takeBoundedPushTokens,
} from "./push_security.ts";

const attemptId = "00000000-0000-4000-8000-000000000001";
const recipientId = "00000000-0000-4000-8000-000000000002";

Deno.test("push claim parser remains compatible with UUID/null responses", () => {
  assertEquals(parsePushClaimResponse(attemptId), {
    attemptId,
    skipped: null,
    retryAfterSeconds: null,
  });
  assertEquals(parsePushClaimResponse(null), {
    attemptId: null,
    skipped: "already_claimed",
    retryAfterSeconds: null,
  });
});

Deno.test("push claim parser supports an explicit retry claim and backoff", () => {
  assertEquals(
    parsePushClaimResponse({
      attempt_id: attemptId,
      disposition: "retry_claimed",
      claimed: true,
    }),
    { attemptId, skipped: null, retryAfterSeconds: null },
  );
  assertEquals(
    parsePushClaimResponse({
      disposition: "retry_later",
      retry_after_seconds: 12.2,
    }),
    { attemptId: null, skipped: "retry_later", retryAfterSeconds: 13 },
  );
  assertEquals(
    parsePushClaimResponse({ status: "processing", attempt_id: attemptId }),
    {
      attemptId: null,
      skipped: "already_claimed",
      retryAfterSeconds: null,
    },
  );
  assertThrows(() => parsePushClaimResponse({ status: "unknown" }), Error);
});

Deno.test("push token selection deduplicates, validates and bounds devices", () => {
  const validA = `token-a:${"x".repeat(20)}`;
  const validB = `token-b:${"y".repeat(20)}`;
  const validC = `token-c:${"z".repeat(20)}`;
  assertEquals(
    takeBoundedPushTokens(
      recipientId,
      [
        { user_id: recipientId, token: validA },
        { user_id: recipientId, token: validA },
        { user_id: recipientId, token: "contains whitespace" },
        { user_id: "00000000-0000-4000-8000-000000000003", token: validB },
        { user_id: recipientId, token: validB },
        { user_id: recipientId, token: validC },
      ],
      2,
    ),
    [
      { user_id: recipientId, token: validA },
      { user_id: recipientId, token: validB },
    ],
  );
});
