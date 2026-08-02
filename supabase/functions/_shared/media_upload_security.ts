import { EdgeError } from "./edge.ts";

export const mediaUploadBuckets = [
  "profile-images",
  "chat-media",
  "listing-drafts",
  "outfit-images",
  "accessory-images",
  "dispute-evidence",
] as const;

export type MediaUploadBucket = typeof mediaUploadBuckets[number];

export type MediaUploadTarget = {
  bucket: MediaUploadBucket;
  objectPath: string;
  contentType: string;
  sizeBytes: number;
  resourceId: string;
};

type BucketRule = {
  maxBytes: number;
  mimeTypes: ReadonlySet<string>;
};

const stillImageMimeTypes = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
]);

const bucketRules: Record<MediaUploadBucket, BucketRule> = {
  "profile-images": {
    maxBytes: 10 * 1024 * 1024,
    mimeTypes: stillImageMimeTypes,
  },
  "chat-media": {
    maxBytes: 20 * 1024 * 1024,
    mimeTypes: new Set([...stillImageMimeTypes, "image/gif"]),
  },
  "listing-drafts": {
    maxBytes: 15 * 1024 * 1024,
    mimeTypes: stillImageMimeTypes,
  },
  "outfit-images": {
    maxBytes: 15 * 1024 * 1024,
    mimeTypes: stillImageMimeTypes,
  },
  "accessory-images": {
    maxBytes: 15 * 1024 * 1024,
    mimeTypes: stillImageMimeTypes,
  },
  "dispute-evidence": {
    maxBytes: 20 * 1024 * 1024,
    mimeTypes: stillImageMimeTypes,
  },
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const threadIdPattern = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$/;
const fileNamePattern =
  /^[A-Za-z0-9][A-Za-z0-9._-]{0,179}\.(?:jpe?g|png|webp|gif)$/i;

export function parseMediaUploadTarget(
  body: Record<string, unknown>,
  authenticatedUserId: string,
): MediaUploadTarget {
  const userId = validateUuid(authenticatedUserId, "user_id");
  const bucket = validateBucket(body.bucket);
  const objectPath = exactString(body.object_path, "object_path", 512);
  const contentType = exactString(body.content_type, "content_type", 64)
    .toLowerCase();
  const sizeBytes = validateSize(body.size_bytes, bucketRules[bucket].maxBytes);

  if (!bucketRules[bucket].mimeTypes.has(contentType)) {
    throw new EdgeError(
      415,
      "unsupported_media_type",
      "The requested media type is not allowed for this bucket",
    );
  }

  const segments = objectPath.split("/");
  if (segments.some((part) => !part || part === "." || part === "..")) {
    throw invalidPath();
  }

  let resourceId: string;
  switch (bucket) {
    case "profile-images":
      if (
        segments.length !== 3 ||
        segments[0] !== userId ||
        segments[1] !== "avatar"
      ) {
        throw invalidPath();
      }
      resourceId = userId;
      break;
    case "chat-media":
      if (
        segments.length !== 4 ||
        segments[0] !== "threads" ||
        !threadIdPattern.test(segments[1]) ||
        segments[2] !== userId
      ) {
        throw invalidPath();
      }
      resourceId = segments[1];
      break;
    default:
      if (segments.length !== 3 || segments[0] !== userId) {
        throw invalidPath();
      }
      resourceId = validateUuid(segments[1], "resource_id");
  }

  const fileName = segments.at(-1) ?? "";
  if (
    !fileNamePattern.test(fileName) ||
    fileName.includes("..") ||
    !extensionMatchesMime(fileName, contentType)
  ) {
    throw invalidPath();
  }
  if (
    bucket === "dispute-evidence" &&
    !/^[0-9a-f]{64}\.(?:jpe?g|png|webp)$/.test(fileName)
  ) {
    throw new EdgeError(
      400,
      "invalid_object_path",
      "Dispute evidence must use its lowercase SHA-256 as the filename",
    );
  }

  return { bucket, objectPath, contentType, sizeBytes, resourceId };
}

export function maxMediaUploadBytes(bucket: MediaUploadBucket): number {
  return bucketRules[bucket].maxBytes;
}

function validateBucket(value: unknown): MediaUploadBucket {
  const bucket = exactString(value, "bucket", 64);
  if (!(mediaUploadBuckets as readonly string[]).includes(bucket)) {
    throw new EdgeError(
      400,
      "unsupported_bucket",
      "The requested upload bucket is not supported",
    );
  }
  return bucket as MediaUploadBucket;
}

function validateSize(value: unknown, maxBytes: number): number {
  if (!Number.isSafeInteger(value) || Number(value) < 1) {
    throw new EdgeError(
      400,
      "invalid_size_bytes",
      "size_bytes must be a positive integer",
    );
  }
  const sizeBytes = Number(value);
  if (sizeBytes > maxBytes) {
    throw new EdgeError(
      413,
      "media_too_large",
      "The requested media file is too large",
    );
  }
  return sizeBytes;
}

function validateUuid(value: unknown, field: string): string {
  const uuid = exactString(value, field, 36).toLowerCase();
  if (!uuidPattern.test(uuid)) {
    throw new EdgeError(400, `invalid_${field}`, `${field} must be a UUID`);
  }
  return uuid;
}

function exactString(value: unknown, field: string, maxLength: number): string {
  if (
    typeof value !== "string" || value.length < 1 || value.length > maxLength
  ) {
    throw new EdgeError(400, `invalid_${field}`, `${field} is invalid`);
  }
  const trimmed = value.trim();
  if (trimmed !== value || /[\u0000-\u001f\u007f\\]/.test(value)) {
    throw new EdgeError(400, `invalid_${field}`, `${field} is invalid`);
  }
  return value;
}

function extensionMatchesMime(fileName: string, contentType: string): boolean {
  const extension = fileName.split(".").at(-1)?.toLowerCase();
  switch (contentType) {
    case "image/jpeg":
      return extension === "jpg" || extension === "jpeg";
    case "image/png":
      return extension === "png";
    case "image/webp":
      return extension === "webp";
    case "image/gif":
      return extension === "gif";
    default:
      return false;
  }
}

function invalidPath(): EdgeError {
  return new EdgeError(
    400,
    "invalid_object_path",
    "object_path is not a canonical path for this upload bucket",
  );
}
