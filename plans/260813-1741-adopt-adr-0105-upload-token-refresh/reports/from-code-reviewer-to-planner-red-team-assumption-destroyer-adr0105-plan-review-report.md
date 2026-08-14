# Red-team review — ADR-0105 upload-phase token refresh plan

Reviewer role: ASSUMPTION DESTROYER (fact checker + contract verifier), Standard tier.
Plan: `plans/260813-1741-adopt-adr-0105-upload-token-refresh/`
Branch: `feat/add_as_attachment`. ADR source: PR #4755 (read via `gh pr diff`).

---

## Finding 1: Adding a public method to `AuthorizationInterceptors` breaks 17 generated mock files — Phase 1's "existing suite green between steps" is unachievable

- **Severity:** Critical
- **Location:** Phase 1, "Implementation Steps" step 4 + "Related Code Files" + Risk row "Refactoring live auth on a feature branch"
- **Flaw:** The plan treats mock regeneration as a footnote scoped to one file: *"the `.mocks.dart` sibling regenerates via build_runner"* (phase-01:124-125). In reality `MockAuthorizationInterceptors` is generated into **17** files across the whole app test tree. Mockito emits `class MockAuthorizationInterceptors extends Mock implements AuthorizationInterceptors`; adding a public `ensureFreshAuthorizationHeader` makes all 17 fail to satisfy the interface until regenerated. Phase 1's mitigation ("steps land one at a time with the existing suite green between them") and step 6 (`flutter analyze` + interceptor suite only) will not detect this, because `flutter test test/features/interceptor/` does not compile the other 16 files.
- **Failure scenario:** Dev completes Phase 1 step 4, runs `flutter analyze` and `flutter test test/features/interceptor/` — both green. CI (`.github/workflows/analyze-test.yaml`) then fails compilation on 16 unrelated controller test suites. The dev must run a repo-wide `dart run build_runner build --workspace --delete-conflicting-outputs`, producing a diff across 17 generated files that the plan never budgeted or reviewed.
- **Evidence:**
  - `grep -rln "class MockAuthorizationInterceptors" test` → 17 files, incl. `test/features/base/base_controller_test.mocks.dart`, `test/features/composer/presentation/composer_controller_test.mocks.dart`, `test/features/thread/presentation/controller/thread_controller_test.mocks.dart`, `test/features/login/presentation/login_controller_test.mocks.dart:177`, `test/features/search/verify_before_time_in_search_email_filter_test.mocks.dart:692`.
  - Plan claim scoped to one file: `phase-01-interceptor-refresh-gateway.md:122-125`.
- **Suggested fix:** Add an explicit implementation step: "regenerate all mocks (`dart run build_runner build --workspace --delete-conflicting-outputs`) and run the **full** `flutter test`, not just `test/features/interceptor/`." Enumerate the 17 files in Related Code Files, or state the regeneration diff is expected and unreviewed.

---

## Finding 2: The Phase 4 cross-cutting test cannot exist on any Dart platform — `AuthorizationInterceptors` is VM-only, `BrowserOpfsDriveFileUploader` is web-only

- **Severity:** Critical
- **Location:** Phase 4, "Related Code Files" → Create `test/features/upload/opfs_upload_token_refresh_test.dart`; Implementation Steps 1 and 2; Success Criteria bullets 1-2
- **Flaw:** The plan justifies the file's location purely on package dependency direction (*"`workplace` is a path dependency of the app, so both are importable here"*, phase-04:31-36). Dependency direction is satisfied, but **platform** is not. `AuthorizationInterceptors` imports `dart:io` and calls `File(filePath!).openRead()` — it cannot compile for `--platform chrome`. `BrowserOpfsDriveFileUploader` imports `dart:js_interop` (transitively via `opfs_xhr_upload.dart`) and `package:web` — it cannot compile on the VM. There is no platform on which one test file imports both.
- **Failure scenario:** Phase 4 step 3 runs `flutter test test/features/upload/` (VM, no platform flag). The new file fails to compile with "dart:js_interop is not available on this platform". Switching to `--platform chrome` fails the other direction on `dart:io`. Both the cross-cutting test (step 1) and the four-concurrent-401 test (step 2) — which the plan calls the G1 regression scenario and lists as two of five Phase 4 success criteria — are unbuildable as specified.
- **Evidence:**
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:3` `import 'dart:io';`; `:488-491` `File(filePath!).openRead()`; `HttpHeaders` used at `:98`, `:126`, `:639`.
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:3` `import 'dart:js_interop';`, `:9` `package:web/web.dart`.
  - `workplace/lib/data/datasource/drive_transfer/opfs_drive_file_uploader_web.dart:7` `package:web/web.dart`.
  - Existing precedent: `workplace/test/data/datasource/drive_transfer/opfs_drive_file_uploader_test.dart:1` is `@TestOn('chrome')`.
  - Plan command that would run it: `phase-04-tests-verification-and-deferred-wiring.md:53-59`.
