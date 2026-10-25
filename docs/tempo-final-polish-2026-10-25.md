# Tempo final polish — 25 October 2026

## Changes
- Monthly insights now use the same deduplicated Tempo + Apple Health workout ledger as the weekly summary, Activities and Sports. Six calendar months remain visible, including empty months. The chart switches between count, duration and distance, with a selected-month workout list and active-day count.
- The on-device Health workout import covers the last 365 days so monthly and current-year summaries can include older workouts. Daily metric/sleep queries are unchanged. Strava API records remain a separate direct display.
- Monthly insights are reachable directly from Home. Year summary and Eddington use the same local/Health ledger.
- Launch has a short T reveal, restrained moving arc and settling wordmark. Reduce Motion removes the movement.
- More groups existing destinations into personal/community, discovery/health, progress and optional Strava tools. Normal secondary actions no longer appear as destructive red controls.
- Nearby facilities show whichever map provider finishes first, filter results to the chosen radius and update camera longitude as well as latitude.
- Dashboard requests honor cancellation and use generation-based loading ownership. Repeated authorization failure gets at most one automatic recovery instead of an unbounded restore loop. Disconnecting Strava preserves the independent Health water value.
- A failed Health workout query keeps the last successful on-device workout list and exposes an error; a successful empty read still clears it.
- Removed the repeated Update and sync cards from Activities, Sports and monthly insights. Health connection and authorization controls remain in Health.

## Tempo Coach hardening
A user reported a freeze/termination after repeated questions on an iPhone 15. No physical-device crash log was available, so the exact exception or memory-termination cause has not been established.

The code had an asynchronous submission-lock gap, unowned request tasks, nested vertical scroll views and animated ScrollViewProxy calls while chat items were being replaced. The final change locks synchronously before creating a task, owns and cancels the request on Stop/New chat/exit, ignores stale completions, uses one scroll container with native scroll positioning, and keeps errors outside the conversation history. Copying is a context-menu action instead of live text selection in changing lazy chat cells.

Both UI and transport enforce the existing service limits: 12 retained turns, 1,500 UTF-16 units per question, 6,000 per answer and a 48,000-unit request history. Account generations prevent an old completion from clearing a newer request's loading state. Health context remains explicitly opt-in and Strava data is excluded.

## Evidence and release boundary
- Before the last Coach change, 87 backend/localization tests passed, including a fix for a malformed English grade format token.
- The production disposable-account audit passed all 30 checks on 25 October: registration, username/email login, account isolation, synthetic Health round-trip, friend request/acceptance, AI with and without synthetic Health consent, reset configuration, logout and cleanup.
- The initial monthly implementation compiled successfully in GitHub macOS CI and its 32 workout/month regressions passed. The UI stage was cancelled when subsequent changes superseded that revision; this is not a completed final UI test run.
- At the user's explicit request, the new complete simulator run was cancelled and no further full test suite is started for the final Coach revision. The final native check is limited to the TestFlight archive/build; device behavior is to be reviewed by the user.
- No new native simulator or physical-device crash-free claim is made for this final revision.
