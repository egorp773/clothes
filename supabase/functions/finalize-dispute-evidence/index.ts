import { createClient } from "npm:@supabase/supabase-js@2.49.8";

import {
  bearerToken,
  EdgeError,
  errorResponse,
  jsonResponse,
  readJsonObject,
  requiredEnv,
  sha256BytesHex,
  strictCorsHeaders,
} from "../_shared/edge.ts";
import {
  assertEvidenceObjectPath,
  detectEvidenceImageMime,
  maxDisputeImageBytes,
} from "../_shared/evidence.ts";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

Deno.serve(async (request) => {
  const requestId = crypto.randomUUID();
  let cors: Record<string, string> = {};
  try {
    cors = strictCorsHeaders(request, "DISPUTE_ALLOWED_WEB_ORIGINS");
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      throw new EdgeError(405, "method_not_allowed", "Use POST");
    }
    const body = await readJsonObject(request, 8 * 1024);
    const disputeId = String(body.dispute_id ?? "").trim().toLowerCase();
    if (!uuidPattern.test(disputeId)) {
      throw new EdgeError(400, "invalid_dispute_id", "Invalid dispute id");
    }

    const admin = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false,
        },
      },
    );
    const { data: authData, error: authError } = await admin.auth.getUser(
      bearerToken(request),
    );
    if (authError || !authData.user) {
      throw new EdgeError(401, "invalid_session", "Authentication required");
    }
    const objectPath = assertEvidenceObjectPath(
      body.storage_path,
      authData.user.id,
      disputeId,
    );
    const { data: object, error: downloadError } = await admin.storage
      .from("dispute-evidence")
      .download(objectPath);
    if (downloadError || !object) {
      throw new EdgeError(404, "evidence_not_found", "Evidence was not found");
    }
    if (object.size < 1 || object.size > maxDisputeImageBytes) {
      await admin.storage.from("dispute-evidence").remove([objectPath]);
      throw new EdgeError(413, "invalid_evidence_size", "Invalid image size");
    }
    const bytes = new Uint8Array(await object.arrayBuffer());
    let mimeType: string;
    try {
      mimeType = detectEvidenceImageMime(bytes);
    } catch (error) {
      await admin.storage.from("dispute-evidence").remove([objectPath]);
      throw error;
    }
    const contentHash = await sha256BytesHex(bytes);
    const fileName = objectPath.split("/").at(-1) ?? "";
    if (!fileName.startsWith(contentHash)) {
      await admin.storage.from("dispute-evidence").remove([objectPath]);
      throw new EdgeError(
        409,
        "evidence_hash_mismatch",
        "Uploaded evidence checksum does not match its object path",
      );
    }
    const originalName = String(body.original_name ?? "evidence")
      .replace(/[\u0000-\u001f\u007f/\\]/g, "")
      .slice(0, 255) || "evidence";
    const { data: evidenceId, error: finalizeError } = await admin.rpc(
      "finalize_dispute_evidence",
      {
        p_actor_id: authData.user.id,
        p_dispute_id: disputeId,
        p_evidence_type: "image",
        p_storage_path: objectPath,
        p_content_hash: contentHash,
        p_metadata: {
          original_name: originalName,
          size_bytes: bytes.byteLength,
          mime_type: mimeType,
          checksum_source: "edge_download",
        },
      },
    );
    if (finalizeError || !evidenceId) {
      console.error(`[dispute-evidence:${requestId}] finalize failed`, {
        code: finalizeError?.code,
      });
      throw new EdgeError(
        403,
        "evidence_finalize_denied",
        "Evidence could not be attached to this dispute",
      );
    }
    return jsonResponse(
      {
        finalized: true,
        evidence_id: evidenceId,
        storage_path: objectPath,
        request_id: requestId,
      },
      200,
      cors,
    );
  } catch (error) {
    return errorResponse(error, requestId, cors);
  }
});
