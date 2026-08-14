# Red-team review — ADR-0105 upload-phase token refresh plan (security adversary)

Reviewer role: FACT CHECKER + CONTRACT VERIFIER (Standard tier)
Target: `plans/260813-1741-adopt-adr-0105-upload-token-refresh/` (plan.md + phases 1-4)
Source ADR: PR #4755 `docs/adr/0105-upload-phase-token-refresh-for-drive-attachments.md`
Branch: `feat/add_as_attachment`

---

## Finding 1: The session-epoch guard cannot close the resurrection window — `clear()` runs *after* the durable wipe

- **Severity:** Critical
- **Location:** Phase 1, "Post-`clear()` guard" + Implementation Step 2 + Success Criterion 3
- **Flaw:** The plan's whole anti-resurrection argument rests on `_sessionEpoch` being incremented by `clear()`. But logout's durable wipe happens *before* `clear()` is called, and the plan checks the epoch exactly once — immediately after the token-endpoint await — while three further `await`s (and on iOS a fourth) still have to run before the session is durably written.

  `_clearAllData()` order is: `await Future.wait([deleteAuthorityOidcInteractor.execute(), cachingManager.clearAll(), ...])` → **then** `authorizationInterceptors.clear()` → then `cachingManager.closeHive()`. The epoch therefore does not move until after the Hive boxes have already been emptied.
- **Failure scenario:** User starts a 400 MB drive attach. `ensureFreshAuthorizationHeader` enters `_refreshTokenOnce()`, captures `epoch = 0`, and awaits the IdP. User taps logout. `deleteAuthorityOidcInteractor` + `cachingManager.clearAll()` wipe the token box and account box. The IdP responds. `_sessionEpoch` is still `0` (`clear()` has not run yet) → the guard passes → `_updateNewToken`, then `_updateCurrentAccount` runs `persistOneTokenOidc(newToken)` and `setCurrentAccount(...)`, re-writing a live access token and a `isSelected: true` account into the boxes that were just emptied. `clear()` then nulls in-memory state only. On next app start the app finds a persisted, valid OIDC session and auto-logs-in the "logged-out" user. On iOS the same window also re-seeds `saveKeyChainSharingSession`, which is shared with the share extension.

  A second, narrower variant survives even if the ordering were fixed: the epoch is checked once, but `_updateCurrentAccount` awaits `getCurrentAccount()`, `persistOneTokenOidc()` and `setCurrentAccount()` in sequence. A `clear()` landing between `persistOneTokenOidc` and `setCurrentAccount` leaves a *partial* write — live token persisted, account not updated — which the plan's Success Criterion ("no `persistOneTokenOidc`, no `setCurrentAccount`") does not describe or test.

  This window exists today for Dio 401s, but the plan materially amplifies it: it is now reachable from an upload that can sit in `await` for minutes, rather than from a request that fails in seconds.
