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

## 26 October: save and invitation follow-up

Personal manual workouts can be saved without optional sensor support and are explicitly labelled unverified; photos do not turn them into verified records or server challenge scores. Optional signal lookup is no longer a mandatory permission/query gate. The manual save action locks synchronously and duration changes avoid a future end time.

Phone running/walking supports an explicit timer-only mode without location permission. Completed elapsed time can be saved even if a GPS route was not obtained; route and distance remain absent and the source is labelled phone timer. Short sessions display seconds rather than zero minutes.

Challenge friends can be selected directly in the creation form, a blank name gets a default, the returned server-created challenge is displayed immediately, and a visible dialog reports success or failure. The social transport has a separate bounded timeout for server name moderation. Scheduled start time is displayed so pre-start scores are understandable. No server safety/moderation bypass was introduced.

At the user’s request, no new full test suite was run for these changes. The next TestFlight archive is the compile/package check; physical-device flows are left for the user’s review.

## 26 October: simplified navigation and modern Health layout

- Distance is shown for running, cycling, walking, hiking and swimming. Court/team sports, fitness and yoga emphasize session count, duration and active days; swimming distance uses metres. This also applies to workout rows and direct Strava activity details. Source measurements are retained.
- The sport list uses smaller headers and two focused metrics; the seven-day chart header now uses that seven-day interval rather than all-time distance. Secondary sport tools expand on demand.
- Home puts Health and the weekly summary first. Optional Strava activities are grouped in a disclosure. The former More tab is now Profile, with aligned rows grouped by purpose instead of a large tile grid. Existing destinations remain reachable.
- Health has a calmer graphite background, a compact daily balance overview and consistently aligned measurement tiles. Sleep, cardio, score factors and water details expand separately. Daily/history selection and underlying metrics remain available.
- Shared metric grids switch to one column at accessibility text sizes. Long titles and summary values can wrap or stack vertically; numerical values use monospaced digits. Existing future UI navigation assertions were updated for the renamed Profile destination, but were not executed.
- Per the user, no build, TestFlight upload or full test run was started for this menu refresh. TestFlight publication is the user’s next step.

## Logo-only launch and recording follow-up

The launch now contains only the centered transparent T mark, enlarged from 140 to 154 points. The existing logo reveal animation and Reduce Motion behavior remain; the decorative circle, radial background and TEMPO wordmark are removed.

Manual and phone workout saves keep their save lock through successful dismissal so a second tap cannot create a duplicate during the closing transition. A started phone session retains its sport and real start time through pauses. A repeated Health connect action during an active sync returns without incorrectly reporting Health as unavailable.

The preceding user-triggered TestFlight run 40238498065 completed successfully. These follow-up changes receive static source/diff review only; no new build, full test suite or TestFlight upload is started.

## 26 October: account, connection and photo lifecycle follow-up

- Profile updates, authentication, password reset and deletion now own their busy state. A response from an invalidated operation cannot replace a later account profile or unlock its request. Logout and social/account responses check the session they started with.
- Strava authorization callbacks and ticket exchange cleanup belong to a specific authorization attempt. Signing out cancels the web authentication session and invalidates pending callbacks. A late restore cannot undo a newer connection/disconnection. Terminal ticket errors stop immediately; canceled work does not retry.
- Water-write completion and loading state cannot spill into a later account session.
- Onboarding, account settings and manual-workout photo tasks cancel with selection changes or screen exit. Late photos cannot overwrite the latest selection. Manual saving waits for photo preparation, and an unreadable attachment displays the existing localized error instead of silently disappearing.
- Only static source and diff review was performed for this batch, as requested. No full tests, simulator run, build or TestFlight upload were started.

## 26 October: recording continuity, social refresh and nearby courts

- Phone GPS distance is accumulated only inside continuous recording segments. Pauses and GPS gaps over 30 seconds start a new segment, with no straight-line distance or map bridge across the unmeasured interval. Old route files remain readable because the new segment marker is optional. Stale/out-of-order coordinates and implausible point-to-point speed are ignored.
- Pause/resume keeps fractional elapsed time instead of losing it at every pause. Leaving the recording screen stops its timer, pending permission start and location updates. Controls are disabled during the successful save transition.
- Social refreshes have response ownership: an older response cannot replace a newer post-action list. Manual refresh buttons are disabled during active requests. Action success messages survive their follow-up refresh and use existing translations. Both friend selectors enforce the same 20-person invitation limit.
- If storing a manual workout fails after its photo was written, the unattached new photo is removed. Optional sensor lookup also checks the original account session before persisting the record.
- Nearby facility matching preserves distinct same-provider courts instead of merging every pair within 70 metres or names within 700 metres. Cross-provider duplicate matching uses a much tighter distance.
- Static source/diff review only; no full tests, simulator, build or TestFlight upload started, per the user's preference.

