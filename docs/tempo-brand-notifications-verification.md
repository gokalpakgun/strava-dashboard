# Tempo brand, notifications and workout history

## Implemented
- A single vector T source generates the iOS icon, transparent animated launch mark and web mark. There are no neon effects.
- The root background and glass tab bar remain outside the screen transition. Reduce Motion is respected.
- An authenticated notification inbox, per-type preferences and opt-in daily, weekly and milestone reminders.
- Friend request, acceptance and challenge invitation events create an inbox notice and an APNs alert for eligible registered devices. No health values, coordinates or private activity details enter the alert.
- Device registrations are tied to a live account session. Logout/account deletion removes registrations. Token reassignment cannot deliver one account's alerts to another.
- Apple Health workout import reads 90 days, including tennis and basketball. Weekly summaries, activity filters and per-sport history use the same on-device ledger. Matching Tempo/Health copies count once.
- Strava API records remain an independent, source-labelled direct display. They do not enter this ledger, Tempo totals, goals, scores, social competitions or AI input.

## Verification evidence
- Initial implementation: GitHub iOS Simulator Smoke Test run 40110404277 passed all 7 UI tests on iPhone 17 Pro. This included real disposable account registration, onboarding, username/email login, Keychain restoration, real simulator HealthKit sample write/read/delete, notification permission/preferences and repeated tab navigation.
- The updated Worker regression suite passes 85 tests. New checks cover device/session isolation, invalid token cleanup, Apple transport failure, JWT signature and concurrent token signing, preference validation and idempotent registration.
- Added production workout ledger regressions and native UI assertions for weekly count/duration/distance, tennis filtering and a performed basketball sport missing from profile interests.
- Extended the real HealthKit integration to write/read/delete one tennis workout plus the existing six metric/stage samples.
- Added a real disposable-account friend-request-to-native-inbox UI test. This requires the notification Worker routes to be deployed before the final simulator run.

## Deployment facts and limits
- Tempo Push Notifications capability and the App Store profile were renewed. The GitHub signing secret was updated.
- Production APNs credentials are held as encrypted Cloudflare secrets, never in Git.
- A direct Apple production HTTP/2 probe with a deliberately invalid device token returned BadDeviceToken. This verifies provider connectivity, not delivery to a phone.
- Real lock-screen delivery must be checked after installing the new TestFlight build and granting notification permission. Simulator permission/inbox tests do not establish phone delivery.
- Existing users may need to use the workout permission/sync action to grant access to the newly requested HealthKit workout type. HealthKit never reveals whether read access was denied, so an empty result is not presented as proof of authorization.

## Immediate inbox consistency fix

The first final simulator run (40134542214) passed 8 of 9 UI tests, including the new workout ledger/filter UI and real HealthKit tennis import. It exposed a delayed friend-request inbox read in the real account test. The inbox now uses a per-account SQLite Durable Object, with persistence awaited before the social response and only APNs transport scheduled in the background. The previous KV implementation remains a compatibility fallback for isolated unit fixtures; production is configured with NOTIFICATION_INBOX.

Eleven additional regressions cover immediate read-after-write, concurrent duplicate creation, account isolation, mark-read, migration and timed retention. A Windows workerd/SQLite runtime probe also passed ten concurrent creates producing one immediately readable notice, mark-read and cleanup. The iOS notification request disables HTTP response-cache reuse. Final CI must rerun after this fix.