- **Evidence:**
  - `lib/features/base/base_controller.dart:655-668` — `_clearAllData()`: `await Future.wait([...deleteAuthorityOidcInteractor / cachingManager.clearAll()...])` at `:656-663`, `authorizationInterceptors.clear()` at `:660-661`, `closeHive()` at `:662`
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:673-678` — `clear()` nulls in-memory fields only
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:570-589` — `_updateCurrentAccount`: three sequential awaits (`getCurrentAccount` `:571`, `persistOneTokenOidc` `:576`, `setCurrentAccount` `:586`)
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:371-373` — iOS `saveKeyChainSharingSession` is a fourth await outside the plan's single check point
- **Suggested fix:** Do not derive the guard from `clear()`. Either (a) bump the epoch as the *first* statement of `_clearAllData()` (a separate `beginSessionTeardown()` on the interceptor) so the guard leads the wipe, and re-check the epoch immediately before *every* durable write inside `_refreshTokenOnce`; or (b) make the durable write section a single guarded critical section that re-reads the epoch and aborts, and add a compensating delete if a write already landed. Success Criterion 3 must be rewritten to test `clear()` arriving *during* `_updateCurrentAccount`, not only before it.

---

## Finding 2: The single-flight memo is per-instance, and the app runs two `AuthorizationInterceptors`

- **Severity:** Critical
- **Location:** Phase 1, "Architecture" / Requirements ("A refresh already in flight is joined, never duplicated"); Phase 4 Step 2 ("exactly one refresh"); plan.md Key decisions
- **Flaw:** The plan (and the ADR) treat `_refreshTokenOnce()` as *the* app-wide single-flight. It is a field on one object, and the app constructs **two** `AuthorizationInterceptors` — the default one and one tagged `BindingTag.isolateTag` — each with its own `Dio`, its own `AuthenticationClientBase`, and its own `_token`. Neither knows about the other; token updates are pushed to both only from the outside (`setDataToInterceptors`). The plan never states which instance `ensureFreshAuthorizationHeader` is called on, and never acknowledges the second one.
- **Failure scenario:** Exactly the scenario ADR-0105 names as its motivation. The user has an OPFS drive attach in flight (resolver bound to the default instance) while a background/isolate request 401s on the isolate instance. Both call `refreshingTokensOIDC` with the *same* refresh token, concurrently. Against an IdP with refresh-token rotation the first rotates it; the second returns `invalid_grant`. On the isolate instance that is a server rejection → `_handleRefreshErrorOnWeb`/`OnMobile` → `clear()` + `RefreshTokenFailedException` → `BaseController.handleRefreshTokenFailedException()` → `clearDataAndGoToLoginPage()`. The user is logged out mid-attach — the precise outcome the memo was introduced to prevent. Worse, with rotation-reuse detection many IdPs revoke the entire token family, so the *successful* refresh on the default instance is also dead.

  Secondary: after the default instance refreshes, the isolate instance's `_token` is stale and nothing propagates the new value, so the isolate's next request 401s and triggers yet another refresh.
- **Evidence:**
  - `lib/features/base/base_controller.dart:79-80` — `Get.find<AuthorizationInterceptors>()` and `Get.find<AuthorizationInterceptors>(tag: BindingTag.isolateTag)`
  - `lib/main/bindings/network/network_bindings.dart:92-100` — instance 1
  - `lib/main/bindings/network/network_isolate_binding.dart:55-63` — instance 2, distinct `AuthenticationClientBase`/cache managers, all `tag: BindingTag.isolateTag`
  - `lib/features/base/reloadable/reloadable_controller.dart:133-139` — the only cross-instance sync, and it is push-only from outside
  - `lib/features/base/base_controller.dart:660-661` — both cleared explicitly, confirming they are independent objects
- **Suggested fix:** Either hoist the single-flight into a shared collaborator injected into both instances (a `RefreshTokenCoordinator` singleton keyed on the refresh token), or state explicitly in Phase 1 that the memo is per-instance, that the isolate instance is out of scope, and downgrade Phase 4's "exactly one `refreshingTokensOIDC` call" to "one per interceptor instance". As written, that success criterion is provable only in a unit test with one instance and is false in production.

---

## Finding 3: After logout, the injected capability returns `null` and Phase 3 sends the upload *unauthenticated*

- **Severity:** Critical
- **Location:** Phase 1 Step 4 (`none` → return null); Phase 2 "Architecture" (**Null means "send no Authorization header"** … "is not an error"); Phase 3 Requirements + Success Criterion 5
- **Flaw:** `clear()` sets `_authenticationType = AuthenticationType.none`. The plan makes `none` indistinguishable from "session was destroyed": both return `null`, and all three phases explicitly define `null` as *not an error* — the XHR simply omits the `Authorization` header. There is no signal that lets the uploader tell "this deployment has no auth" from "your session was just revoked".
- **Failure scenario:** User is mid-upload of a drive file. Session dies (refresh rejected on the *other* interceptor, or the user logs out on another tab / hits the logout button). `clear()` runs; auth type becomes `none`. The uploader's XHR 401s, the retry-once path fires `resolveAuthHeader(forceRefresh: true)`, `ensureFreshAuthorizationHeader` takes the `none` branch and returns `null`, and Phase 3 then re-sends the whole staged file **with no Authorization header at all** to `request.uploadUri`. The retry is guaranteed to fail, but the client has just POSTed the full file body of a (potentially confidential) drive document to a server-supplied URL with no credential and no user context — and, per Phase 3, treated it as a normal transport failure rather than an auth failure, so nothing routes to `handleRefreshTokenFailedException`. On a misconfigured or attacker-controlled `uploadUrl` (see Finding 7) that is an unauthenticated exfiltration of the file body.
- **Evidence:**
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:673-678` — `clear()` sets `_authenticationType = AuthenticationType.none`
  - Phase 1 line 149-150 — "`basic` → return the existing basic header; `none` → return null"
  - Phase 2 line 46-48 — "**Null means "send no Authorization header"**, not the literal string "null" — this is the `AuthenticationType.none` case and is not an error."
  - Phase 3 line 27-28 and 122 — null header ⇒ no `Authorization` header, asserted as a success criterion
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:130-131` — the header is applied unconditionally today
- **Suggested fix:** Make "no session" a distinct outcome. `ensureFreshAuthorizationHeader` should capture the auth type *at construction of the resolver closure* (or throw `RefreshTokenFailedException` when the type transitions to `none` after having been `oidc`/`basic`). `null` should only ever be returned when the session was configured as `none` from the start. Phase 3's retry must abort — not resend — when the resolver returns a different-shaped answer than the first attempt did.

---

## Finding 4: `oidc` with a null `_configOIDC` is not short-circuited, and the null-check crash now poisons a shared memo

- **Severity:** High
- **Location:** Phase 1, "Three rules from ADR-0105" rule 2, and Step 4's gate list
- **Flaw:** Rule 2 short-circuits only `basic` and `none`. The codebase treats "`oidc` **and** `_configOIDC != null`" as a *separate* precondition (`_isAuthenticationOidcValid()`), and has a dedicated forced-logout tag for the state the plan ignores. `setTokenAndAuthorityOidc` accepts a **nullable** `newConfig`, so `_authenticationType == oidc && _configOIDC == null` is a reachable state, not a theoretical one. The plan's gate is only `type == oidc` + has-refresh-token + expired/force, which does not exclude it.
- **Failure scenario:** Token restored from cache with a config-load failure (or an FCM cold start that sets the token before the OIDC config resolves). A drive upload calls `ensureFreshAuthorizationHeader`; the token is expired; the plan enters `_refreshTokenOnce()` → `_getNewTokenForOtherPlatform()` → `_invokeRefreshTokenFromServer()` → `_configOIDC!.clientId` throws `_TypeError` (null check on null). Because the memo is now **shared**, a concurrent Dio 401 that joined the same future receives the same `_TypeError` — the crash propagates into `_refreshTokenThenRetry`'s generic `catch`, which on web routes it into `_handleRefreshErrorOnWeb` and classifies it as a non-rejection ("keep session"), so every subsequent request retries forever against a config that can never load. And the off-Dio caller gets a `_TypeError`, not the `RefreshTokenFailedException` that Phase 1's own requirement promises ("A rejected refresh clears the session and throws `RefreshTokenFailedException`"). Phase 3 then wraps it as `DioExceptionType.unknown` via `_asDioFailure`.
- **Evidence:**
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:504` — `_isAuthenticationOidcValid() => _authenticationType == oidc && _configOIDC != null`
  - `:178-181` — `_classifySkippedRefresh401` has an explicit `forced_logout_401_oidc_config_missing` branch, proving the state occurs in production
  - `:72-77` — `setTokenAndAuthorityOidc({TokenOIDC? newToken, OIDCConfiguration? newConfig})`, both nullable, sets `_authenticationType = oidc` unconditionally
  - `:610-618` — `_configOIDC!` ×4 and `_token!` ×1
  - `:621-622` — iOS path additionally dereferences `_token!` before the keychain lookup
