import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.49.8";

import {
  bearerToken,
  EdgeError,
  errorResponse,
  jsonResponse,
  readJsonObject,
  requiredEnv,
  strictCorsHeaders,
} from "../_shared/edge.ts";

const retainedByDesign = [
  "orders_and_transaction_history",
  "payment_and_refund_ledger",
  "active_or_retained_disputes",
  "moderation_and_security_audit",
  "records_required_by_law",
];
const inventoryPageSize = 200;
const storageDeleteBatchSize = 100;

type StorageObjectRow = {
  bucket_id: string;
  object_name: string;
};

Deno.serve(async (request) => {
  const requestId = crypto.randomUUID();
  let cors: Record<string, string> = {};
  try {
    cors = strictCorsHeaders(request, "ACCOUNT_DELETION_ALLOWED_ORIGINS");
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      throw new EdgeError(405, "method_not_allowed", "Use POST");
    }

    const body = await readJsonObject(request, 8 * 1024);
    if (body.confirmation !== "DELETE_MY_ACCOUNT") {
      throw new EdgeError(
        400,
        "deletion_confirmation_required",
        "Explicit account deletion confirmation is required",
      );
    }
    const idempotencyKey = String(body.idempotency_key ?? "");
    if (!/^[A-Za-z0-9._:-]{16,128}$/.test(idempotencyKey)) {
      throw new EdgeError(
        400,
        "invalid_idempotency_key",
        "A stable idempotency_key is required",
      );
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = requiredEnv("SUPABASE_ANON_KEY");
    const accessToken = bearerToken(request);
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
    const { data: authData, error: authError } = await admin.auth.getUser(
      accessToken,
    );
    if (authError || !authData.user) {
      throw new EdgeError(401, "invalid_session", "Authentication required");
    }
    assertRecentAuthentication(authData.user.last_sign_in_at);

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
    const { data: requested, error: requestError } = await userClient.rpc(
      "request_account_deletion",
      { p_idempotency_key: idempotencyKey },
    );
    if (requestError) {
      if (requestError.code === "55000") {
        return jsonResponse(
          {
            accepted: false,
            anonymized: false,
            status: "deferred",
            code: safeDatabaseMessage(
              requestError.message,
              "active_obligations_prevent_deletion",
            ),
            deferred_reasons: ["active_order_payment_or_dispute"],
            retained_categories: retainedByDesign,
            request_id: requestId,
          },
          409,
          cors,
        );
      }
      throw mapDatabaseError(requestError, "deletion_request_failed");
    }
    const deletionRequest = normalizeRpcObject(requested);
    const deletionRequestId = String(
      deletionRequest.request_id ?? deletionRequest.id ?? "",
    );
    if (!isUuid(deletionRequestId)) {
      throw new EdgeError(
        503,
        "invalid_deletion_contract",
        "Account deletion request could not be identified",
      );
    }
    const requestStatus = String(deletionRequest.status ?? "requested");
    const deferredReasons = stringArray(
      deletionRequest.deferred_reasons ?? deletionRequest.hold_reasons,
    );
    if (
      deferredReasons.length > 0 ||
      ["held", "deferred", "waiting_for_retention"].includes(requestStatus)
    ) {
      return jsonResponse(
        {
          accepted: false,
          anonymized: false,
          status: requestStatus,
          deletion_request_id: deletionRequestId,
          deferred_reasons: deferredReasons,
          deletion_after: deletionRequest.deletion_after ?? null,
          retained_categories: stringArray(
            deletionRequest.retained_categories,
            retainedByDesign,
          ),
          request_id: requestId,
        },
        202,
        cors,
      );
    }

    // The database RPC removes the Auth identity in the same transaction as
    // anonymisation. Erase all non-retained Storage objects first so a failed
    // Storage operation can never leave an apparently deleted account with
    // owner media behind. This inventory/remove loop is safe to retry after a
    // partial attempt because already-removed objects disappear from inventory.
    const removedStorageObjects = await deleteOwnedStorageObjects(
      admin,
      authData.user.id,
    );

    const { data: anonymized, error: anonymizeError } = await admin.rpc(
      "anonymize_user_account",
      {
        p_request_id: deletionRequestId,
        p_user_id: authData.user.id,
        p_actor: "edge:delete-account",
      },
    );
    if (anonymizeError) {
      if (anonymizeError.code === "55000") {
        return jsonResponse(
          {
            accepted: false,
            anonymized: false,
            status: "deferred",
            deletion_request_id: deletionRequestId,
            deferred_reasons: ["active_order_payment_or_dispute"],
            retained_categories: retainedByDesign,
            request_id: requestId,
          },
          202,
          cors,
        );
      }
      throw mapDatabaseError(anonymizeError, "account_anonymization_failed");
    }
    const result = normalizeRpcObject(anonymized);
    const status = String(result.status ?? "anonymized");
    return jsonResponse(
      {
        accepted: true,
        anonymized: result.anonymized === true,
        status,
        deletion_request_id: deletionRequestId,
        deletion_after: result.deletion_after ?? null,
        retained_categories: stringArray(
          result.retained_categories,
          retainedByDesign,
        ),
        removed_categories: stringArray(result.removed_categories),
        removed_storage_objects: removedStorageObjects,
        request_id: requestId,
      },
      status === "anonymized" && result.anonymized === true ? 200 : 202,
      cors,
    );
  } catch (error) {
    return errorResponse(error, requestId, cors);
  }
});

