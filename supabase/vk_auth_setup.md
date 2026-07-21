# VK ID: production setup

Register this exact provider callback:

`https://<SUPABASE_HOST>/functions/v1/vk-auth`

Flutter starts the flow with an application PKCE challenge and an explicitly
allowlisted `redirect_to`. The Edge Function uses provider PKCE, validates the
one-time state, and returns only a short `exchange_code` to the app. Flutter
exchanges that code by `POST` with its original verifier; access and refresh
tokens never appear in the redirect URL.

Configure deployment secrets:

```bash
supabase secrets set \
  VK_CLIENT_ID=<VK_CLIENT_ID> \
  OAUTH_ALLOWED_REDIRECT_URIS=com.example.clothes://login-callback/ \
  OAUTH_DEFAULT_REDIRECT_URI=com.example.clothes://login-callback/ \
  OAUTH_ALLOWED_WEB_ORIGINS=https://<APP_WEB_HOST>
```

Replace the example application ID/scheme with the final organization-owned
identifier in Flutter, Android, iOS, Supabase, and this allowlist together.

If the selected VK application type requires an additional secret, store it
only in the Edge Function secret store under the name used by the deployed
provider integration. Do not accept identity from an unverified `id_token`
fallback and do not auto-link accounts by an unverified provider email.

Deploy the public OAuth entry point:

```bash
supabase functions deploy vk-auth --no-verify-jwt
```

The function remains responsible for exact redirect validation, provider and
application PKCE, state expiry, one-time identity resolution, and replay
prevention.