- **Suggested fix:** Reuse the existing gate verbatim: `ensureFreshAuthorizationHeader` must require `_isAuthenticationOidcValid() && _isTokenNotEmpty(_token) && _isRefreshTokenNotEmpty(_token)` before entering the refresh chain — i.e. the same predicate `validateToRefreshToken` applies minus the 401 term. Anything else returns the current bearer. Add a test for `oidc` + null config.

---

## Finding 5: The G1 fix silently changes the Dio path's forced-logout classification — contradicting Phase 1's own requirement

- **Severity:** High
- **Location:** Phase 1, "G1: the duplicate-token guard" + Requirements ("The Dio 401 path behaves exactly as today, including its forced-logout classification and Sentry tagging")
- **Flaw:** The plan says "only the caller that *performed* the refresh evaluates it". The plan analyses only the case where the Dio caller performs and the drive caller joins. The reverse is now equally likely and is the *common* case for a long upload: the OPFS uploader calls `ensureFreshAuthorizationHeader(forceRefresh: true)` first, a Dio request 401s a moment later and **joins** the memo (`performed: false`). That Dio caller now skips the duplicate-token guard entirely. Whether an IdP returned the same access token — the condition the tag exists to record — becomes a function of *which caller happened to arrive first*, i.e. non-deterministic. Phase 1's requirement that the Dio path "behaves exactly as today, including its forced-logout classification" is therefore violated by the plan's own fix.

  Compounding: `ensureFreshAuthorizationHeader` never evaluates the guard at all, so on the entire off-Dio path a refresh that returns the *same* credential is reported to the uploader as a successful `forceRefresh`. The uploader then replays the identical bearer on attempt 2, which is a guaranteed second 401 — the retry is spent on a credential already known to be rejected.

  And there is no baseline to regress against: `forced_logout_401_refreshed_token_duplicated` has **zero** test coverage today (0 hits outside the one production line), so Phase 1's Success Criterion "still logs … exactly as today" cannot be verified — there is nothing that captured "today".