- **Suggested fix:** Split into (a) a chrome test in `workplace/test/` driving the uploader against a **fake** `ResolveAuthHeader` that records `forceRefresh`, and (b) a VM test in `test/features/interceptor/` driving `ensureFreshAuthorizationHeader` concurrency directly. Drop the "one test spanning both" requirement, or replace the real interceptor with a thin platform-neutral seam that both can import.

---

## Finding 3: `RefreshTokenFailedException` cannot pass through `_asDioFailure` — `workplace` cannot import the type, and the current catch-all rewraps it

- **Severity:** Critical
- **Location:** Phase 3, Implementation Steps 4-5 and Requirement *"`RefreshTokenFailedException` from the resolver propagates unchanged"*; Success Criteria *"propagates with its type intact"*
- **Flaw:** Steps 4 and 5 contradict each other and both contradict the boundary Phase 2 deliberately erects. Step 4 says keep `_asDioFailure`'s `unknown` fallback; step 5 says let `RefreshTokenFailedException` "pass through `_asDioFailure` untouched". `_asDioFailure` returns `error` unchanged **only** when `error is DioException`; everything else becomes `DioException(type: unknown)`. `RefreshTokenFailedException extends AuthenticationException`, is not a `DioException`, and lives in the **app** package (`lib/main/exceptions/...`) which `workplace` does not and (per Phase 2's non-functional requirement) must not depend on. So `_asDioFailure` can neither type-test for it nor be told to skip it.
- **Failure scenario:** Refresh is rejected mid-upload. `ensureFreshAuthorizationHeader` throws `RefreshTokenFailedException` inside `_attempt`. The `catch (e)` at `opfs_drive_file_uploader_web.dart:81` catches it and `_asDioFailure` returns `DioException(type: unknown, error: RefreshTokenFailedException())`. The composer-side handler the ADR specifies (`catch RefreshTokenFailedException` → `handleRefreshTokenFailedException()` → save draft + reconnect) never fires; the user's draft is not saved and the session is never reconciled. Phase 3's success criterion silently fails, and the wiring PR inherits a bug the plan asserted was handled.
- **Evidence:**
  - `workplace/lib/data/datasource/drive_transfer/opfs_drive_file_uploader_web.dart:120-128` (`_asDioFailure`, `if (error is DioException) return error;` else wrap as `unknown`), and the catch-all at `:81-86`.
  - `lib/main/exceptions/remote/authentication_exception.dart:17` `class RefreshTokenFailedException extends AuthenticationException`.
  - `workplace/pubspec.yaml:12-31` — deps are `core`, `model`, `dio`, `web`, … no app dependency; Phase 2 success criterion `phase-02:94` forbids adding one.
- **Suggested fix:** Resolve the header **outside** the uploader's `try` (or wrap only the send), so a resolver throw escapes uncaught; or have the app-side resolver closure convert rejection into a `DioException` carrying `RefreshTokenFailedException` in `.error` and specify that the composer unwraps `.error`. Either way state the chosen contract on the `ResolveAuthHeader` typedef in Phase 2.

---

## Finding 4: The freshness check has zero lead time relative to upload duration — the retry becomes the primary mechanism, and each trigger costs a full re-upload

