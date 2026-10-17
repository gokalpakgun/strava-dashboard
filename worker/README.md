# Cloudflare Worker

The Worker serves the dashboard assets and handles web and Tempo iOS Strava OAuth on the same origin. Web Strava refresh tokens are stored in the `TOKEN_STORE` KV namespace; the browser receives only an HttpOnly session cookie. The iOS app receives a short-lived one-time exchange ticket and stores its separate water-sync token in iOS Keychain.

## Cloudflare setup

1. The Worker name is `tempoapi`, matching `wrangler.jsonc`.
2. In **Settings → Variables and Secrets**, add these as secrets: `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`, a random high-entropy `STRAVA_WEBHOOK_VERIFY_TOKEN`, and a separate random `STRAVA_WEBHOOK_PATH_SECRET`.
3. The first deployment creates and binds the `TOKEN_STORE` KV namespace from `wrangler.jsonc`.
4. `wrangler.jsonc` also binds Cloudflare Workers AI as `AI`; the Tempo Koç feature uses the Cloudflare-hosted Llama 4 Scout model.
5. Connect the GitHub repository under **Settings → Builds**. Set the root directory to `worker/` and let Cloudflare use `npx wrangler deploy` as the deploy command.
6. After deployment, open `https://tempo-strava-api.gokalpakgun11.workers.dev/` and use **Strava’ya bağlan**.

When connecting an existing Worker, push a new commit to the selected production branch to trigger its first repository build.

The Strava app's Authorization Callback Domain must match the public site host, currently `apitempo.com`. Web OAuth uses `/auth/callback`; the iOS companion app uses `/mobile/auth/callback` on the same host.

Do not put Strava credentials in GitHub files. Add or rotate them only in Cloudflare's secret settings. The Worker requests `activity:read_all`, uses OAuth state validation, stores session refresh tokens server-side, and requires the same-origin HttpOnly cookie for activity access.

Tempo Koç runs only after the user submits a request. It uses the question and conversation plus an Apple Health summary only when the user explicitly opts in for that request. Strava profile, activity data, and data derived from Strava are never sent to Workers AI. Coach prompts and answers are not stored by the app.

Strava webhook support uses `/webhooks/strava/<STRAVA_WEBHOOK_PATH_SECRET>`. The unguessable path prevents forged POST events because Strava's event callbacks do not include a signing secret. Configure both webhook secrets in the Worker and register that exact callback URL with Strava. Activity create/update/delete events invalidate cached dashboards; an athlete deauthorization event removes the linked Strava credentials and server-side Strava dashboard cache. The iOS dashboard cache expires after 24 hours so deleted activity data is not kept visible beyond Strava's 48-hour deletion window.

The native SwiftUI iOS source lives under `ios/TempoHealth`. It reads the athlete dashboard through bearer-protected mobile endpoints and uses MapKit for activity routes. The app uses a PKCE-bound, one-time OAuth ticket; its random access token is stored in iOS Keychain while Strava refresh credentials remain in KV. Water is entered manually in the app and daily totals are retained in KV for up to 100 days. Public use also requires upgrading the Strava API app from single-player mode (10 athletes) and requesting Strava review before scaling beyond that. App Store distribution requires an Apple Developer account, a completed privacy-policy contact, signing, device testing, and App Review.