- **Evidence:**
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:357-366` — the guard and the `super.onError(err, handler)` that ends the request
  - `:361` — the only occurrence of `forced_logout_401_refreshed_token_duplicated` in the whole repo (`grep -rn "refreshed_token_duplicated" .` → 1 hit, production only; `test/features/interceptor/authorization_interceptor_test.dart` has 88 `test(` blocks, none referencing it)
  - Phase 1 line 29-30 (requirement) vs. line 91-93 (the fix) — direct contradiction
- **Suggested fix:** Have `_RefreshOutcome` carry `isDuplicate` computed **once, by the performer**, and let every joiner read that boolean rather than skipping the check. Add the missing baseline test for the duplicate tag *before* refactoring (it is a prerequisite, not a success criterion). Make `ensureFreshAuthorizationHeader` surface duplicate-on-`forceRefresh` as a failure so the uploader does not burn its single retry on a known-bad token.

---

## Finding 6: Phase 4's flagship cross-cutting test cannot be built, and Phases 2-3's `flutter test workplace/` gate silently skips the changed tests

- **Severity:** High
- **Location:** Phase 4, "Related Code Files" → Create + Implementation Steps 1-3; Phase 2 Success Criteria; Phase 3 Step 6
- **Flaw:** Phase 4 asserts the cross-cutting test can live in the app package "because it needs a real `AuthorizationInterceptors`; `workplace` is a path dependency of the app, so both are importable here." Import-ability is not the constraint — **test platform** is. `authorization_interceptors.dart` imports `dart:io` (and uses `HttpHeaders` throughout), so it cannot compile on the browser test platform. `BrowserOpfsDriveFileUploader` / `OpfsXhrUpload` import `dart:js_interop` and `package:web`, and every existing test for them is `@TestOn('chrome')`, so they cannot run on the VM platform. There is no target where both halves compile. The plan's single strongest verification artifact — the one that proves the refresh/retry contract across the boundary — is unimplementable as specified, and the plan states the opposite as settled fact.

  Separately, Phase 2 Success Criterion "`flutter test workplace/` green" and Phase 3 Step 6 are meaningless gates: `flutter test` defaults to the VM platform, so all five `@TestOn('chrome')` files are **skipped**, including 4 of the 5 test files Phase 2 modifies and both files Phase 3 modifies. Both phases can report green having executed none of their changed tests.
- **Evidence:**
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:3` — `import 'dart:io';`; `HttpHeaders.authorizationHeader` at `:98, :103, :126, :639`
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:3,9` — `dart:js_interop`, `package:web/web.dart`
  - `@TestOn('chrome')` at line 1 of: `opfs_xhr_upload_test.dart`, `opfs_drive_file_uploader_test.dart`, `opfs_drive_file_stager_test.dart`, `opfs_fetch_download_test.dart`, `drive_transfer_strategy_factory_web_test.dart`
  - Phase 4 lines 31-36 (the claim), lines 53-59 (the four suite commands, none of which pass `--platform chrome`)
- **Suggested fix:** Replace the "real `AuthorizationInterceptors`" cross-cutting test with (a) a chrome-platform test in `workplace/test/` driving the uploader against a *fake* `ResolveAuthHeader` that scripts the refresh outcomes, plus (b) a VM test in `test/features/interceptor/` that proves the interceptor side of the contract. Pin the exact commands with `--platform chrome` for the workplace suites, and make "N tests ran, 0 skipped" part of the success criteria.

---

## Finding 7: Declaring the server-supplied `uploadUrl` out of scope is wrong — this design amplifies the exposure

- **Severity:** High
- **Location:** Phase 1, "Security Considerations" ("pre-existing behaviour shared with `FileUploader`, unchanged here and out of scope")
- **Flaw:** The claim "unchanged here" is false in three concrete ways. `Session.getUploadUri` accepts the server's `uploadUrl` as an absolute URL whenever it `hasOrigin` and no `jmapUrl` override is supplied — the origin is entirely server-controlled and never compared to the JMAP origin. Today the OPFS leg sends whatever bearer happened to be resolved at *transfer* start (which the plan itself argues may already be stale/expired). After this change that endpoint receives: (1) a header resolved immediately before `send`, i.e. **guaranteed fresh**; (2) on a 401, a `forceRefresh: true` that **rotates the real refresh token** on demand and hands over a second, newer bearer; (3) two delivery attempts of the full file body instead of one.
- **Failure scenario:** A compromised or hostile JMAP session response returns `uploadUrl: https://attacker.example/upload/{accountId}`. The victim attaches a drive file. Attempt 1 carries a fresh bearer to the attacker origin. The attacker replies `401` with permissive CORS; the client obligingly refreshes (burning and rotating the legitimate refresh token) and re-sends the *whole file body* plus a brand-new bearer. The attacker now holds two access tokens minted seconds apart and the complete file. Under the old `String authHeader` design the attacker got one, possibly expired, token and no refresh trigger. That is a material amplification introduced by this plan, not pre-existing behaviour.
- **Evidence:**
  - `model/lib/extensions/session_extension.dart:53-70` — `getUploadUri`: `else if (uploadUrl.hasOrigin) { uploadUrlValid = uploadUrl; }` at `:57-58`, no origin comparison anywhere
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:69` — `xhr.open('POST', request.uploadUri.toString())` with the raw server URI
  - Phase 1 lines 198-200 — the dismissal
  - Phase 3 lines 51-58 — the per-attempt resolve + `forceRefresh: true` replay
- **Suggested fix:** Do not carry the dismissal forward unchanged. Either add an origin check against `dynamicUrlInterceptors.jmapUrl` in the OPFS leg (one comparison, inside `BrowserOpfsDriveFileUploader.upload`, before the first send), or — at minimum — record in Phase 1 that this plan *increases* the exposure and make the origin check a blocking prerequisite of the wiring PR rather than "worth a separate ticket".

---

## Finding 8: `forceRefresh` is an unrate-limited refresh capability exported as public `workplace` API

- **Severity:** Medium
- **Location:** Phase 2, "Architecture" (typedef) + "Security Considerations" ("narrower than exposing the interceptor")
- **Flaw:** The claim that the capability "can request a header and nothing else" understates it. `forceRefresh: true` is an *authenticated side effect*: it makes the app spend and rotate its refresh token on demand. The memo coalesces only *concurrent* calls — sequential calls each perform a full token request. The only bound in the design is the `retried` flag inside `BrowserOpfsDriveFileUploader.upload`, i.e. in the *consumer*, not in the capability. The typedef lives in `workplace/lib/data/model/workplace_type_defs.dart`, so it is public API of the package; nothing prevents a future strategy, a retry wrapper, or a bug in a `whenCancel` handler from calling it in a loop.
- **Failure scenario:** A future consumer (or a regression that moves the retry flag) drives `forceRefresh: true` in a tight loop against an IdP with refresh-token rotation and reuse detection. Each call rotates; a single overlapping/duplicate use trips the IdP's reuse detector, which revokes the entire token family. Every device and tab for that user is logged out, and the client cannot tell why — the local classifier will see `invalid_grant` and call it a normal server rejection.
- **Evidence:**
  - Phase 2 lines 36-37 (typedef) and 108-111 (the security claim)
  - `workplace/lib/data/model/workplace_type_defs.dart` — public typedefs, no visibility annotation; `workplace/pubspec.yaml` confirms no `get` dependency, so the capability is the only channel — and it is unguarded
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:610-618` — every invocation is a real token-endpoint call; there is no throttle anywhere in the chain
  - ADR-0105 "Risks" itself names rotation as the hazard, then relies on a memo that only covers concurrency
- **Suggested fix:** Put the bound in the capability, not the consumer: a minimum interval between *performed* refreshes (e.g. ignore `forceRefresh` if a refresh completed within the last N seconds and the token it produced is still unexpired) inside `ensureFreshAuthorizationHeader`. Cheap, one field, and it makes the retry-once flag a defence-in-depth rather than the only defence.

---

## Finding 9: The epoch only moves on `clear()` — account/session swap via `setTokenAndAuthorityOidc` is invisible to it

- **Severity:** Medium
- **Location:** Phase 1, "Post-`clear()` guard" ("Re-checking `_authenticationType` alone is weaker — a re-login between the two points restores `oidc`… while still being a different session")
- **Flaw:** The plan correctly identifies that a re-login must invalidate an in-flight refresh, then implements a guard that only fires on `clear()`. `setTokenAndAuthorityOidc` is called on session reload and on FCM cold start **without** a preceding `clear()`, so the identity can change under an in-flight refresh with the epoch untouched.
- **Failure scenario:** A drive upload triggers a refresh for session A. While it is awaiting, `reloadable_controller.setDataToInterceptors` (or `FcmMessageController._handleGetAccountByOidcSuccess`) installs session B's token via `setTokenAndAuthorityOidc`. The refresh for A resolves; the epoch is unchanged so the guard passes; `_updateNewToken(A')` overwrites B's in-memory token, and `_updateCurrentAccount` builds a `PersonalAccount` from `tokenOIDC.tokenIdHash` of **A'** combined with `currentAccount.accountId`, `apiUrl` and `userName` of **B**, then persists it as the selected account. The result is a durable account record pairing one user's identity with another session's token hash, plus a token box entry for A' presented as current.
- **Evidence:**
  - `lib/features/base/reloadable/reloadable_controller.dart:137-140` — `setTokenAndAuthorityOidc` on both instances, no `clear()`
  - `lib/features/push_notification/presentation/controller/fcm_message_controller.dart:194-197` — same, from a push-triggered path
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:578-586` — `PersonalAccount(tokenOIDC.tokenIdHash, …, accountId: currentAccount.accountId, apiUrl: currentAccount.apiUrl, userName: currentAccount.userName)` — token hash and identity come from different sources
  - `grep -rn "authorizationInterceptors.clear"` → only `lib/features/base/base_controller.dart:660-661`