async function deleteOwnedStorageObjects(
  admin: SupabaseClient,
  userId: string,
): Promise<number> {
  let afterBucket = "";
  let afterName = "";
  let removed = 0;

  while (true) {
    const rows = await listDeletionStorageObjects(
      admin,
      userId,
      afterBucket,
      afterName,
      inventoryPageSize,
    );
    if (rows.length === 0) break;

    const last = rows.at(-1)!;
    const byBucket = new Map<string, string[]>();
    for (const row of rows) {
      const paths = byBucket.get(row.bucket_id) ?? [];
      paths.push(row.object_name);
      byBucket.set(row.bucket_id, paths);
    }

    for (const [bucket, paths] of byBucket) {
      for (
        let offset = 0;
        offset < paths.length;
        offset += storageDeleteBatchSize
      ) {
        const batch = paths.slice(offset, offset + storageDeleteBatchSize);
        const { error } = await admin.storage.from(bucket).remove(batch);
        if (error) {
          console.error("Account deletion Storage removal failed", {
            bucket,
            error,
          });
          throw new EdgeError(
            503,
            "storage_erasure_failed",
            "Account media could not be erased",
          );
        }
        removed += batch.length;
      }
    }

    afterBucket = last.bucket_id;
    afterName = last.object_name;
    if (rows.length < inventoryPageSize) break;
  }

  // Do not delete Auth until the authoritative inventory confirms that no
  // erasable object remains. This also catches partial Storage API responses.
  const remaining = await listDeletionStorageObjects(
    admin,
    userId,
    "",
    "",
    1,
  );
  if (remaining.length > 0) {
    throw new EdgeError(
      503,
      "storage_erasure_incomplete",
      "Account media erasure is incomplete",
    );
  }
  return removed;
}

async function listDeletionStorageObjects(
  admin: SupabaseClient,
  userId: string,
  afterBucket: string,
  afterName: string,
  limit: number,
): Promise<StorageObjectRow[]> {
  const { data, error } = await admin.rpc(
    "list_account_deletion_storage_objects",
    {
      p_user_id: userId,
      p_after_bucket: afterBucket,
      p_after_name: afterName,
      p_limit: limit,
    },
  );
  if (error || !Array.isArray(data)) {
    console.error("Account deletion Storage inventory failed", error);
    throw new EdgeError(
      503,
      "storage_inventory_failed",
      "Account media could not be inventoried",
    );
  }
  return data.map((raw) => {
    const row = raw && typeof raw === "object"
      ? raw as Record<string, unknown>
      : {};
    const bucketId = String(row.bucket_id ?? "");
    const objectName = String(row.object_name ?? "");
    if (
      !/^[a-z0-9][a-z0-9._-]{0,99}$/.test(bucketId) ||
      objectName.length < 1 ||
      objectName.length > 1024 ||
      objectName.includes("\\") ||
      objectName.split("/").some((part) =>
        !part || part === "." || part === ".."
      )
    ) {
      throw new EdgeError(
        503,
        "invalid_storage_inventory",
        "Account media inventory is invalid",
      );
    }
    return { bucket_id: bucketId, object_name: objectName };
  });
}

function assertRecentAuthentication(lastSignInAt: string | undefined): void {
  const configured = Number(
    Deno.env.get("ACCOUNT_DELETION_REAUTH_MAX_AGE_SECONDS") ?? 600,
  );
  const maxAgeSeconds = Number.isFinite(configured)
    ? Math.max(300, Math.min(configured, 900))
    : 600;
  const lastSignIn = Date.parse(lastSignInAt ?? "");
  const ageMs = Date.now() - lastSignIn;
  if (
    !Number.isFinite(lastSignIn) ||
    ageMs < -30_000 ||
    ageMs > maxAgeSeconds * 1000
  ) {
    throw new EdgeError(
      403,
      "recent_authentication_required",
      "Sign in again before deleting the account",
    );
  }
}

function normalizeRpcObject(value: unknown): Record<string, unknown> {
  if (Array.isArray(value)) {
    return value[0] && typeof value[0] === "object"
      ? value[0] as Record<string, unknown>
      : {};
  }
  return value && typeof value === "object"
    ? value as Record<string, unknown>
    : {};
}

function stringArray(value: unknown, fallback: string[] = []): string[] {
  if (!Array.isArray(value)) return [...fallback];
  const sanitized = value
    .map((item) => String(item ?? "").trim())
    .filter(Boolean)
    .map((item) => item.slice(0, 100));
  return sanitized.length > 0 ? [...new Set(sanitized)] : [...fallback];
}

function safeDatabaseMessage(
  value: string | undefined,
  fallback: string,
): string {
  const message = String(value ?? fallback)
    .replace(/^.*?:\s*/, "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 100);
  return message || fallback;
}

function mapDatabaseError(
  error: { code?: string; message?: string },
  fallbackCode: string,
): EdgeError {
  const code = safeDatabaseMessage(error.message, fallbackCode);
  if (error.code === "42501") {
    return new EdgeError(403, code, "Account deletion is not allowed");
  }
  if (error.code === "23514") {
    return new EdgeError(409, code, "Account deletion request is invalid");
  }
  if (error.code === "P0002") {
    return new EdgeError(404, code, "Account deletion request was not found");
  }
  console.error("Account deletion RPC failed", error);
  return new EdgeError(
    503,
    fallbackCode,
    "Account deletion is temporarily unavailable",
  );
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(
      value,
    );
}
