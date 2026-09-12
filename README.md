# BlueAI

Mobile AI assistant built with Flutter for Android and iOS.

The web target is kept for development and UI testing.

## AI backend

Google login is required. Supabase Auth, PostgreSQL and Realtime store and sync
rooms/messages. The Cloudflare Worker in `backend/` verifies the user's session,
loads database history, streams AI and persists checkpoints. Only the AI key goes
to the gateway; the Supabase token is never forwarded to the AI provider.

Start with [Supabase and Google setup](docs/SUPABASE_SETUP.md). Copy
`config/dev.example.json` to `config/dev.json` and fill in your public project
configuration. In Android Studio's **Additional run args**, enter:

```text
--dart-define-from-file=config/dev.json
```

Or run `flutter run --dart-define-from-file=config/dev.json`. For web add
`-d chrome --web-port=3000` and allow that origin in Supabase and the Worker.
No project credentials are included. The app displays setup instructions until configured.

Copy `backend/.dev.vars.example` to `backend/.dev.vars`, fill in the same Supabase
URL and publishable key, then run the backend locally:

```bash
cd backend
npm install
npm run dev
```

Deploy it with `npm run deploy`, then set the returned HTTPS Worker URL in the
app settings or with `--dart-define=BLUEAI_BACKEND_URL=https://...`.

HTTP is disabled by default because it exposes API keys and chat messages. For
local LAN development only, enable it explicitly:

```bash
flutter run \
  --dart-define=BLUEAI_BACKEND_URL=http://192.168.1.20:8787 \
  --dart-define=BLUEAI_ALLOW_INSECURE_HTTP=true
```

See `backend/README.md` for Worker configuration and deployment details.

## Credential storage and streaming reliability

API keys are stored with `flutter_secure_storage`, not ordinary preferences.
Keys are scoped by account on each device. After login, migration asks whether to
assign a legacy key to that account before verifying its new copy and deleting
the old one. New devices require their own key. Signing out clears account state
from memory; the scoped key remains for the next login by the same account.
Clearing the key in settings deletes it from secure storage. Android requires
API 23+ and app backup is disabled; Apple targets include Keychain entitlements.
Web development requires HTTPS or localhost for secure storage.

See the [secure-storage platform setup](https://pub.dev/packages/flutter_secure_storage/versions/10.3.2)
when building on a new machine. Windows desktop plugin builds require symlink
support (Developer Mode). Native Keychain/Keystore behavior must also be tested
on the target device.

Chat requests time out after 30 seconds waiting for response headers or 90
seconds without a stream chunk. Stop and timeouts abort the HTTP request; the
Worker forwards cancellation upstream. SSE replies require `[DONE]` to count
as complete. Truncated and reasoning-only replies are shown as errors and are
excluded from subsequent assistant history. Raw-text compatibility responses
have no completion marker and use HTTP EOF instead.

Run checks with `flutter analyze`, `flutter test`, and, inside `backend/`,
`npm run build` and `npm test`. Backend tests use the installed AI SDK with a
mock gateway and do not send API requests. The SQL suite applies migrations to
PostgreSQL via PGlite and tests two-account RLS, atomic turns, expiry and soft deletion.
Google OAuth, Realtime delivery and two-device concurrency still require a real
test project; follow the acceptance checklist in the setup guide before release.

Rooms support rename, pin, soft delete and history paging. Realtime causes a
database refetch; resume/reconnect also refetches. Offline reads use memory and
cloud writes are disabled. There is no offline mutation queue, attachment handling,
quota system or long-context summarization in this version. Previously lost
in-memory history cannot be recovered.
