import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  accessoryImageBucket,
  canonicalAccessoryStoragePath,
} from "./accessory_storage.ts";
import { EdgeError } from "./edge.ts";

const ownerId = "10000000-0000-4000-8000-000000000001";
const accessoryId = "20000000-0000-4000-8000-000000000002";
const canonicalPath = `${ownerId}/${accessoryId}/original.jpg`;

Deno.test("accessory storage accepts only the owner/accessory namespace", () => {
  assertEquals(accessoryImageBucket, "accessory-images");
  assertEquals(
    canonicalAccessoryStoragePath(
      canonicalPath,
      "https://project.supabase.co",
      ownerId,
      accessoryId,
    ),
    canonicalPath,
  );
  assertEquals(
    canonicalAccessoryStoragePath(
      `storage://accessory-images/${canonicalPath}`,
      "https://project.supabase.co",
      ownerId,
      accessoryId,
    ),
    canonicalPath,
  );
});

Deno.test("accessory storage accepts project private-object URLs", () => {
  assertEquals(
    canonicalAccessoryStoragePath(
      `https://project.supabase.co/storage/v1/object/sign/accessory-images/${canonicalPath}?token=short-lived`,
      "https://project.supabase.co",
      ownerId,
      accessoryId,
    ),
    canonicalPath,
  );
});

Deno.test("accessory storage rejects legacy buckets and another accessory", () => {
  for (
    const value of [
      `https://project.supabase.co/storage/v1/object/public/product-images/accessories/${ownerId}/old.jpg`,
      `${ownerId}/30000000-0000-4000-8000-000000000003/other.jpg`,
    ]
  ) {
    const error = assertThrows(
      () =>
        canonicalAccessoryStoragePath(
          value,
          "https://project.supabase.co",
          ownerId,
          accessoryId,
        ),
      EdgeError,
    );
    assertEquals(
      ["invalid_accessory_image", "invalid_accessory_image_owner"].includes(
        error.code,
      ),
      true,
    );
  }
});
