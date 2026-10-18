# Cloudflare Worker

The Worker serves the dashboard assets and handles web and Tempo iOS Strava OAuth on the same origin. Web Strava refresh tokens are stored in the `TOKEN_STORE` KV namespace; the browser receives only an HttpOnly session cookie. The iOS app receives a short-lived one-time exchange ticket and stores its separate water-sync token in iOS Keychain.

## Cloudflare setup

1. The Worker name is `tempoapi`, matching `wrangler.jsonc`.
2. In **Settings → Variables and Secrets**, add these as secrets: `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`, a random high-entropy `STRAVA_WEBHOOK_VERIFY_TOKEN`, a separate random `STRAVA_WEBHOOK_PATH_SECRET`, a random `MODERATION_TOKEN` (at least 32 random bytes), and a random `AUTH_PEPPER` (at least 32 random bytes). Do not commit these values. Keep `AUTH_PEPPER` backed up in a password manager: rotating it without a password-hash migration locks out accounts that have already been upgraded.
3. The first deployment creates and binds the `TOKEN_STORE` KV namespace from `wrangler.jsonc`.
4. `wrangler.jsonc` also binds Cloudflare Workers AI as `AI`; the Tempo Koç feature uses the Cloudflare-hosted Llama 4 Scout model.
5. Connect the GitHub repository under **Settings → Builds**. Set the root directory to `worker/` and let Cloudflare use `npx wrangler deploy` as the deploy command.
6. After deployment, open `https://tempo-strava-api.gokalpakgun11.workers.dev/` and use **Strava’ya bağlan**.

When connecting an existing Worker, push a new commit to the selected production branch to trigger its first repository build.

The Strava app's Authorization Callback Domain must match the public site host, currently `apitempo.com`. Web OAuth uses `/auth/callback`; the iOS companion app uses `/mobile/auth/callback` on the same host.

Do not put Strava credentials in GitHub files. Add or rotate them only in Cloudflare's secret settings. The Worker requests `activity:read_all`, uses OAuth state validation, stores session refresh tokens server-side, and requires the same-origin HttpOnly cookie for activity access.

Tempo Koç runs only after the user submits a request. It uses the question and conversation plus an Apple Health summary only when the user explicitly opts in for that request. Strava profile, activity data, and data derived from Strava are never sent to Workers AI. Coach prompts and answers are not stored by the app.

Strava webhook support uses `/webhooks/strava/<STRAVA_WEBHOOK_PATH_SECRET>`. The unguessable path prevents forged POST events because Strava's event callbacks do not include a signing secret. Configure both webhook secrets in the Worker and register that exact callback URL with Strava. Activity create/update/delete events invalidate cached dashboards; an athlete deauthorization event removes the linked Strava credentials and server-side Strava dashboard cache. The iOS dashboard cache expires after 24 hours so deleted activity data is not kept visible beyond Strava's 48-hour deletion window.

Social safety reports are stored for up to 180 days in `TOKEN_STORE`. The `MODERATION_TOKEN` protects the private report queue: `GET /api/moderation/reports` lists reports, and `POST /api/moderation/reports/<report-id>` with `{"action":"resolve"}` closes one. Use a random value of at least 32 characters, send it only in an HTTPS `Authorization: Bearer` header, and never put it in the app or a URL. Review reports promptly and follow up through the published support channel. Social write actions stay unavailable until this secret is configured.

The `AI` binding uses `@cf/meta/llama-guard-3-8b` to screen public usernames, display names and challenge titles. Only the short text being published is sent for classification; Health and Strava data are never passed to this moderation model. Unknown or unavailable moderation results are rejected. Automated screening is not a substitute for a person reviewing user reports; keep the queue monitored and take timely action.

`AUTH_PEPPER` must be a random value of at least 32 characters and is combined with PBKDF2-SHA-256 (100,000 iterations, the Workers runtime ceiling) before deriving new password hashes. Existing unpeppered accounts are upgraded after a successful login. New signup and password-reset operations fail closed if the pepper is missing or too short. The secret itself is never stored with a user record.

The native SwiftUI iOS source lives under `ios/TempoHealth`. It reads the athlete dashboard through bearer-protected mobile endpoints and uses MapKit for activity routes. The app uses a PKCE-bound, one-time OAuth ticket; its random access token is stored in iOS Keychain while Strava refresh credentials remain in KV. Water is entered manually in the app and daily totals are retained in KV for up to 100 days. Public use also requires upgrading the Strava API app from single-player mode (10 athletes) and requesting Strava review before scaling beyond that. App Store distribution requires an Apple Developer account, a completed privacy-policy contact, signing, device testing, and App Review.