- **Severity:** High
- **Location:** plan.md "Key decisions" → *"Header resolution moves to send time"*; Phase 3 Overview (*"the replay costs no re-download and leaks nothing"*) and Non-functional requirements
- **Flaw:** `_isTokenExpired` is a strict `expiredTime.isBefore(DateTime.now())` with no skew or lead-time margin. Resolving the header "immediately before `xhr.send`" prevents staleness *at t=0* but says nothing about t=0+N minutes. The ADR's stated trigger — *"a batch of large drive files can outlive the access token's TTL"* — is exactly a case a point-in-time expiry check cannot pre-empt. The plan then inherits the ADR's optimism (*"401-driven replay is the exception, not the mechanism"*) without testing it. Worse, the plan repeats the ADR's phrase "costs no re-download" while omitting that it costs a full **re-upload** of the same multi-hundred-MB body; the whole file must be re-sent because a 401 typically arrives only after the body has been transferred.
- **Failure scenario:** Token has 90s of TTL left. `ensureFreshAuthorizationHeader(forceRefresh: false)` sees `isExpired == false` and returns the current bearer. A 400 MB file takes 8 minutes to send. The server 401s at the end. The retry then re-sends all 400 MB, doubling the user's upload. For a batch of N large files this is systematic, not exceptional, and there is no size cap or "refresh if expiring within X" rule anywhere in Phases 1-3.
- **Evidence:**
  - `model/lib/oidc/token_oidc.dart:66-74` — `isExpired` is a bare `isBefore(now)`, no leeway.
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:502` `_isTokenExpired(t) => t?.isExpired == true`.
  - Secondary hazard the plan never mentions: `lib/features/login/data/extensions/token_response_extension.dart:12` and `authentication_token_extension.dart:12` both do `expiredTime: accessTokenExpirationDateTime ?? DateTime.now()` — a provider that omits an expiry yields a token **born expired**, so `ensureFreshAuthorizationHeader` would force a token round-trip before *every* upload, violating Phase 1 success criterion *"performs no network call for a valid token"*. This also makes the plan's Unresolved Question 2 (null `expiredTime`) largely moot for the OIDC path, where it is never null.
- **Suggested fix:** Add a lead-time term to the off-Dio freshness check (`forceRefresh || expiredTime.isBefore(now.add(leeway))`), and state the leeway explicitly. Correct Phase 3's overview to say the replay costs a full re-upload. Note the `?? DateTime.now()` fallback as a precondition to verify.

---

## Finding 5: The session-epoch guard has the same hole it was invented to close — `clear()` is not the only session boundary

- **Severity:** High
- **Location:** Phase 1, "Post-`clear()` guard" and Implementation Steps step 1
- **Flaw:** The plan rejects the ADR's auth-type recheck as "weaker — a re-login between the two points restores `oidc` and passes a type check while still being a different session" (phase-01:114-116), then builds a guard that bumps only in `clear()`. But re-login / session-reload / FCM account restoration call `setTokenAndAuthorityOidc` directly, **without** `clear()`. So the epoch does not move on exactly the "different session" transition the plan cites as the reason the type check is insufficient.
- **Failure scenario:** An OPFS upload starts `_refreshTokenOnce()`. While it is awaiting the token endpoint, `ReloadableController.setDataToInterceptors` (session reload, account switch, or the FCM path) installs a **newer** token via `setTokenAndAuthorityOidc`. The epoch is unchanged, so the memo's post-await branch proceeds: `_updateNewToken` overwrites the newer token with the one derived from the older refresh token, and `_updateCurrentAccount` **durably persists** it (`persistOneTokenOidc` + `setCurrentAccount`). The clobbered session survives restart — precisely the failure class the guard exists to prevent, just via a different door.
- **Evidence:**
  - Only `clear()` caller: `lib/features/base/base_controller.dart:660-661`.
  - Session (re)establishment without `clear()`: `lib/features/base/reloadable/reloadable_controller.dart:138-139` (`setDataToInterceptors`), `lib/features/push_notification/presentation/controller/fcm_message_controller.dart:195-198`.
  - Durable write inside the proposed memo: `authorization_interceptors.dart:570-589`.
- **Suggested fix:** Bump the epoch in `setTokenAndAuthorityOidc` and `setBasicAuthorization` as well as `clear()` — i.e. treat "identity mutated" as the boundary, not "identity cleared". Add a success criterion covering "a refresh resolving after a re-login performs no write".

---

## Finding 6: There are two `AuthorizationInterceptors` instances — the memo is per-instance, so "one shared refresh" and "the app's only non-Dio auth entry point" are both false

- **Severity:** High
- **Location:** Phase 1 Overview and Architecture; plan.md Overview; Phase 4 Deferred item 1 (resolver construction)
- **Flaw:** The plan (and the ADR) reason as if there is a single `AuthorizationInterceptors`. The app registers two: a default-tag instance and a `BindingTag.isolateTag` instance with its own `Dio`, `AuthenticationClientBase`, and cache managers. A `_refreshTokenOnce()` memo is an instance field, so it coalesces nothing across the pair. The ADR's stated motivation for the memo — refresh-token **rotation** causing `invalid_grant` → `clear()` → logout mid-attach — survives untouched between the two instances (the isolate instance is the one behind `FileUploader`'s worker-isolate uploads, i.e. concurrent with a drive upload by construction). The plan also never says which tag `ComposerController` resolves for the resolver closure.
- **Failure scenario:** An IO/isolate upload 401s and the isolate interceptor refreshes. Simultaneously a drive OPFS upload calls `ensureFreshAuthorizationHeader` on the main-tag instance and refreshes with the same (now-rotated) refresh token. The provider rejects the second with `invalid_grant`; `_handleRefreshErrorOnWeb`/`Mobile` calls `clear()` and the user is logged out mid-attach — the exact outcome the ADR cites as the reason for the memo.
- **Evidence:**
  - `lib/main/bindings/network/network_bindings.dart:92` `Get.put(AuthorizationInterceptors(...))`.
  - `lib/main/bindings/network/network_isolate_binding.dart:55-62` — second instance, `Get.put(..., tag: BindingTag.isolateTag)`.
  - `lib/features/base/base_controller.dart:80` `Get.find<AuthorizationInterceptors>(tag: BindingTag.isolateTag)`.
  - Plan text asserting singularity: `phase-01:14-16` ("the app's only non-Dio auth entry point"), plan.md:26-29.
- **Suggested fix:** State explicitly which instance the resolver uses, and either scope the claim ("one refresh per interceptor instance; cross-instance rotation is pre-existing and out of scope, as with multi-tab") or move the memo to a shared holder. Do not leave the ADR's rotation argument implying a guarantee the design does not provide.

---

## Finding 7: `flutter test workplace/` does not run any of the files Phases 2-3 change — they are chrome-only, and CI needs a workflow edit the plan never mentions

- **Severity:** High
- **Location:** Phase 2 Success Criteria (*"`flutter test workplace/` green"*), Phase 2 step 5 (*"treat a clean analyze as the completion signal"*), Phase 4 Implementation Step 3
- **Flaw:** Every drive-transfer test file the plan edits carries `@TestOn('chrome')`. Under the default VM platform those files are **skipped**, so "green" is a vacuous signal for exactly the code under change. CI runs them in a second, hand-maintained step driven by a hardcoded `CHROME_TEST_PATHS` list in the workflow file — any new chrome test must be registered there or it never runs in CI. The plan lists neither the `--platform chrome` requirement nor the workflow file.
- **Failure scenario:** Phase 2 and Phase 3 are declared complete on a green `flutter test workplace/` that ran zero of the five modified test files. A `ResolveAuthHeader` threading mistake or a broken retry ships. If Phase 4's new test is written as chrome-only (the only viable option per Finding 2), it is not in `CHROME_TEST_PATHS` and never executes in CI either.
- **Evidence:**
  - `@TestOn('chrome')` at line 1 of: `workplace/test/data/datasource/drive_transfer/opfs_xhr_upload_test.dart`, `opfs_drive_file_uploader_test.dart`, `opfs_drive_file_stager_test.dart`, `drive_transfer_strategy_factory_web_test.dart`, `opfs_fetch_download_test.dart`.
  - `.github/workflows/analyze-test.yaml:16-25` `CHROME_TEST_PATHS` list; `:74-82` the `flutter test "$rel_path" --platform chrome` loop.
  - Plan commands: `phase-02:93`, `phase-04:53-59` (no `--platform chrome` anywhere in the plan).
- **Suggested fix:** Replace the commands with `(cd workplace && flutter test test/data/datasource/drive_transfer --platform chrome)`, and add `.github/workflows/analyze-test.yaml` to Related Code Files for any new chrome test file.

---

## Finding 8: Phase 3's architecture sketch hoists `getFile` and charset resolution out of the `try`, breaking the uploader's documented failure contract

- **Severity:** Medium
- **Location:** Phase 3, "Architecture" pseudocode block
- **Flaw:** The sketch places `file = store.getFile(handle)` and `charsetFuture = resolveCharset(file)` before `attempt(...)`, i.e. outside any error handling. The current implementation deliberately puts both **inside** the one `try`, and its doc comment explains why in detail: `getFile` throws a bare `DOMException` when the entry has gone, and callers branch on `DioExceptionType`, so everything must funnel through `_asDioFailure`. The sketch silently discards that invariant. Implementation Step 2 ("extract the existing body of `upload()` into `_attempt`") does not say where the try boundary lands, so the sketch is the only guidance.
- **Failure scenario:** The staged OPFS entry has been swept or the tab lost its handle. `_store.getFile` throws a `DOMException`. It escapes `upload()` un-normalised. The composer's chip-failure path, which branches on `DioExceptionType`, cannot classify it — the chip fails with an unhandled/unclassified error instead of a transfer failure, and the cancellation collapse at `:85` (`_throwIfCancelled` in the catch) never runs, so a concurrent cancel surfaces as a browser error rather than `DioExceptionType.cancel`.
- **Evidence:**
  - `workplace/lib/data/datasource/drive_transfer/opfs_drive_file_uploader_web.dart:34-41` (doc comment stating the invariant), `:51-52` (`try` opens before `getFile`), `:81-86` (catch → `_throwIfCancelled` → `_asDioFailure`).
  - Plan sketch: `phase-03-opfs-uploader-late-resolve-and-retry-once.md:46-59`.
- **Suggested fix:** Redraw the sketch with the outer `try` enclosing `getFile`, `resolveCharset`, and both attempts; state that `_attempt` rethrows raw and only `upload()`'s catch normalises.

---

## Finding 9: G1's `performed` flag changes Dio-path behaviour for joiners, contradicting Phase 1's own "behaves exactly as today" requirement

- **Severity:** Medium
- **Location:** Phase 1, "G1: the duplicate-token guard" (*"Joiners never re-run the comparison"*) vs Requirements bullet 5 (*"The Dio 401 path behaves exactly as today, including its forced-logout classification"*)
- **Flaw:** The guard at `:357` is verified exactly as the plan states (comparison at 357, `_updateNewToken` at 367), and G1 is a genuine gap the ADR misses. But the plan's fix over-corrects: with `performed == false` a joining Dio caller skips the comparison entirely. That is not "the same as today"; today every Dio 401 caller evaluates it. Note also the plan's framing is narrower than the actual defect — once the memo owns the assignment, the **performing** caller trips the guard too, not just joiners; the `previousToken` snapshot fixes both, so the `performed` flag is doing separate, unjustified work.
- **Failure scenario:** Provider legitimately returns the same access token (still-valid token, no rotation). Caller A performs the refresh: guard fires, logs `forced_logout_401_refreshed_token_duplicated`, propagates to logout — as today. Caller B joined: skips the guard, sets `_refreshAttemptedKey`, and re-issues its request with the identical token. It 401s again, `hasAttemptedRefresh` is now true, and it is tagged `forced_logout_401_after_refresh_attempted` instead. Same logout, different Sentry tag, plus one wasted round trip — and if caller B is an upload, a wasted full body send. Phase 1's success criterion "still logs `forced_logout_401_refreshed_token_duplicated` exactly as today" holds only for the single-caller case it tests.
- **Evidence:**
  - `authorization_interceptors.dart:357-366` (guard + `_logForcedLogoutFor401`), `:367` `_updateNewToken`, `:375-376` `_refreshAttemptedKey` + `_performRetry`.
  - Divergent tag path: `:122` `hasAttemptedRefresh`, `:171-181` `_classifySkippedRefresh401`.
  - Contradicting plan lines: `phase-01:91-93` vs `phase-01:29-30`.
- **Suggested fix:** Drop the `performed` flag; let every Dio caller evaluate the guard against `outcome.previousToken`. The snapshot alone is sufficient and preserves today's classification for joiners and performers alike.

---

## Finding 10: `ensureFreshAuthorizationHeader`'s error contract is specified only for rejection, and the "same classifier" it names is not reusable off-Dio

- **Severity:** Medium
- **Location:** Phase 1, Implementation Steps step 4 (last bullet) and Requirements bullet 4; Security Considerations (*"the new entry point adds no second classification path"*)
- **Flaw:** The plan specifies exactly one failure outcome — rejection → `clear()` + `RefreshTokenFailedException` — and claims it is "routed through the same classifier the Dio path uses so 'reject vs keep session' cannot drift". But the Dio path's decision lives in `_handleRefreshErrorOnWeb` / `_handleRefreshErrorOnMobile`, whose signature requires a `DioException originalError` and an `ErrorInterceptorHandler`; neither exists off-Dio. Only the `_errorClassifier.isServerRejection` predicate is reusable, and the web handler has **three** branches (rejection → clear+reject; `ArgumentError` with unknown OAuth2 code → Sentry + keep session; everything else → keep session silently), two of which the plan never assigns an off-Dio outcome. The refactor needed to genuinely share the decision is not in any implementation step.
- **Failure scenario:** Web refresh fails with a network blip during an upload. `isServerRejection` is false, so the session must be kept. The plan does not say what `ensureFreshAuthorizationHeader` does: throw (which becomes `DioException(unknown)` in the uploader — see Finding 3 — and fails the chip with no diagnosis), or return the stale header (which produces another 401 and a second full re-upload). Whichever a dev picks, the "cannot drift" claim is unverified and untested — Phase 1's success criteria cover only the rejection case.
- **Evidence:**
  - `authorization_interceptors.dart:50-56` (`_handleRefreshError` signature, requires `DioException` + `ErrorInterceptorHandler`), `:209-253` (three-branch web handler), `:283-285` (`_isRefreshRejectedByTokenEndpoint`), `:287-310` (mobile handler).
  - Plan text: `phase-01:155-158`, `phase-01:193-195`.
- **Suggested fix:** Extract a pure `RefreshDecision classify(Object error)` used by both entry points, and add a Phase 1 success criterion for the keep-session branch: what `ensureFreshAuthorizationHeader` returns/throws on a transient refresh failure.

---

## Verification Results

**Tier:** Standard (Fact Checker + Contract Verifier)
**Claims checked:** 24 · **Verified:** 14 · **Failed:** 7 · **Unverifiable from repo:** 3

### Verified

| # | Claim | Evidence |
|---|---|---|
| 1 | `isTokenValid()` has no expiry term | `model/lib/oidc/token_oidc.dart:62` — `token.isNotEmpty && tokenId.uuid.isNotEmpty` |
| 2 | `isExpired` returns false when `expiredTime == null` | `token_oidc.dart:66-74` |
| 3 | Guard at `:357` sits before `_updateNewToken` at `:367` | exact, no drift |
| 4 | A joining caller would trip the guard once the memo owns the assignment | correct (and so would the performer — see Finding 9) |
| 5 | `_invokeRefreshTokenFromServer` dereferences `_configOIDC!` and `_token!` | `:612-618`; note `_getNewTokenForIOSPlatform` at `:622` also dereferences `_token!`, unmentioned |
| 6 | `clear()` only nulls in-memory fields | `:673-678` |
| 7 | `_updateCurrentAccount` writes durably (`persistOneTokenOidc` + `setCurrentAccount`) | `:570-589` |
| 8 | `validateToRefreshToken` gate | `:510-533` |
| 9 | OPFS sweep is 4h-scoped | `workplace/.../opfs_file_ops.dart:89-90` `Duration(hours: 4)`; single caller `drive_transfer_strategy_factory_web.dart:60` |
| 10 | `OpfsXhrUpload` maps non-2xx to `badResponse` carrying `statusCode` | `opfs_xhr_upload.dart:167-176`; reachable in the uploader because `_asDioFailure` passes `DioException` through (`:121`); the uploader's own `_parseUploadResponse` badResponse has no `response`, so `statusCode` is null → no false 401 |
| 11 | `status == 0` CORS case maps to `connectionError`, not `badResponse` | `opfs_xhr_upload.dart:98-103` |
| 12 | 13 `authHeader` sites across the enumerated files | grep returns exactly 13, matching the plan's list line-for-line |
| 13 | 5 workplace test files reference `authHeader` | matches the plan's list exactly |
| 14 | `DriveTransferPipeline`, `ResolveAuthHeader`, `updateUploadProgress` → 0 hits under `lib/` and `workplace/` | all three confirmed 0 |
| 15 | `upload_controller.dart:98` and `:154` are the progress mapping sites | exact |
| 16 | `handleRefreshTokenFailedException` at `base_controller.dart:291` | exact |
| 17 | `test/features/interceptor/authorization_interceptor_test.dart` exists, 3841 lines, 88 tests, with dedicated groups for refresh/retry, refresh failures (Dio/non-Dio/PlatformException), queued-request concurrency, and the duplicate-token guard | the suite **is** strong enough to catch a refresh-path regression — this claim holds; what does not hold is the "green between steps" workflow (Finding 1) |

### FAILED

| # | Claim | Where | Reality |
|---|-------|-------|---------|
| F1 | "`workplace` is a path dependency of the app, so both are importable here" | phase-04:31-36 | Dependency direction is fine; **platform** is not. `dart:io` vs `dart:js_interop` — no shared platform. See Finding 2. |
| F2 | "Let `RefreshTokenFailedException` pass through `_asDioFailure` untouched" | phase-03:107-109 | `_asDioFailure` rewraps every non-`DioException` as `unknown`, and `workplace` cannot import the type. See Finding 3. |
| F3 | "the `.mocks.dart` sibling regenerates via build_runner" (singular) | phase-01:124-125 | 17 `.mocks.dart` files declare `MockAuthorizationInterceptors`. See Finding 1. |
| F4 | "`flutter test workplace/` green" as the Phase 2/3 completion signal | phase-02:93, phase-04:57 | All 5 modified test files are `@TestOn('chrome')` → skipped on the VM. See Finding 7. |
| F5 | "a `test/features/login/...` path does not exist" | phase-04:60-61 | `test/features/login/` exists with `data/`, `domain/`, `presentation/`. The intended claim (the *interceptor* suite is not under it) is true; the sentence as written is false. |
| F6 | "today they interpolate `request.fileName` only, at `:73` and `:139`" | phase-03:141-143 | `:73` yes. `:139` is inside `_resolveCharset`, which has no `request` in scope and interpolates only `$e`. Conclusion survives, citation does not. |
| F7 | Epoch-in-`clear()` is strictly stronger than the ADR's auth-type recheck | phase-01:113-116 | Both miss `setTokenAndAuthorityOidc` re-login (`reloadable_controller.dart:138`, `fcm_message_controller.dart:195`). See Finding 5. |

Minor line drift (not counted as failures): `token_oidc.dart:61` → actual `:62`; `token_oidc.dart:66-73` → actual `:66-74`; `authorization_interceptors.dart:613-617` → actual `:612-618`; `opfs_xhr_upload.dart:167-176` → else-branch is `:167-176` inclusive of braces, body at `:168-175`.

### Unverifiable from the repo (correctly flagged by the plan)

- JMAP upload endpoint's status code for an expired bearer (401 vs 403/400).
- Whether that response carries `Access-Control-Allow-Origin`.
- ADR-0105 final text (status: Proposed).

### Contract verification — consumers of each proposed interface change

| Interface change | Consumers found | Notes |
|---|---|---|
| `ensureFreshAuthorizationHeader` (new public) | 0 production; **17** `.mocks.dart` files break | Finding 1 |
| `_refreshTokenOnce` / `_RefreshOutcome` (new private) | 1 caller (`_refreshTokenThenRetry`, `:343`) + new entry point | contained |
| `ResolveAuthHeader` on 4 request classes | 13 production sites / 5 files + 5 workplace test files | plan's enumeration verified exact |
| `XhrUploadFileRequest.authHeader` → nullable | 2 sites: `opfs_drive_file_uploader_web.dart:63` (construct), `opfs_xhr_upload.dart:131` (`setRequestHeader`) | plan's `:131` guard is correct and sufficient |
| `_sessionEpoch` bump points | 1 (`clear()`, `base_controller.dart:660-661`) — insufficient | Finding 5 |
| `AuthorizationInterceptors` instances | 2 (`network_bindings.dart:92`, `network_isolate_binding.dart:55`) | Finding 6 |

---

## Unresolved questions

1. Which `AuthorizationInterceptors` tag does the drive resolver bind to — default or `BindingTag.isolateTag`? The plan never says, and it determines whether the memo covers the concurrent upload path at all.
2. What does `ensureFreshAuthorizationHeader` do on a **non-rejection** refresh failure (web network blip)? Unspecified, untested, and it changes whether a large upload is retried or abandoned.
3. Given Findings 2 and 7, what is the actual test topology for the cross-cutting scenario? Two platform-split tests, or a platform-neutral seam? This decides whether the ADR's headline concurrency guarantee is testable at all.
4. Is a lead-time/leeway term acceptable on the off-Dio expiry check, or is the team committed to the ADR's point-in-time semantics with a full re-upload as the recovery path?
