# Yandex ID auth setup

The app uses the public Edge Function:

`https://hbwzxtwcjlsfldjcqudt.supabase.co/functions/v1/yandex-auth`

Mobile app redirect URL:

`com.example.clothes://login-callback/`

Yandex Client ID:

`ce46da5616754944897dbb8b6a7116fe`

Yandex Redirect URI:

`https://hbwzxtwcjlsfldjcqudt.supabase.co/functions/v1/yandex-auth`

Yandex authorization page host:

`hbwzxtwcjlsfldjcqudt.supabase.co`

## Yandex OAuth

1. Open your app in Yandex OAuth.
2. Add the Yandex Redirect URI above.
3. Enable access to Yandex ID user info and email.

## Supabase

Set Edge Function secrets:

```bash
supabase secrets set YANDEX_CLIENT_ID=ce46da5616754944897dbb8b6a7116fe
supabase secrets set YANDEX_CLIENT_SECRET=<CLIENT_SECRET>
```

Deploy without JWT verification:

```bash
supabase functions deploy yandex-auth --no-verify-jwt
```

Do not store the Client Secret in Flutter code or commit it to Git.

## Telegram

Telegram Login requires a bot token and server-side hash verification. Do not verify Telegram login only in Flutter, because the bot token must stay secret.
