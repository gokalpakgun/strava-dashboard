# Cloudflare Worker

The Worker serves the dashboard assets and handles Strava OAuth on the same origin. Strava refresh tokens are stored in the `TOKEN_STORE` KV namespace; the browser receives only an HttpOnly session cookie.

## Cloudflare setup

1. The Worker name is `tempoapi`, matching `wrangler.jsonc`.
2. In **Settings → Variables and Secrets**, add these as secrets: `STRAVA_CLIENT_ID` and `STRAVA_CLIENT_SECRET`.
3. The first deployment creates and binds the `TOKEN_STORE` KV namespace from `wrangler.jsonc`.
4. `wrangler.jsonc` also binds Cloudflare Workers AI as `AI`; the Tempo Koç feature uses the Cloudflare-hosted Llama 4 Scout model.
5. Connect the GitHub repository under **Settings → Builds**. Set the root directory to `worker/` and let Cloudflare use `npx wrangler deploy` as the deploy command.
6. After deployment, open `https://tempo-strava-api.gokalpakgun11.workers.dev/` and use **Strava’ya bağlan**.

When connecting an existing Worker, push a new commit to the selected production branch to trigger its first repository build.

The Strava app's Authorization Callback Domain must be `tempo-strava-api.gokalpakgun11.workers.dev`. The callback URL used by the Worker is `/auth/callback` on that origin.

Do not put Strava credentials in GitHub files. Add or rotate them only in Cloudflare's secret settings. The Worker requests `activity:read_all`, uses OAuth state validation, stores session refresh tokens server-side, and requires the same-origin HttpOnly cookie for activity access.

Tempo Koç runs only after the athlete checks the in-app consent box and submits a request. The Worker sends Cloudflare AI the selected date range, weekly and monthly aggregates derived from sport type, distance, moving time, elevation, average speed and running pace, plus the question text. It excludes activity names, routes, precise locations, and profile details. Coach prompts and answers are not stored by the app.
