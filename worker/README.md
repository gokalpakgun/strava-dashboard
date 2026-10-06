# Cloudflare Worker

The Worker serves the dashboard assets and handles web and Tempo iOS Strava OAuth on the same origin. Web Strava refresh tokens are stored in the `TOKEN_STORE` KV namespace; the browser receives only an HttpOnly session cookie. The iOS app receives a short-lived one-time exchange ticket and stores its separate water-sync token in iOS Keychain.

## Cloudflare setup

1. The Worker name is `tempoapi`, matching `wrangler.jsonc`.
2. In **Settings → Variables and Secrets**, add these as secrets: `STRAVA_CLIENT_ID` and `STRAVA_CLIENT_SECRET`.
3. The first deployment creates and binds the `TOKEN_STORE` KV namespace from `wrangler.jsonc`.
4. `wrangler.jsonc` also binds Cloudflare Workers AI as `AI`; the Tempo Koç feature uses the Cloudflare-hosted Llama 4 Scout model.
5. Connect the GitHub repository under **Settings → Builds**. Set the root directory to `worker/` and let Cloudflare use `npx wrangler deploy` as the deploy command.
6. After deployment, open `https://tempo-strava-api.gokalpakgun11.workers.dev/` and use **Strava’ya bağlan**.

When connecting an existing Worker, push a new commit to the selected production branch to trigger its first repository build.

The Strava app's Authorization Callback Domain must match the public site host, currently `apitempo.com`. Web OAuth uses `/auth/callback`; the iOS companion app uses `/mobile/auth/callback` on the same host.

Do not put Strava credentials in GitHub files. Add or rotate them only in Cloudflare's secret settings. The Worker requests `activity:read_all`, uses OAuth state validation, stores session refresh tokens server-side, and requires the same-origin HttpOnly cookie for activity access.

Tempo Koç runs only after the athlete checks the in-app consent box and submits a request. The Worker sends Cloudflare AI the selected date range, weekly and monthly aggregates derived from sport type, distance, moving time, elevation, average speed and running pace, plus the question text. It excludes activity names, routes, precise locations, and profile details. Coach prompts and answers are not stored by the app.

The iOS source lives under `ios/TempoHealth`. It uses HealthKit to read dietary-water samples, uploads only daily totals, and associates them with the Strava athlete ID. The app uses a PKCE-bound, one-time OAuth ticket; its separate sync token is stored in iOS Keychain while only the token hash is stored in KV. Health totals are retained in KV for up to 100 days. Public use also requires upgrading the Strava API app from single-player mode (10 athletes) and requesting Strava review before scaling beyond that. App Store distribution requires an Apple Developer account, a completed privacy-policy contact, signing, device testing, and App Review.