## 26 October: independent Health reads and fresh daily scoring

- Daily measurements and workout imports now settle independently. A failed daily query preserves the last daily cache, exposes its error and does not prevent a successful workout result from updating Activities, Sports and summaries. Failed reads are never uploaded as empty replacements; a genuinely successful empty read still replaces the previous snapshot.
- Concurrent Health changes are coalesced into one follow-up read after the current sync rather than silently discarded. Account/opt-in changes invalidate the queued work. Resume no longer starts two identical Health syncs for Strava-connected accounts.
- Repeated Health disconnect requests are serialized, so a delayed old DELETE cannot run after reconnect and remove a new server snapshot. Water refresh/write completions respect the selected Health source and opt-in generation.
- Daily Tempo Balance uses measurements from today/yesterday and up to 28 days of baseline history; water uses today only. Older historical measurements remain visible in history but no longer masquerade as current factors. This is a data-freshness correction, not clinical validation of the existing score.
- Workout read failures are now visible in Health, Activities and Sports. Previously the error was stored in the model but had no UI consumer.
- Internal Health day keys and their parser explicitly use the Gregorian calendar, matching HealthKit exports even when the phone uses another display calendar.
- Static source/diff review only. No full test suite, simulator, build or TestFlight upload was started.

## Balance visibility correction requested by the user

The previous freshness cutoff hid Tempo Balance for users whose latest available measurements were older than yesterday. This changed feature availability without being requested. The cutoff is removed: the original factor formulas, weights and available-history baseline are preserved, and the latest available measurements can produce the score again. Home, Health and balance details display a localized measurement date/range when inputs are from different dates or an earlier day. Missing measurements are still not fabricated. The independent Health read, sync and water-source bug fixes remain in place. No build or TestFlight upload was started.

## Consolidated source audit — 26 October

Scope: registration/login/reset/profile persistence, Strava authorization/restore/dashboard, phone/manual workout persistence and route display, weekly/monthly ledger summaries, Health read/sync/disconnect/scoring, Coach request/history lifecycle, friend/challenge actions, notifications/reminders and facility search. This is source review, not a claim of exhaustive runtime verification. Existing features and the no-measurement/no-score guard remain present.

### Fixed in this consolidated pass

- Notification binding, permission completion, inbox loading and APNs registration results now check their owning account/session. Account changes reset stale loading and error state without allowing old completions to unlock the new request. APNs writes remain serialized across accounts.
- A new inbox event during an active load queues one follow-up refresh. Locally read notifications do not become unread again when an older server snapshot arrives. Achievement tracking checks the workout account and retains previously earned IDs through temporary empty loads.
- Reminder scheduling is serialized and versioned. A late scheduling completion after logout or a preference change is removed before the latest preference is scheduled. Logout/account switch also clears pending achievement alerts. The APNs device token is retained as device identity, and registration is renewed at least daily while the app remains alive, matching the server record's finite lifetime.
- Facility provider failures are distinguished from successful empty searches. Failed/partial results are not cached as a complete empty search for ten minutes. Existing partial places remain visible; localized error text and an explicit retry action are available. If location permission was denied, the explicit permission action opens iPhone settings instead of looping on the same denied request.
- Strava dashboard cancellation/session-generation checks run before consuming a response. Terminal API/decode errors stop immediately; they no longer fall through into an unintended second attempt.
- Phone routes longer than the existing 12,000-point storage budget are sampled across their whole duration instead of truncating the end. Endpoint and pause/gap boundary information are retained.

### Reviewed paths retained from earlier fixes

| Area | Source review outcome |
| --- | --- |
| Account/auth/profile | Session ownership, bounded transport, cancellation, password-reset endpoint and photo preparation/save gates retained. |
| Manual/phone saving | Save locks, local unverified/timer labels, photo rollback, original start time and pause-safe GPS segments retained. |
| Activity/Sports/week/month | Shared deduplicated local/Health ledger and sport-appropriate metrics retained. |
| Apple Health | Independent workout/daily reads, coalesced refreshes, ordered disconnect cleanup and water-source ownership retained. A score still requires actual supported measurements. |
| Coach | One owned request, bounded conversation, cancellation and account ownership retained; no Strava data added to Coach context. |
| Friends/challenges | Shared social transport and response ownership retained; moderation is not bypassed. |
| Branding/navigation | No menus, score rings, logos or existing feature destinations removed. |