- **Suggested fix:** Increment `_sessionEpoch` in `setBasicAuthorization` and `setTokenAndAuthorityOidc` as well as `clear()` — i.e. make it a "session identity generation" counter, not a "logout" counter. Name it accordingly so the invariant is not re-broken by the next author.

---

## Verification Results

**Tier:** Standard — FACT CHECKER + CONTRACT VERIFIER
**Claims checked:** 41 · **VERIFIED:** 34 · **FAILED:** 3 · **UNVERIFIED:** 4

### Fact-check (sampled ~10/phase)

| Claim (plan location) | Result |
|---|---|
| duplicate-token guard at `authorization_interceptors.dart:357`, `_updateNewToken` at `:367` (plan.md:51-53, phase-01:76-83) | VERIFIED `authorization_interceptors.dart:357,367` |
| `_configOIDC!`/`_token!` deref at `:613-617` (phase-01:63) | VERIFIED `authorization_interceptors.dart:610-618` |
| `validateToRefreshToken` at `:510-533` / `:511` (phase-01:68, phase-04:69) | VERIFIED `authorization_interceptors.dart:510-533` |
| `clear()` nulls in-memory only at `:673-678` (phase-01:104) | VERIFIED `authorization_interceptors.dart:673-678` |
| `_updateCurrentAccount` durable writes at `:570-589` (phase-01:106-108) | VERIFIED `authorization_interceptors.dart:570-589` |
| `_performRetry` awaits the whole retried request, `:456-458` (plan.md:88) | VERIFIED `authorization_interceptors.dart:456-458` |
| `isTokenValid()` = `token.isNotEmpty && tokenId.uuid.isNotEmpty` at `token_oidc.dart:61` (plan.md:61-62, phase-01:57) | **FAILED** — the getter is at `model/lib/oidc/token_oidc.dart:62`, not `:61`. Content correct, citation drifted. |
| `isExpired` returns false when `expiredTime == null`, `token_oidc.dart:66-73` (phase-01:58-59) | VERIFIED `model/lib/oidc/token_oidc.dart:66-74` |
| `handleRefreshTokenFailedException` inherited from `BaseController`, `:291` (phase-04:86) | VERIFIED `lib/features/base/base_controller.dart:291` |
| `RefreshTokenFailedException` in `lib/main/exceptions/remote/authentication_exception.dart` (phase-01:156) | VERIFIED `authentication_exception.dart:17` |
| 13 `authHeader` production sites across 5 files (phase-02:52-59) | VERIFIED — grep returns exactly 12 code sites + 1 doc comment across the 5 named files |
| `drive_transfer_strategy.dart:28,67,76,91,99` | VERIFIED (all 5 exact) |
| `opfs_drive_transfer_strategy.dart:47` | VERIFIED |
| `opfs_drive_file_uploader.dart:23,32` | VERIFIED |
| `opfs_drive_file_uploader_web.dart:63` | VERIFIED |
| `opfs_xhr_upload.dart:26,33,131` | VERIFIED |
| `buffered_web_drive_file_stager.dart:84` is doc-comment only | VERIFIED |
| 5 test files construct/assert `authHeader` (phase-02:63-69) | VERIFIED — grep returns exactly those 5, no others |
| `opfs_xhr_upload.dart:167-176` maps non-2xx → `badResponse` with `statusCode` (phase-03:66-68) | VERIFIED |
| `opfs_xhr_upload.dart:98-103` `onerror` → `connectionError` (phase-03:72-73) | VERIFIED |
| `opfs_drive_file_uploader_web.dart:43` is `upload()` (phase-03:41) | VERIFIED |
| charset sniff uses the same handle at `:58` (phase-03:64) | VERIFIED |
| existing subscription/`finally` pattern at `:87-90` (phase-03:134) | VERIFIED |
| "logWarning/logError interpolate `request.fileName` only, at `:73` and `:139`" (phase-03:141-143) | **FAILED** — `:73` interpolates `request.fileName`; `:139` (`'charset sniff failed: $e'`) interpolates neither `request` nor `fileName`. |
| `opfs_xhr_upload.dart:50` doc comment says the header is read once (plan.md:23) | VERIFIED `opfs_xhr_upload.dart:49-50` |
| OPFS sweep is 4h-scoped (phase-03:61-63) | VERIFIED `opfs_file_ops.dart:87-90` (`Duration olderThan = const Duration(hours: 4)`) |
| `test/features/interceptor/` exists, `.mocks.dart` sibling present, `test/features/login/...` does not (phase-01:122-125, phase-04:60-61) | VERIFIED — `authorization_interceptor_test.dart` + `authorization_interceptor_test.mocks.dart` |
| `DriveTransferPipeline`, `ResolveAuthHeader`, `updateUploadProgress` → 0 hits under `lib/` and `workplace/` (plan.md:71-72, phase-04:80-81) | VERIFIED — 0 hits each |
| `UploadController` progress mapping at `:98` and `:154` (phase-04:90-96) | VERIFIED — `(success.progress * 100 / success.total).floor()` at both lines |
| `workplace` has no `get` dependency (plan.md:94) | VERIFIED `workplace/pubspec.yaml` |
| `BaseOptions` default `Content-Type: application/json` at `network_bindings.dart:60-64` + `constant.dart:3` (plan.md:91-92) | VERIFIED (map is `network_bindings.dart:60-63`; `constant.dart:3`) |
| `QueuedInterceptorsWrapper` single `_errorQueue`, `dio-5.2.0/lib/src/interceptor.dart:364-410` (plan.md:86-88) | VERIFIED (`QueuedInterceptor` at `:364`, `_errorQueue` at `:367`) |
| `StagedFileUploader` typedef exists to copy the pattern from (phase-02:36) | VERIFIED `workplace/lib/data/model/workplace_type_defs.dart` |
| "the resolved header … is never logged" (phase-01:193-195) | UNVERIFIED for the *whole chain* — true inside the uploader (`DioException.toString()` at `dio-5.2.0/lib/src/dio_exception.dart:202-208` emits no headers; Sentry `_sanitizeRequest` strips them, `core/lib/utils/sentry/sentry_initializer.dart:120-140`), but the refresh chain the new API invokes logs the **full access token** at `authorization_interceptors.dart:76` and `:80`. Debug/console-only in practice (`ConsoleLogHandler.canHandle`), so not a release leak — but the plan's blanket claim is broader than what holds. |
| Phase 4: cross-cutting test can host a real `AuthorizationInterceptors` + `BrowserOpfsDriveFileUploader` in one file (phase-04:31-36) | **FAILED** — see Finding 6. `dart:io` vs `@TestOn('chrome')` are mutually exclusive test platforms. |
| Phase 1: "Dio 401 path behaves exactly as today, including forced-logout classification" (phase-01:29-30) | **FAILED** as a consequence of the plan's own G1 design — see Finding 5. |
| ADR text matches the plan's summary of it (deviation is G1 only) | VERIFIED against `gh pr diff 4755` — the ADR's post-`clear()` guard is "re-checks the auth type after the await"; the plan's epoch is a deliberate, documented strengthening. |
| ADR names `UploadController.updateUploadProgress`, which does not exist | VERIFIED — 0 hits repo-wide; ADR text confirmed in the PR diff |

