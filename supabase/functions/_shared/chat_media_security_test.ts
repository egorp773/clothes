import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  isMissingChatMembersRelation,
  validateOwnedChatMediaPath,
} from "./chat_media_security.ts";

const userId = "00000000-0000-4000-8000-000000000001";

Deno.test("chat-media cleanup accepts only the authenticated owner namespace", () => {
  assertEquals(
    validateOwnedChatMediaPath(
      "direct-a-b",
      `threads/direct-a-b/${userId}/asset-1.jpg`,
      userId,
    ),
    {
      threadId: "direct-a-b",
      ownerId: userId,
      objectName: "asset-1.jpg",
      storagePath: `threads/direct-a-b/${userId}/asset-1.jpg`,
    },
  );
});

Deno.test("chat-media cleanup rejects another user's object and path traversal", () => {
  const otherUserId = "00000000-0000-4000-8000-000000000002";
  assertThrows(
    () =>
      validateOwnedChatMediaPath(
        "direct-a-b",
        `threads/direct-a-b/${otherUserId}/asset.jpg`,
        userId,
      ),
    Error,
    "owned chat-media object",
  );
  assertThrows(
    () =>
      validateOwnedChatMediaPath(
        "direct-a-b",
        `threads/direct-a-b/${userId}/../asset.jpg`,
        userId,
      ),
  );
  assertThrows(
    () =>
      validateOwnedChatMediaPath(
        "direct-a-b",
        `threads/another-thread/${userId}/asset.jpg`,
        userId,
      ),
  );
});

Deno.test("canonical membership fallback is limited to a missing relation", () => {
  assertEquals(isMissingChatMembersRelation({ code: "42P01" }), true);
  assertEquals(isMissingChatMembersRelation({ code: "PGRST205" }), true);
  assertEquals(
    isMissingChatMembersRelation({
      code: "PGRST204",
      message: "column left_at is not in the schema cache",
    }),
    false,
  );
  assertEquals(isMissingChatMembersRelation({ code: "42501" }), false);
});
