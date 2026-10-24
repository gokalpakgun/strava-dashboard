# Tempo verification — 24 October 2026

## Reproducible checks

| Check | Evidence | Result |
| --- | --- | --- |
| Worker regressions | `node --test worker/test/*.test.js` | 59 passed |
| Production sleep aggregation | Swift executable built from the app's `TempoSleepAggregation.swift` | 17 assertions passed |
| Disposable live service flows | [GitHub run 40089247110](https://github.com/gokalpakgun/strava-dashboard/actions/runs/40089247110), `live-service-check` | 30 / 30 passed |
| Delivered password-reset flow | Local `outputs/live-password-reset.json` | 10 / 10 passed |
| Native account and HealthKit user flows | Same GitHub run, `simulator-smoke` | 5 UI cases passed |

The live service checks create and remove two disposable accounts. They exercise registration, duplicate rejection, username/email login, wrong-password rejection, onboarding, synthetic Health summary round trips and account isolation, friend request/acceptance, consent-controlled multi-turn coach requests, logout and deletion. No real user's account is modified by this script.

## Password recovery

`apitempo.com` was verified in Resend. Its sending-only API key is restricted to that domain and stored as the encrypted Worker secret `RESEND_API_KEY`. Tracking is not configured and TLS is enforced. No paid plan was selected.

Real Turkish and English reset emails reached Resend's `delivered` state. A delivered link was used against a disposable account: the new password worked, the previous password and session failed, and both the used link and an earlier issued link failed afterward. The disposable account and local credential state were removed. Provider delivery status does not establish inbox placement in a mail client.

Local tests additionally advance the test KV clock beyond the 30-minute expiry and verify direct token deletion even when a prefix listing does not yet include the reset key.

## Native test scope

The suite covers welcome/sign-in forms, the reset sheet, five primary tabs and the manual workout form, social navigation, real registration and three-step onboarding, username/email login, stored Keychain session restoration, and the normal Apple Health connect button with a real account. The last step checks that the production native sync creates a dated server snapshot; it does not invent measurements for an empty simulator.

The HealthKit integration test uses the native system permission sheet and real simulator HealthKit APIs. It writes six tagged samples, reads the exact UUIDs and the production daily aggregator, checks 321 ml water, 1,234 steps and 180 minutes of sleep (core/deep/REM: 60 minutes each; awake: 10 minutes), deletes only those samples, and rereads their UUIDs to confirm cleanup. This helper is excluded from Release and physical-device builds.

Run #15 found a test input selector choosing an inherited icon identifier instead of the editable field. Run #16 exposed the native Password AutoFill save sheet blocking the next action. The suite now uses typed field/button queries, dismisses the save prompt without storing disposable passwords, and captures a screenshot and hierarchy at its first failed account step. Run #17 completed registration, onboarding and Keychain restoration, then found a sign-in request still busy after 50 seconds. Account requests now allow two bounded attempts with 12-second request and 20-second resource timeouts, and no connectivity wait. Debug diagnostics contain only endpoint, method, attempt, status and numeric error code; credentials, request/response bodies and Health values are excluded.

## Boundaries

- Synthetic simulator records do not establish permission to read Apple Watch or other apps' records on a physical iPhone.
- The earlier real Strava browser OAuth/dashboard check does not establish native iPhone deep-link authorization.
- Cloudflare KV operations do not provide atomic uniqueness or single-use guarantees across simultaneous requests in different edge locations. The sequential flows and listed regressions do not prove those distributed guarantees.

Generated screenshots and live reports stay in ignored `outputs/`; generated credentials remain in ignored `.env.*` files only while a test is in progress. No credential belongs in a commit or report.
