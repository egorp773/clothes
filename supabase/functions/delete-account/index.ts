import { createClient } from "npm:@supabase/supabase-js@2";

type StorageObjectRow = {
  bucket_id: string;
  object_name: string;
};

const inventoryPageSize = 200;
const storageDeleteBatchSize = 100;

Deno.serve(async (request) => {
  const requestId = crypto.randomUUID();
  const cors = corsHeaders(request);
  if (!cors) {
    return json(
      { code: "origin_not_allowed", message: "Origin is not allowed", request_id: requestId },
      403,
      { "Vary": "Origin" },
    );
  }

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (request.method !== "POST") {
    return json(
      { code: "method_not_allowed", message: "Use POST", request_id: requestId },
      405,
      { ...cors, "Allow": "POST, OPTIONS" },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error(`[delete-account:${requestId}] missing server environment`);
    return json(
      { code: "server_misconfigured", message: "Account deletion is unavailable", request_id: requestId },
      500,
      cors,
    );
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return json(
      { code: "invalid_authorization", message: "Authentication required", request_id: requestId },
      401,
      cors,
    );
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await admin.auth.getUser(match[1]);
  if (authError || !authData.user) {
    return json(
      { code: "invalid_session", message: "Authentication required", request_id: requestId },
      401,
      cors,
    );
  }

  const userId = authData.user.id;
  try {
    const removedObjects = await deleteOwnedStorageObjects(admin, userId);

    // Products and outfits have legacy SET NULL ownership FKs. Delete them
    // explicitly so account deletion cannot leave public orphaned UGC.
    const { error: productDeleteError } = await admin
      .from("products")
      .delete()
      .eq("seller_id", userId);
    if (productDeleteError) throw new Error(`products:${productDeleteError.message}`);

    const { error: outfitDeleteError } = await admin
      .from("outfits")
      .delete()
      .eq("owner_id", userId);
    if (outfitDeleteError) throw new Error(`outfits:${outfitDeleteError.message}`);

    // This removes the Auth user and linked identities. Database rows with
    // CASCADE ownership (profile, accessories, messages, tokens, etc.) follow.
    const { error: deleteUserError } = await admin.auth.admin.deleteUser(userId);
    if (deleteUserError) throw new Error(`auth:${deleteUserError.message}`);

    console.info(
      `[delete-account:${requestId}] completed; storage_objects=${removedObjects}`,
    );
    return json(
      { deleted: true, removed_storage_objects: removedObjects, request_id: requestId },
      200,
      cors,
    );
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    console.error(`[delete-account:${requestId}] failed: ${detail}`);
    return json(
      { code: "deletion_failed", message: "Account could not be deleted", request_id: requestId },
      500,
      cors,
    );
  }
});

async function deleteOwnedStorageObjects(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<number> {
  let afterBucket = "";
  let afterName = "";
  let removed = 0;

  while (true) {
    const { data, error } = await admin.rpc(
      "list_account_deletion_storage_objects",
      {
        p_user_id: userId,
        p_after_bucket: afterBucket,
        p_after_name: afterName,
        p_limit: inventoryPageSize,
      },
    );
    if (error) throw new Error(`storage_inventory:${error.message}`);

    const rows = (data ?? []) as StorageObjectRow[];
    if (rows.length === 0) break;
    const last = rows[rows.length - 1];
    afterBucket = last.bucket_id;
    afterName = last.object_name;

    const byBucket = new Map<string, string[]>();
    for (const row of rows) {
      const paths = byBucket.get(row.bucket_id) ?? [];
      paths.push(row.object_name);
      byBucket.set(row.bucket_id, paths);
    }

    for (const [bucket, paths] of byBucket) {
      for (let offset = 0; offset < paths.length; offset += storageDeleteBatchSize) {
        const batch = paths.slice(offset, offset + storageDeleteBatchSize);
        const { error: removeError } = await admin.storage.from(bucket).remove(batch);
        if (removeError) {
          throw new Error(`storage_remove:${bucket}:${removeError.message}`);
        }
        removed += batch.length;
      }
    }

    if (rows.length < inventoryPageSize) break;
  }
  return removed;
}

function corsHeaders(request: Request): Record<string, string> | null {
  const origin = request.headers.get("Origin");
  const configured = (Deno.env.get("ACCOUNT_DELETION_ALLOWED_ORIGINS") ?? "*")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  if (origin && !configured.includes("*") && !configured.includes(origin)) {
    return null;
  }
  return {
    "Access-Control-Allow-Origin": origin && !configured.includes("*") ? origin : "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };
}

function json(
  body: unknown,
  status: number,
  headers: Record<string, string>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, "Content-Type": "application/json; charset=utf-8" },
  });
}
