import { EdgeError } from "./edge.ts";

export const maxDisputeImageBytes = 20 * 1024 * 1024;

export function detectEvidenceImageMime(bytes: Uint8Array): string {
  if (
    bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  ) {
    return "image/jpeg";
  }
  if (
    bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47 && bytes[4] === 0x0d &&
    bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  ) {
    return "image/png";
  }
  if (
    bytes.length >= 12 && ascii(bytes, 0, 4) === "RIFF" &&
    ascii(bytes, 8, 12) === "WEBP"
  ) {
    return "image/webp";
  }
  throw new EdgeError(
    415,
    "unsupported_evidence_media",
    "Evidence must be a JPEG, PNG or WebP image",
  );
}

export function assertEvidenceObjectPath(
  path: unknown,
  userId: string,
  disputeId: string,
): string {
  const value = String(path ?? "").trim().toLowerCase();
  const escapedUser = escapeRegex(userId.toLowerCase());
  const escapedDispute = escapeRegex(disputeId.toLowerCase());
  if (!new RegExp(`^${escapedUser}/${escapedDispute}/[^/]{1,200}$`).test(value)) {
    throw new EdgeError(
      400,
      "invalid_evidence_path",
      "Evidence object path is outside the dispute namespace",
    );
  }
  return value;
}

function ascii(bytes: Uint8Array, from: number, to: number): string {
  return String.fromCharCode(...bytes.slice(from, to));
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
