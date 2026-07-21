# Yandex ID: production setup

The application uses a two-stage OAuth flow:

1. Flutter generates an application PKCE verifier/challenge and opens
   `https://<SUPABASE_HOST>/functions/v1/yandex-auth` with the exact
   `redirect_to` and `code_challenge`.
2. The Edge Function validates a one-time server-side state, completes the
   provider exchange, and redirects to the allowlisted app URI with a short
   one-time `exchange_code` only.
3. Flutter sends that code and the original verifier to the same function by
   `POST`. Supabase session tokens are returned in the response body and never
   placed in a redirect URL.

## Provider configuration

Create a Yandex OAuth application and register this exact callback:

`https://<SUPABASE_HOST>/functions/v1/yandex-auth`

Enable only the scopes required for identity and email:

`login:info login:email`

Do not register wildcard callbacks.

## Edge Function secrets

```bash
supabase secrets set \
  YANDEX_CLIENT_ID=<YANDEX_CLIENT_ID> \
  YANDEX_CLIENT_SECRET=<YANDEX_CLIENT_SECRET> \
  OAUTH_ALLOWED_REDIRECT_URIS=com.example.clothes://login-callback/ \
  OAUTH_DEFAULT_REDIRECT_URI=com.example.clothes://login-callback/ \
  OAUTH_ALLOWED_WEB_ORIGINS=https://<APP_WEB_HOST>
```

List every allowed redirect explicitly, comma-separated. Development HTTP
redirects are accepted only for `localhost`, `127.0.0.1`, or `[::1]`.
Replace the example application ID/scheme with the final organization-owned
identifier in Flutter, Android, iOS, Supabase, and this allowlist together.

Deploy the public OAuth entry point without Supabase JWT verification:

```bash
supabase functions deploy yandex-auth --no-verify-jwt
```

The function itself still enforces state, application PKCE, provider PKCE,
exact redirects, short expiry, and one-time exchange. Never put the Yandex
client secret or Supabase service-role key in Flutter.