### Contract verification (interface changes → consumer counts)

| New/changed interface | Consumers found |
|---|---|
| `ensureFreshAuthorizationHeader` (new public method) | **0** production callers after Phases 1-4 (wiring deferred). Reachable from **any** call site via `Get.find<AuthorizationInterceptors>()`; 2 live instances exist (`network_bindings.dart:92`, `network_isolate_binding.dart:55`); 3 existing external consumers of the class today (`base_controller.dart:79,80`, `fcm_message_controller.dart:177`, `composer_attachment_extension_registry_provider.dart:20`). |
| `_refreshTokenOnce()` memo (new private) | 2 intended callers (`_refreshTokenThenRetry`, `ensureFreshAuthorizationHeader`) × 2 instances = 2 independent memos at runtime (Finding 2). |
| `_RefreshOutcome` (new private type) | 2 producers/consumers, all in-file. No test currently asserts on the duplicate-token tag it exists to preserve (0 hits in `test/`). |
| `ResolveAuthHeader` replacing `String authHeader` on 4 request classes | Production: **12** code sites + **1** doc comment, across **5** files (exactly as enumerated in Phase 2). Tests: **5** files, **10** sites (`drive_transfer_strategy_test.dart:74,141,152`; `opfs_xhr_upload_test.dart:118`; `buffered_web_drive_file_stager_test.dart:247,275`; `opfs_drive_file_uploader_test.dart:52,94`; `opfs_drive_file_stager_test.dart:685,701`). No `.mocks.dart` in `workplace/test/` references `authHeader` — 0 mock regeneration needed there. 4 of those 5 test files are `@TestOn('chrome')`. |
| Nullable `XhrUploadFileRequest.authHeader` | 2 production sites (`opfs_xhr_upload.dart:26` decl, `:131` use) + 1 construction site (`opfs_drive_file_uploader_web.dart:60-66`) + 1 test construction (`opfs_xhr_upload_test.dart:118`). Count is 4. |
| `int _sessionEpoch` | 1 incrementer as specified (`clear()`); **3** session-identity mutators exist (`clear()`, `setTokenAndAuthorityOidc`, `setBasicAuthorization`) — see Finding 9. |
| `test/features/interceptor/authorization_interceptor_test.dart` | 88 `test(` blocks that must stay green through the Phase 1 refactor; `.mocks.dart` sibling regenerates via build_runner (as the plan states). |

---

## Unresolved questions

1. Which `AuthorizationInterceptors` instance is the drive resolver bound to — default or `BindingTag.isolateTag`? The plan never says, and the answer changes both the single-flight guarantee and which `_token` the retry uses.
2. Is the epoch expected to guard the iOS `saveKeyChainSharingSession` write, which happens in `_refreshTokenThenRetry` (`:371-373`) and not inside the memo as drawn in Phase 1's architecture diagram? The diagram places `keychain(iOS)` inside `_refreshTokenOnce()`; Step 2 also says so; the current code has it in the caller. Which one moves?
3. What is the intended behaviour when `ensureFreshAuthorizationHeader` is called on a session that was `oidc` and is now `none` (post-`clear()`)? Finding 3 assumes the plan's literal reading (return null, upload unauthenticated). If that is not intended, all three phases need the contract rewritten.
4. Given the wiring PR is deferred, is there any user-visible benefit shipped by Phases 1-4 at all? The plan refactors live auth code with 0 production consumers of the new entry point and defers the only empirical gate (Phase 4 step 4) to a later PR. If the answer is "no", the risk/benefit ordering should be reconsidered — land the wiring behind a flag in the same PR, or land the interceptor change last.
