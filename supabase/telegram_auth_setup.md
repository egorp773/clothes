# Telegram Login: production setup

Telegram authentication is verified only by the Edge Function. The bot token
must never be present in Flutter.

The app generates an application PKCE verifier/challenge before opening
`https://<SUPABASE_HOST>/functions/v1/telegram-auth`. After Telegram login, the
Edge Function validates the signed payload, its age, and the one-time state.
The allowlisted app callback receives only a short `exchange_code`; Flutter
exchanges it by `POST` together with the original PKCE verifier. Session
tokens are never included in the redirect URL.

## Bot configuration

1. Create the bot with `@BotFather`.
2. Use `/setdomain` with the exact HTTPS Supabase Functions host.
3. Record the numeric bot ID and bot token in the deployment secret store.

## Edge Function secrets

```bash
supabase secrets set \
  TELEGRAM_BOT_ID=<NUMERIC_BOT_ID> \
  TELEGRAM_BOT_TOKEN=<BOT_TOKEN> \
  TELEGRAM_AUTH_MAX_AGE_SECONDS=300 \
  OAUTH_ALLOWED_REDIRECT_URIS=com.example.clothes://login-callback/ \
  OAUTH_DEFAULT_REDIRECT_URI=com.example.clothes://login-callback/ \
  OAUTH_ALLOWED_WEB_ORIGINS=https://<APP_WEB_HOST>
```

List every allowed redirect explicitly, comma-separated. Do not use a wildcard
domain or accept a client-supplied redirect that is absent from this list.
Replace the example application ID/scheme with the final organization-owned
identifier in Flutter, Android, iOS, Supabase, and this allowlist together.

Deploy the public entry point without Supabase JWT verification:

```bash
supabase functions deploy telegram-auth --no-verify-jwt
```

This makes only the HTTP entry point public. The function must retain its
server-side signature, freshness, state, PKCE, expiry, and replay checks.