Build 40324756292 (#46) was verified already cancelled. No new workflow, simulator, full test suite or TestFlight upload was started. Static checks cover whitespace/diff integrity, retained Swift declarations and duplicate/missing localization keys. Physical-device and live-service behavior is not asserted from these checks.

## 27 October: Coach, localization, export and storage follow-up

- Coach previously requested a 90-second timeout through a URLSession with a 30-second resource cap. It now has a dedicated cancellable 90/100-second session, fails promptly when offline and distinguishes timeouts from connection failures. This fixes the concrete timeout mismatch; no first-request live-account success guarantee is inferred from source review.
- The composer uses a bottom safe-area inset for keyboard avoidance. The custom app tab bar yields while Coach is visible and returns when leaving it. Chat privacy controls remain available above the conversation; the keyboard is no longer explicitly dismissed on every send. A failed request does not overwrite a newer draft. Per the user's clarification, no separate Coach retry button was added.
- The Coach system instructions explicitly cover all sports, including rules, technique, tactics, training, equipment and adapted/beginner options. General questions do not require a month selection or Health connection. Health consent and the exclusion of Strava context remain unchanged.
- Cloudflare `tempoapi` deployment succeeded with existing variables preserved: version `f062f681-1f2f-48a3-b60b-0b0f37dc3136`. Wrangler reported the existing KV, AI, assets and notification-inbox bindings. The static asset publication also included the two repository privacy pages that differed from the previous deployment. No credentials are stored in this repository.
- Missing English keys were added for Activities, Water, Longest session, Effort, Enjoyment, Hiking and several connection/account status messages. Both shipped string tables were checked for duplicate keys; new required copies are present.
- Profile-card gallery export submits the original PNG bytes through PhotoKit's resource API rather than handing over a UIImage for implicit re-encoding. Permission denial offers Settings, asynchronous completion belongs to its original screen/account and share actions guard against duplicate temporary files.
- An unreadable saved-workout file is no longer silently treated as a new empty collection that can overwrite existing records. Its error remains visible, saving/deletion retries the read and proceeds only when successful, and the previous file is preserved on failure. Workout deletion errors are now surfaced in Activities.
- Static JavaScript syntax, source declaration inventory, localization keys and diff integrity were checked. No full tests, simulator run, native iOS build or TestFlight upload was started. Native layout/export behavior remains for the user's device review.

## 27 October: challenge responses and cancelled connection restores

The production challenge configuration issue was resolved separately by replacing the invalid moderation administration token; the safety gate remains enabled. A targeted live flow using two disposable accounts passed signup, friendship, challenge creation (201), receipt and acceptance (200), and account cleanup. Credentials and the token value are absent from this report and Git.

The native follow-up consumes the challenge object returned by accept/decline/sharing mutations and retains it until the read snapshot agrees with the user's new state. A stale snapshot cannot revert a successful acceptance or sharing choice. Declined invitations remain hidden as in the server list, local responses are deduplicated, and blocking someone clears associated local overlays before refreshing. New text typed while a previous friend/challenge request is in flight is preserved rather than cleared by that previous request's success.

Strava restore attempts now have request ownership. Concurrent callers do not unlock an active restore, cancellation clears its attempt flag for a later foreground retry, renewed Tempo tokens permit a fresh restore, and choosing to skip Strava invalidates an outstanding restore response. Existing OAuth and disconnect generation checks remain intact.

The user-triggered build 40414108075 succeeded on c5f7885. The newer native changes above received static source/diff review only; no new build, full test suite, simulator run or TestFlight upload was started. No feature or destination was removed.

## 27 October: location permissions, route decoding and recording time

- Revoking facility-location permission invalidates in-flight searches, clears their location/cache/results and retains the selected sport/radius for a later authorized lookup. Delayed location failures cannot replace the permission explanation. Stale/invalid location callbacks are rejected; approximate location remains supported.
- Facility cache reuse now checks both age and origin proximity. Distances are recalculated and sorted against the current location, with the selected radius reapplied. Invalid OpenStreetMap coordinates are rejected before map display.
- Malformed Strava polylines fail safely instead of permitting unchecked bytes, shifts, coordinate overflow or incomplete routes. Valid encoded routes remain supported.
- Phone workout duration uses monotonic uptime, preserving fractional pause/resume time without jumping when wall-clock settings change. Backgrounding cancels a pending permission-triggered start; revoking GPS permission pauses an active route recording and ignores delayed GPS callbacks. Timer-only recording remains available.
- Static source inventory and diff integrity checks only. No full test suite, simulator, native build or TestFlight upload was started. No feature, score or destination was removed.

## 27 October: Strava replacement requests, Health token renewal and workout ownership

- Changing the mobile Strava token invalidates the previous dashboard request generation and releases its loading gate. A reload for the replacement token can start immediately; the old response/defer cannot update or unlock the replacement request.
- Health authorization belongs to the Tempo account and Health opt-in generation, so a bearer-token renewal for the same account cannot leave authorization permanently busy. Coalesced sync work uses the current account token on its next pass instead of discarding the queued read because the previous token changed.
- Manual workout signal queries settle independently. An unavailable heart-rate, respiration or other Health stream no longer discards successful measurements or prevents the independent phone-pedometer lookup. Missing readings stay nil/empty; existing support thresholds and unverified-record labels are unchanged. Cancellation is checked before and after the parallel Health reads.
- Local workout writes use an account-session identifier, including across logout/login to the same account. Manual and phone recording screens dismiss on a session change, and save actions reject stale screens before writing. An in-flight manual signal lookup rechecks the session before saving. Ordinary token renewal for the same session no longer rejects a local workout save. Manual form fields are frozen during saving, preserving the submitted snapshot.
- Added the English translation for the changed-account workout error. Static source declaration, string-table and diff checks only; no full tests, simulator, native build or TestFlight upload started. No feature or existing score was removed.

## 27 October: prefer native Strava authorization

- With Strava installed, Tempo now requests a server-prepared Strava app authorization URL and opens the official strava://oauth/mobile/authorize route. The Info.plist query allowlist includes strava. Without Strava, or if preparation/app launch fails, the existing ASWebAuthenticationSession browser flow remains available. No Strava client secret is included in the iOS app.
- The preparation endpoint uses the same encrypted, expiring OAuth state, PKCE challenge, HTTPS server callback and read scopes as the existing mobile flow. Successful and denied callbacks carry the attempt challenge; the native client ignores a delayed callback for a superseded attempt. A denied request returns to Tempo without exchanging a token.
- Returning manually from Strava releases the busy button while retaining the verifier for a delayed valid return. Choosing to skip or disconnect invalidates pending authorization so its late callback cannot reconnect against that choice. Existing ticket exchange and persistent connection storage are retained.
- Focused existing OAuth state test passed with native preparation, denied callback, invalid challenge and existing web/mobile/tamper assertions. JavaScript syntax, Info.plist XML, Swift declaration inventory, localization uniqueness and diff integrity were checked. No full suite, simulator, iOS build or TestFlight upload was started. Actual app-to-app UI behavior still requires the new iOS build on an iPhone with Strava installed.
- Production Cloudflare version b7af8401-a6b1-4225-8203-546067c14ac1 deployed with existing variables preserved. A synthetic live request returned preparation 200 with the expected Strava destination and a PKCE-bound denial return 302 to Tempo; no Strava account login or permission grant was performed by that check.

## 27 October: approved green/blue branding and focused launch motion

- The user selected the brighter blue/green preview preceding the muted-palette variant. Its flowing T, app-accent green and matching light contact shading are carried into the shared clean vector mark. The navy icon background is a uniform #071B35, with no generated grain. The preview reference is preserved locally in outputs/brand/approved-color-reference.png; generated transparent cutouts with stray edge artifacts were rejected.
- branding/tempo/build.cjs generates all nine opaque AppIcon sizes, the build/app-icon copy, both identical transparent in-app image sets and the web SVG from this one vector. The shared TempoBrandMark used inside TempoProfileShareArtwork therefore supplies the same mark to the card preview, PNG export and share output. No branding assets are left dependent on generated-images paths.
- Launch now uses a one-shot, centered logo focus/scale/fade entrance over a flat app background and a short fade into the next screen. No text, spinner, rings or repeated animation is added. Reduce Motion displays the mark immediately with a shorter minimum hold. Account restoration can keep the settled mark visible without replaying motion; cancelling the launch task no longer completes its delayed state change.
- Asset checks verified catalog dimensions and opacity, identical in-app images, alpha transparency, matching build icon/web source and six uniform navy background samples. Diff/source checks only; no full suite, simulator, native build or TestFlight upload started. iPhone animation timing and exported card layout remain for the user’s new-build review.
- Cloudflare web-mark publication completed with variables preserved: version d2d8e713-a6fb-4472-b629-49e0d90ed246. The iOS assets and launch motion require the next user-triggered build.

## 27 October: simplify Home and inset monthly navigation

- Home now groups weekly workout count, duration and distance/active days into one quiet overview card, followed by four compact shortcuts: movement menu, Coach, nearby sports places and Social. Existing readiness/Health navigation and score ring are unchanged.
- The monthly-progress link sits inside the weekly card with its own horizontal/vertical content padding, a bounded icon, wrapping text and trailing chevron. Its label no longer relies on a secondary-button style that supplied only vertical padding, which put a leading-aligned icon against the rounded rectangle edge.
- Home previews the latest workout with a visible See all route to full history. Routes and the existing Strava activity panel remain under the Strava tools disclosure, with connection/loading/error controls retained. The daily motivational sentence remains as a quiet unboxed footer. No destination, workout record or score was removed.
- Weekly distance now sums only distance-based sports; Health distance attached to court sports cannot inflate that Home metric. All sports still contribute to workout count and duration. Accessibility text sizes use the existing adaptive grid; monthly labels and shortcut titles wrap. English copies were added for Latest workout and See all.
- Source declaration inventory, required destination/identifier checks, string-table uniqueness and diff integrity checked. No full suite, simulator, native build or TestFlight upload started. Final native spacing remains for the user’s next-build review.

## 28 October: account access, outlined metrics, facility matching/scrolling and Social redesign

- Restored a first-row Account settings destination in Profile. The profile identity card now opens AccountSettingsScreen; achievements remain available through their dedicated Profile menu entry. Existing profile editing, sport preferences, security, logout and deletion controls remain intact.
- Home weekly values use padded, lightly tinted rectangular tiles with a visible thin border. Shared primary/secondary actions now have horizontal padding, a minimum touch height and wrapping centered text. Metric captions can grow vertically rather than being clipped to two lines.
- Nearby facilities now use a bounded-height map followed by a real lazy scrolling list of every returned place. Each row has separate select-on-map and directions buttons; names/addresses wrap and the list has the shared bottom navigation clearance. Sport/radius changes own a cancellable search task. Source attribution, location permission, failure/retry and radius controls are retained.
- All 13 sports now have explicit Apple-name and OpenStreetMap-tag matching. Apple matches without evidence of the selected sport are excluded instead of assuming any generic sports complex is relevant. Explicit OSM tags still allow an unnamed court to appear. Removed broad basketball/volleyball/padel aliases; added guards against table/paddle tennis, motorcycling, billiard-pool and court-gym ambiguity. This improves classification using provider metadata; it does not certify venue availability or guarantee provider labels.
- Social now has a compact section selector, an overview with real counters, profile-photo avatars, friend-list search, dedicated add-friend and challenge-composer sheets, selectable challenge participants and visible per-user safety menus. Pending/outgoing requests, acceptance/rejection, blocking/unblocking, reports, leaderboards and per-challenge opt-in sharing remain available. New copy is translated in both shipped language tables. Modal challenge feedback is presented by the currently visible sheet.
- Static checks cover retained Swift declarations, account/map/social destinations and identifiers, matching coverage for all sport choices, duplicate localization keys and diff integrity. Existing social refresh, answer, challenge creation/response/sharing and moderation operation bodies were verified unchanged. No simulator, full test suite, native build or TestFlight upload was started, following the user’s preference. Final native layout and live venue metadata remain for the user’s next-build review.

## 28 October: explicit challenge consent and friend/challenge management

- Challenge creation now requires an explicit sharing choice before sending; joining an invitation first opens a large Health consent screen. It offers the native Apple Health connection/authorization action when disconnected, a visible connecting/error state, and separate share/continue-without-sharing actions. Connecting Health does not silently opt into challenge sharing. Both creation and acceptance record only an explicit boolean opt-in in the same server operation; older clients remain private by default. Existing challenge cards expose a full-size sharing-management action. Missing measurements still do not produce a score.
- Added confirmed friend removal from the per-friend menu. The authenticated API removes both friendship entries, supports retry after a partial storage write, and preserves other friends, block/report controls and existing challenges. Confirmation explains that those challenges remain and sharing can be turned off separately.
- Added a visible creator-only Cancel challenge action and confirmation. The server enforces ownership and stores a cancellation tombstone so a delayed acceptance/share write cannot restore the challenge. Snapshot loading prunes cancelled invitations for all participants. Cancellation remains available if text moderation configuration is temporarily unavailable.
- Successful friend requests always dismiss the add-friend sheet. Successful challenge creation also closes its composer and selects Challenges. Home quick-access tools now have subtle horizontal and vertical separators; all four existing destinations remain.
- Focused backend checks cover symmetric/idempotent removal, partial-write repair, unauthorized cancellation, cancellation surviving a stale record write, explicit creator sharing and atomic acceptance/sharing. The four targeted tests passed. New copy is translated in English and Turkish. Native source/declaration/localization and diff checks are used here; no full suite, simulator, native build or TestFlight upload is started. Apple Health permission presentation and the final native layout require the user’s next-build device check.

## 28 October: system, light and dark appearance

- Added Appearance under Profile and inside Account settings. The three choices are System, Light and Dark, with an accessible selected state and a shared device-local AppStorage preference. The root scene applies that preference so launch, authentication, navigation, sheets and subsequent launches use it; System inherits the iPhone’s current and scheduled appearance. No account or health setting is changed by switching themes.
- Removed the Info.plist Dark override and all view-level forced-dark preferences, including workout/photo/map and password-reset sheets. Shared backgrounds, cards, raised surfaces, text, secondary text, chart/grid tracks, glass navigation and button labels now use adaptive semantic colors. Light accents use darker green, blue, orange and purple for contrast; dark colors retain the established palette. Primary actions use a separate adaptive foreground to remain readable on both accent palettes. A fixed dark activity gradient was replaced with themed tints.
- Both languages include all appearance labels/help text. Declaration retention, preference wiring, duplicate/missing translation keys, override removal and diff integrity checked. The four light accent/white foreground combinations calculate above 5.6:1 contrast. The PNG artwork’s fixed design, photo-processing black fill, branding assets and Strava authorization-button artwork were preserved. No backend deploy was needed. No full suite, simulator, native build or TestFlight upload was started; final native rendering remains for the user’s next-build review.

## 28 October: Health dashboard and seven interactive wellness features

- Reorganized Health around a large real Balance ring, daily steps/exercise/water indicators, the latest measured sleep with core/deep/REM durations, and calm themed cards. Missing measurements remain unavailable rather than inventing a score or sleep waveform. All existing day selection, 90-day history, eight measurement tiles, detailed sleep assessment, cardio/fitness, Balance factors, workout errors, last-sync time, synchronization, disconnect and permission controls remain available under clearly named sections/destinations. The Health tab now supplies its navigation stack without nesting another stack when Health is opened from Home or Profile.
- Added offline breathing (1/3/5 minutes), a five-minute text-guided relaxation session, a two-minute movement break with four step illustrations, and a three-minute evening pause. These have a timed ring, start/pause/resume, optional haptics and Reduce Motion support. Backgrounding pauses; navigating away closes without saving. Only the complete selected duration adds a completion record. Favorites launch the chosen routine with its default duration in one tap. Recent completions remain visible locally.
- Added daily 1–5 energy/mood/tiredness check-ins, same-day editing and seven recent entries. These are labeled as subjective local notes and do not alter readiness, become workouts or contribute verified competition scores. Favorites, check-ins and sessions are persisted separately per Tempo account on this device, with bounded history, corrupt-data write protection and cleanup on account deletion. They are not sent to Coach, friends or a new service.
- Water supports 200/250/500 ml quick additions, a custom amount, editable personal goal and undo of the latest tracked entry. It works locally without Strava/watch/Health. When Health is connected, new entries use the existing dietary-water permission; older local entries are not silently exported. Local notes and Health totals are distinguished in help text. Health undo uses the tracked sample UUID, app-source ownership and an app marker, preserving other providers’ samples. Apple’s documented async deletion API only permits deleting the app’s own saved objects and still respects revoked write permission: https://developer.apple.com/documentation/healthkit/hkhealthstore/delete(_:withcompletion:)-78l1m
- Added the new Swift file to the committed Xcode project as well as the existing Sources directory workflow. All new copy is translated in English/Turkish and uses the shared light/dark palette. Source checks covered retained declarations, balanced delimiters, localization completeness/duplicates, project references, pause/account guards and the ownership-restricted water path. No full suite, native compiler, simulator or TestFlight upload was run; final timing, haptics, Health permission behavior and native layout require the user’s next-build device check.
