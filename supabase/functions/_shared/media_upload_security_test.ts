import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";

import { EdgeError } from "./edge.ts";
import {
  maxMediaUploadBytes,
  parseMediaUploadTarget,
} from "./media_upload_security.ts";

const userId = "11111111-1111-4111-8111-111111111111";
const resourceId = "22222222-2222-4222-8222-222222222222";

Deno.test("media upload validation accepts every canonical resource namespace", () => {
  const cases: Array<{
    bucket:
      | "profile-images"
      | "chat-media"
      | "listing-drafts"
      | "outfit-images"
      | "accessory-images"
      | "dispute-evidence";
    objectPath: string;
    resourceId: string;
    contentType?: string;
  }> = [
    {
      bucket: "profile-images",
      objectPath: `${userId}/avatar/image.jpg`,
      resourceId: userId,
    },
    {
      bucket: "chat-media",
      objectPath: `threads/direct_${resourceId}/${userId}/image.gif`,
      resourceId: `direct_${resourceId}`,
      contentType: "image/gif",
    },
    {
      bucket: "listing-drafts",
      objectPath: `${userId}/${resourceId}/image.webp`,
      resourceId,
      contentType: "image/webp",
    },
    {
      bucket: "outfit-images",
      objectPath: `${userId}/${resourceId}/image.png`,
      resourceId,
      contentType: "image/png",
    },
    {
      bucket: "accessory-images",
      objectPath: `${userId}/${resourceId}/image.jpeg`,
      resourceId,
    },
    {
      bucket: "dispute-evidence",
      objectPath: `${userId}/${resourceId}/${"a".repeat(64)}.jpg`,
      resourceId,
    },
  ];

  for (const testCase of cases) {
    const target = parseMediaUploadTarget(
      {
        bucket: testCase.bucket,
        object_path: testCase.objectPath,
        content_type: testCase.contentType ?? "image/jpeg",
        size_bytes: 1024,
      },
      userId,
    );
    assertEquals(target.resourceId, testCase.resourceId);
    assertEquals(target.objectPath, testCase.objectPath);
  }
});

Deno.test("media upload validation rejects another user's namespace", () => {
  const error = assertThrows(
    () =>
      parseMediaUploadTarget(
        {
          bucket: "listing-drafts",
          object_path:
            `33333333-3333-4333-8333-333333333333/${resourceId}/image.jpg`,
          content_type: "image/jpeg",
          size_bytes: 1024,
        },
        userId,
      ),
    EdgeError,
  );
  assertEquals(error.code, "invalid_object_path");
});

Deno.test("media upload validation rejects traversal and MIME spoofing", () => {
  for (
    const objectPath of [
      `${userId}/${resourceId}/../image.jpg`,
      `${userId}/${resourceId}/image.png`,
    ]
  ) {
    const error = assertThrows(
      () =>
        parseMediaUploadTarget(
          {
            bucket: "listing-drafts",
            object_path: objectPath,
            content_type: "image/jpeg",
            size_bytes: 1024,
          },
          userId,
        ),
      EdgeError,
    );
    assertEquals(error.code, "invalid_object_path");
  }
});

Deno.test("media upload validation applies per-bucket limits", () => {
  const error = assertThrows(
    () =>
      parseMediaUploadTarget(
        {
          bucket: "profile-images",
          object_path: `${userId}/avatar/image.jpg`,
          content_type: "image/jpeg",
          size_bytes: maxMediaUploadBytes("profile-images") + 1,
        },
        userId,
      ),
    EdgeError,
  );
  assertEquals(error.status, 413);
  assertEquals(error.code, "media_too_large");
});

Deno.test("dispute evidence requires a content-addressed filename", () => {
  const error = assertThrows(
    () =>
      parseMediaUploadTarget(
        {
          bucket: "dispute-evidence",
          object_path: `${userId}/${resourceId}/random.jpg`,
          content_type: "image/jpeg",
          size_bytes: 1024,
        },
        userId,
      ),
    EdgeError,
  );
  assertEquals(error.code, "invalid_object_path");
});
