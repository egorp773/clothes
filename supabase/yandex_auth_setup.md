# Yandex ID auth setup

Flutter app provider id: `custom:yandex`

Mobile app redirect URL: `com.example.clothes://login-callback/`

Supabase app URL: `https://hbwzxtwcjlsfldjcqudt.supabase.co`

## Supabase

1. Open Supabase Dashboard -> Authentication -> Providers.
2. Add a Custom OAuth provider.
3. Use identifier `custom:yandex`.
4. Use OAuth2 manual configuration:
   - Authorization URL: `https://oauth.yandex.ru/authorize`
   - Token URL: `https://oauth.yandex.ru/token`
   - UserInfo URL: `https://login.yandex.ru/info`
5. Copy the Supabase callback URL shown by the provider form.
6. Enable the provider.
7. Add `com.example.clothes://login-callback/` to Authentication -> URL Configuration -> Redirect URLs.

## Yandex OAuth

1. Create an authorization app in Yandex OAuth.
2. Add the Supabase callback URL from the custom provider form as the Yandex Redirect URI.
3. Enable access to login/user info and email.
4. Copy Client ID and Client Secret into the Supabase custom provider.

## Telegram

Telegram Login requires a bot token and server-side hash verification. Do not verify Telegram login only in Flutter, because the bot token must stay secret.
