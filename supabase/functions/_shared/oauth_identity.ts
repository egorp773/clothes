export type OAuthCandidate = {
  app_metadata?: Record<string, unknown> | null;
  user_metadata?: Record<string, unknown> | null;
};

export function normalizeOAuthSubject(value: unknown): string | null {
  const subject = String(value ?? "").trim();
  if (
    subject.length < 1 ||
    subject.length > 500 ||
    !/^[\x21-\x7e]+$/.test(subject)
  ) {
    return null;
  }
  return subject;
}

/**
 * A synthetic Auth user is only safe to bind to an external identity when
 * every binding value came from service-controlled app_metadata. User
 * metadata alone is never sufficient because a normal signup can choose it.
 */
export function isTrustedProvisionalOAuthCandidate(
  candidate: OAuthCandidate,
  provider: string,
  providerSubject: string,
): boolean {
  const appMetadata = candidate.app_metadata;
  const userMetadata = candidate.user_metadata;
  if (!appMetadata || !userMetadata) return false;

  return appMetadata.registration_status === "provisional" &&
    appMetadata.oauth_provider === provider &&
    appMetadata.oauth_provider_subject === providerSubject &&
    userMetadata.provider === provider &&
    userMetadata.provider_subject === providerSubject;
}
