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
  requestMetadata,
  requiredEnv,
  strictCorsHeaders,
} from "../_shared/edge.ts";

const mandatoryDocumentTypes = new Set([
  "terms",
  "privacy_policy",
  "personal_data_consent",
]);
const allowedDocumentTypes = new Set([
  ...mandatoryDocumentTypes,
  "marketing_consent",
]);

type ConsentInput = {
  document_type: string;
  version: string;
  accepted: boolean;
};

Deno.serve(async (request) => {
  const requestId = crypto.randomUUID();
  let cors: Record<string, string> = {};
  try {
    cors = strictCorsHeaders(request, "REGISTRATION_ALLOWED_WEB_ORIGINS");
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      throw new EdgeError(405, "method_not_allowed", "Use POST");
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
    const { data: authData, error: authError } = await admin.auth.getUser(
      bearerToken(request),
    );
    if (authError || !authData.user) {
      throw new EdgeError(401, "invalid_session", "Authentication required");
    }

    const body = await readJsonObject(request, 32 * 1024);
    const birthDate = validateAdultBirthDate(body.birth_date);
    const consents = validateConsents(body.consents);
    await assertActiveDocumentVersions(admin, consents);
    const requiredVersions = Object.fromEntries(
      consents
        .filter((consent) => mandatoryDocumentTypes.has(consent.document_type))
        .map((consent) => [consent.document_type, consent.version]),
    );
    const marketingVersion = consents.find((consent) =>
      consent.document_type === "marketing_consent" && consent.accepted
    )?.version ?? null;
    const metadata = requestMetadata(request);
    const { data, error } = await admin.rpc("complete_legal_onboarding", {
      p_user_id: authData.user.id,
      p_birth_date: birthDate,
      p_required_versions: requiredVersions,
      p_marketing_version: marketingVersion,
      p_ip: metadata.ip,
      p_user_agent: metadata.userAgent,
    });
    if (error) {
      throw mapDatabaseError(error);
    }
    return jsonResponse(
      {
        completed: true,
        onboarding: data,
        request_id: requestId,
      },
      200,
      cors,
    );
  } catch (error) {
    return errorResponse(error, requestId, cors);
  }
});

function validateAdultBirthDate(value: unknown): string {
  const birthDate = String(value ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(birthDate)) {
    throw new EdgeError(
      400,
      "invalid_birth_date",
      "birth_date must use YYYY-MM-DD",
    );
  }
  const [year, month, day] = birthDate.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new EdgeError(400, "invalid_birth_date", "birth_date is invalid");
  }
  const today = new Date();
  const utcToday = new Date(
    Date.UTC(
      today.getUTCFullYear(),
      today.getUTCMonth(),
      today.getUTCDate(),
    ),
  );
  let age = utcToday.getUTCFullYear() - year;
  const birthdayOccurred = utcToday.getUTCMonth() > month - 1 ||
    (
      utcToday.getUTCMonth() === month - 1 &&
      utcToday.getUTCDate() >= day
    );
  if (!birthdayOccurred) age -= 1;
  if (age < 18) {
    throw new EdgeError(
      403,
      "minimum_age_not_met",
      "Only users aged 18 or older may register",
    );
  }
  if (age > 120) {
    throw new EdgeError(400, "invalid_birth_date", "birth_date is implausible");
  }
  return birthDate;
}

function validateConsents(value: unknown): ConsentInput[] {
  if (!Array.isArray(value) || value.length < 3 || value.length > 4) {
    throw new EdgeError(
      400,
      "invalid_consents",
      "consents must contain the separate legal document decisions",
    );
  }
  const seen = new Set<string>();
  const consents = value.map((raw) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw new EdgeError(400, "invalid_consents", "Consent entry is invalid");
    }
    const entry = raw as Record<string, unknown>;
    const documentType = String(entry.document_type ?? "");
    const version = String(entry.version ?? "");
    if (
      !allowedDocumentTypes.has(documentType) ||
      seen.has(documentType) ||
      !/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(version) ||
      typeof entry.accepted !== "boolean"
    ) {
      throw new EdgeError(400, "invalid_consents", "Consent entry is invalid");
    }
    seen.add(documentType);
    return {
      document_type: documentType,
      version,
      accepted: entry.accepted,
    };
  });
  for (const required of mandatoryDocumentTypes) {
    const consent = consents.find((entry) => entry.document_type === required);
    if (!consent?.accepted) {
      throw new EdgeError(
        403,
        "mandatory_consent_required",
        `Consent for ${required} is required`,
      );
    }
  }
  return consents;
}

async function assertActiveDocumentVersions(
  admin: SupabaseClient<any, "public", any>,
  consents: ConsentInput[],
): Promise<void> {
  const { data, error } = await admin.rpc("get_active_legal_documents");
  if (error || !Array.isArray(data)) {
    console.error("Active legal documents are unavailable", error);
    throw new EdgeError(
      503,
      "legal_documents_unavailable",
      "Active legal documents are not configured",
    );
  }
  const active = new Map<string, string>();
  for (const raw of data) {
    if (!raw || typeof raw !== "object") continue;
    const row = raw as Record<string, unknown>;
    active.set(
      String(row.document_type ?? row.type ?? ""),
      String(row.version ?? ""),
    );
  }
  for (const required of mandatoryDocumentTypes) {
    if (!active.get(required)) {
      throw new EdgeError(
        503,
        "legal_documents_unavailable",
        `Active ${required} document is not configured`,
      );
    }
  }
  for (const consent of consents) {
    if (
      consent.accepted && active.get(consent.document_type) !== consent.version
    ) {
      throw new EdgeError(
        409,
        "legal_document_version_stale",
        `The accepted ${consent.document_type} version is no longer active`,
      );
    }
  }
}

function mapDatabaseError(error: {
  code?: string;
  message?: string;
}): EdgeError {
  const message = String(error.message ?? "legal_onboarding_failed")
    .replace(/^.*?:\s*/, "")
    .trim();
  if (error.code === "42501") {
    return new EdgeError(403, message || "onboarding_forbidden", message);
  }
  if (error.code === "23514") {
    return new EdgeError(409, message || "onboarding_invalid", message);
  }
  if (error.code === "22023") {
    return new EdgeError(400, message || "onboarding_invalid", message);
  }
  if (error.code === "55000") {
    return new EdgeError(409, message || "legal_document_version_stale", message);
  }
  console.error("complete_legal_onboarding failed", error);
  return new EdgeError(
    503,
    "onboarding_unavailable",
    "Legal onboarding could not be completed",
  );
}
