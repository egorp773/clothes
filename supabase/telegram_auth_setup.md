# Telegram auth setup

The app opens this public Edge Function:

`https://hbwzxtwcjlsfldjcqudt.supabase.co/functions/v1/telegram-auth`

The mobile redirect URL is:

`com.example.clothes://login-callback/`

## 1. Create a Telegram bot

1. Open Telegram and message `@BotFather`.
2. Run `/newbot`.
3. Save:
   - bot username: `odezhda001_bot`
   - bot token, for example `123456:ABC...`
4. Run `/setdomain` for the bot and set your Supabase function host:
   - `hbwzxtwcjlsfldjcqudt.supabase.co`

## 2. Add Supabase secrets

Set these Edge Function secrets:

```bash
supabase secrets set TELEGRAM_BOT_USERNAME=odezhda001_bot
supabase secrets set TELEGRAM_BOT_TOKEN=<BOT_TOKEN>
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are available to deployed Supabase functions automatically.

## 3. Deploy the function

Deploy without JWT verification, because Telegram opens the function before the user has a Supabase session:

```bash
supabase functions deploy telegram-auth --no-verify-jwt
```

## 4. Add redirect URL in Supabase Auth

Open Supabase Dashboard -> Authentication -> URL Configuration -> Redirect URLs and add:

`com.example.clothes://login-callback/`

For local Flutter web testing, also add the exact local URL you run, for example:

`http://127.0.0.1:8085/`
