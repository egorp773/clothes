import { EdgeError } from "./edge.ts";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type PushClaimDecision = {
  attemptId: string | null;
  skipped: "already_claimed" | "retry_later" | null;
  retryAfterSeconds: number | null;
};

export type PushTokenCandidate = {
  user_id: string;
  token: string;
};

/**
 * Accept the legacy UUID/null RPC response and the structured response used by
 * retry-aware claim implementations. A structured response must explicitly
 * tell this caller that it owns delivery; seeing a processing row is not enough
 * to safely send a second push.
 */
export function parsePushClaimResponse(value: unknown): PushClaimDecision {
  if (value === null || value === undefined) {
    return {
      attemptId: null,
      skipped: "already_claimed",
      retryAfterSeconds: null,
    };
  }
  if (typeof value === "string") {
    if (!isUuid(value)) throw invalidClaimResponse();
    return { attemptId: value, skipped: null, retryAfterSeconds: null };
  }
  if (Array.isArray(value)) {
    if (value.length === 0) return parsePushClaimResponse(null);
    if (value.length !== 1) throw invalidClaimResponse();
    return parsePushClaimResponse(value[0]);
  }
  if (typeof value !== "object") throw invalidClaimResponse();

  const result = value as Record<string, unknown>;
  const attemptId = firstString(result.attempt_id, result.id);
  const disposition = firstString(result.disposition, result.status)
    .toLowerCase();
  const ownsClaim = result.claimed === true ||
    result.should_deliver === true ||
    disposition === "claimed" ||
    disposition === "retry_claimed";

  if (ownsClaim) {
    if (!isUuid(attemptId)) throw invalidClaimResponse();
    return { attemptId, skipped: null, retryAfterSeconds: null };
  }

  const retryAfterSeconds = boundedRetryAfter(result.retry_after_seconds);
  if (
    disposition === "retry_later" ||
    disposition === "failed_backoff" ||
    disposition === "backoff"
  ) {
    return {
      attemptId: null,
      skipped: "retry_later",
      retryAfterSeconds,
    };
  }
  if (
    result.claimed === false ||
    result.should_deliver === false ||
    disposition === "already_claimed" ||
    disposition === "deduplicated" ||
    disposition === "sent" ||
    disposition === "skipped" ||
    disposition === "processing"
  ) {
    return {
      attemptId: null,
      skipped: "already_claimed",
      retryAfterSeconds: null,
    };
  }
  throw invalidClaimResponse();
}

export function takeBoundedPushTokens(
  recipientId: string,
  rows: PushTokenCandidate[],
  maxTokens: number,
): PushTokenCandidate[] {
  if (!Number.isInteger(maxTokens) || maxTokens < 1 || maxTokens > 20) {
    throw new EdgeError(
      500,
      "push_limit_invalid",
      "Push delivery limit is invalid",
    );
  }

  const seen = new Set<string>();
  const selected: PushTokenCandidate[] = [];
  for (const row of rows) {
    if (row.user_id !== recipientId || !isUsablePushToken(row.token)) continue;
    if (seen.has(row.token)) continue;
    seen.add(row.token);
    selected.push({ user_id: recipientId, token: row.token });
    if (selected.length >= maxTokens) break;
  }
  return selected;
}

function isUsablePushToken(value: unknown): value is string {
  if (typeof value !== "string" || value.length < 16 || value.length > 4096) {
    return false;
  }
  return /^[\x21-\x7e]+$/.test(value);
}

function boundedRetryAfter(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  return Math.max(1, Math.min(3600, Math.ceil(parsed)));
}

function firstString(...values: unknown[]): string {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}

function isUuid(value: string): boolean {
  return uuidPattern.test(value);
}

function invalidClaimResponse(): EdgeError {
  return new EdgeError(
    503,
    "push_claim_invalid",
    "Push delivery claim returned an invalid response",
  );
}
