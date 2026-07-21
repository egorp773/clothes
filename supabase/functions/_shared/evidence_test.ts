import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  assertEvidenceObjectPath,
  detectEvidenceImageMime,
} from "./evidence.ts";

Deno.test("detects evidence image magic bytes", () => {
  assertEquals(
    detectEvidenceImageMime(new Uint8Array([0xff, 0xd8, 0xff, 0x00])),
    "image/jpeg",
  );
  assertEquals(
    detectEvidenceImageMime(
      new Uint8Array([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]),
    ),
    "image/png",
  );
  assertThrows(() => detectEvidenceImageMime(new Uint8Array([1, 2, 3])));
});

Deno.test("evidence path is bound to actor and dispute", () => {
  const user = "10000000-0000-4000-8000-000000000001";
  const dispute = "20000000-0000-4000-8000-000000000001";
  assertEquals(
    assertEvidenceObjectPath(`${user}/${dispute}/hash.jpg`, user, dispute),
    `${user}/${dispute}/hash.jpg`,
  );
  assertThrows(() =>
    assertEvidenceObjectPath(
      `30000000-0000-4000-8000-000000000001/${dispute}/hash.jpg`,
      user,
      dispute,
    )
  );
});
