import { createClient } from "npm:@supabase/supabase-js@2.49.8";

import {
  bearerToken,
  EdgeError,
  errorResponse,
  jsonResponse,
  readJsonObject,
  requestMetadata,
  requiredEnv,
  strictCorsHeaders,
} from "../_shared/edge.ts";

Deno.serve(async (request) => {
  const requestId = crypto.randomUUID();
  let cors: Record<string, string> = {};
  try {
    cors = strictCorsHeaders(request, "CONSENT_CENTER_ALLOWED_WEB_ORIGINS");
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      throw new EdgeError(405, "method_not_allowed", "Use POST");
    }
    const body = await readJsonObject(request, 2 * 1024);
    if (body.confirmation !== "WITHDRAW_MARKETING_CONSENT") {
      throw new EdgeError(
        400,
        "withdrawal_confirmation_required",
        "Explicit marketing withdrawal confirmation is required",
      );
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

    const metadata = requestMetadata(request);
    if (!metadata.ip) {
      throw new EdgeError(
        503,
        "request_metadata_unavailable",
        "Withdrawal evidence could not be captured",
      );
    }
    const { data, error } = await admin.rpc(
      "withdraw_marketing_consent_for_user",
      {
        p_user_id: authData.user.id,
        p_ip: metadata.ip,
        p_user_agent: metadata.userAgent,
      },
    );
    if (error) {
      console.error(`[consent-withdrawal:${requestId}] database failure`, {
        code: error.code,
      });
      throw new EdgeError(
        503,
        "withdrawal_not_recorded",
        "Marketing withdrawal could not be recorded",
      );
    }
    return jsonResponse(
      {
        withdrawn: true,
        changed: Number(data ?? 0) > 0,
        request_id: requestId,
      },
      200,
      cors,
    );
  } catch (error) {
    return errorResponse(error, requestId, cors);
  }
});
