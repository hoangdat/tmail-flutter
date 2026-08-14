# Red-team plan review — ADR-0105 upload-phase token refresh

Reviewer role: FAILURE MODE ANALYST (hostile). Tier: Standard (Fact Checker + Contract Verifier).
Plan: `plans/260813-1741-adopt-adr-0105-upload-token-refresh/`
Repo: `/Users/datph/FlutterProject/tmail-agent` @ `feat/add_as_attachment`

---

## Finding 1: Phase 4's cross-cutting test cannot exist on any platform

- **Severity:** Critical
- **Location:** Phase 4, "Related Code Files" (`phase-04:30-36`) and "Implementation Steps" step 1 (`phase-04:43-48`)
- **Flaw:** The plan asserts the test "lives in the app package because it needs a real `AuthorizationInterceptors`; `workplace` is a path dependency of the app, so both are importable here." Import-graph reachability is not platform compatibility. `AuthorizationInterceptors` imports `dart:io`; `BrowserOpfsDriveFileUploader` transitively imports `dart:js_interop` and `package:web`. `dart:io` does not compile for the browser; `dart:js_interop`/`package:web` do not compile for the VM. There is no `flutter test` platform that can load both files in one library.
- **Failure scenario:** Phase 4 step 1 is attempted. Under `flutter test` (VM) the file fails to compile on `package:web`. Under `--platform chrome` it fails on `dart:io`. The implementer either (a) burns the phase discovering this, or (b) "fixes" it by swapping the real interceptor for a mock — at which point the test proves nothing about the refresh chain and the entire justification for the phase ("neither unit test proves it", `phase-04:23-25`) evaporates. Both Phase 4 success criteria 1 and 2 (`phase-04:104-107`) hang off this file.
- **Evidence:**
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:3` — `import 'dart:io';`
  - `workplace/lib/data/datasource/drive_transfer/opfs_drive_file_uploader_web.dart:7` — `import 'package:web/web.dart' as web;`
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:3` — `import 'dart:js_interop';`
  - `workplace/test/data/datasource/drive_transfer/opfs_drive_file_uploader_test.dart:1` — `@TestOn('chrome')`
  - `workplace/test/data/datasource/drive_transfer/opfs_xhr_upload_test.dart:1` — `@TestOn('chrome')`
- **Suggested fix:** Drop the "real interceptor + real uploader in one file" premise. Split into (a) a chrome test in `workplace/test/` driving `BrowserOpfsDriveFileUploader` against a *fake* `ResolveAuthHeader` that scripts refresh timing, and (b) a VM test in `test/features/interceptor/` driving the real `AuthorizationInterceptors` concurrency. State explicitly that no test in this plan proves the two halves compose, and make the manual browser check (step 4) blocking rather than deferred.

---

## Finding 2: Phase 4's suite commands are green with zero OPFS coverage executed

- **Severity:** Critical
- **Location:** Phase 4, "Implementation Steps" step 3 (`phase-04:53-61`) and Success Criteria (`phase-04:108`)
- **Flaw:** `flutter test workplace/` runs on the VM. Every OPFS drive-transfer test is `@TestOn('chrome')`, so it is **skipped, not failed**. Separately, CI only executes browser tests whose exact path is hard-coded in `CHROME_TEST_PATHS`. The plan creates a new test file (Phase 4) and materially rewrites four others (Phases 2-3) without a single instruction to update that list.
- **Failure scenario:** Implementer runs the four commands in `phase-04:54-58`, all green, ticks the criteria, opens the PR. CI runs `flutter test workplace/` (chrome tests skipped) plus the Chrome matrix leg over the fixed path list. The new cross-cutting test file is not in the list → never runs anywhere. Phase 3's retry-once logic — the actual product change — is validated by nothing that executes in CI. This is the plan's own "test-only-green" risk, unmitigated.
- **Evidence:**
  - `.github/workflows/analyze-test.yaml:16-25` — `CHROME_TEST_PATHS` enumerates 9 literal paths; comment at `:13-15` says "Add more lines here as needed."
  - `.github/workflows/analyze-test.yaml:74-82` — chrome leg loops only over `CHROME_TEST_PATHS`, `if: matrix.modules == 'default'`
  - `workplace/test/data/datasource/drive_transfer/opfs_drive_file_uploader_test.dart:1`, `opfs_xhr_upload_test.dart:1` — `@TestOn('chrome')`
  - No `dart_test.yaml` at repo root or in `workplace/` (verified absent) — so no default platform override exists
- **Suggested fix:** Add an explicit implementation step: register every new/changed browser test path in `.github/workflows/analyze-test.yaml` `CHROME_TEST_PATHS`. Replace `flutter test workplace/` in the criteria with the exact `--platform chrome` invocations, and require the run output to show a non-zero test count for the OPFS files.

---

## Finding 3: The session epoch does not cover the logout window; a refresh can resurrect a wiped session

- **Severity:** Critical
- **Location:** Phase 1, "Post-`clear()` guard" (`phase-01:103-116`) and Implementation Step 2 (`phase-01:131-138`)
- **Flaw:** Two holes. (a) The epoch is incremented inside `clear()`, but `clear()` runs *after* the cache wipe in the logout path — the destructive window opens ~one `Future.wait` earlier than the guard. (b) The plan checks the epoch exactly once, "on return" from the token fetch, then performs `_updateNewToken` → `_updateCurrentAccount` → keychain. `_updateCurrentAccount` itself contains **two sequential awaits with a durable write in each**, so the epoch can move (or the process can die) between them with no re-check.
- **Failure scenario A (resurrection):** User logs out. `_clearAllData` starts `Future.wait([deleteAuthorityOidcInteractor.execute(), cachingManager.clearAll(), ...])`. An in-flight drive-upload refresh resolves during that wait. Epoch is still 0 (it is only bumped at `:660-661`, after the wait). Guard passes. `persistOneTokenOidc` writes a live token and `setCurrentAccount` writes a selected account into the just-cleared Hive boxes. `closeHive()` follows. On restart the user is silently logged back in with the pre-logout identity.
- **Failure scenario B (partial write):** Epoch check passes; `persistOneTokenOidc` completes; the tab is closed / process killed before `setCurrentAccount`. The token box now holds a token whose `tokenIdHash` no account points at. The plan's success criterion ("performs no `_updateNewToken`, no `persistOneTokenOidc`, no `setCurrentAccount`", `phase-01:170-171`) is all-or-nothing and does not describe this state, so no test covers it.
- **Evidence:**
  - `lib/features/base/base_controller.dart:652-659` — `Future.wait([... cachingManager.clearAll() ...])`
  - `lib/features/base/base_controller.dart:660-661` — `authorizationInterceptors.clear(); authorizationIsolateInterceptors.clear();` (epoch bump would live here, *after* the wipe)
  - `lib/features/base/base_controller.dart:662` — `await cachingManager.closeHive();`
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:570-589` — `_updateCurrentAccount`: `await getCurrentAccount()` → `await persistOneTokenOidc()` → `await setCurrentAccount()`
  - `authorization_interceptors.dart:673-678` — `clear()` mutates in-memory fields only
- **Suggested fix:** Re-check the epoch immediately before **each** durable write inside `_updateCurrentAccount`, not once. Additionally bump the epoch at the *start* of the logout sequence (a `beginLogout()` / `invalidateSession()` on the interceptor called before `_clearAllData`'s `Future.wait`), not inside `clear()` at the end. Add a test that moves the epoch between `persistOneTokenOidc` and `setCurrentAccount`.

---

## Finding 4: Phase 1 mandates logout on *any* refresh rejection, undoing the keep-session-on-transient behaviour just shipped

- **Severity:** Critical
- **Location:** Phase 1, Requirements (`phase-01:28-29`), Implementation Step 4 last bullet (`phase-01:156-158`), Success Criteria (`phase-01:174-175`)
- **Flaw:** The requirement and the success criterion state flatly: "A rejected refresh clears the session and throws `RefreshTokenFailedException`." Step 4 then says it should be "routed through the same classifier the Dio path uses". These are not the same behaviour, and the plan does not resolve the conflict. The live Dio path only clears on a *confirmed* server rejection; network/transport failures and unclassified `ArgumentError`s explicitly **keep the session**. Worse, Phase 1's own Risk table (`phase-01:188`) says "Classification stays in `_refreshTokenThenRetry`" — i.e. the classifier is *not* shared — directly contradicting step 4.
- **Failure scenario:** Implementer follows the requirement literally (it is the requirement, and it is what the success-criteria checkbox tests). User on flaky wifi starts a 400 MB drive attachment. Token expires mid-transfer; the 401 fires `resolveAuthHeader(forceRefresh: true)`; the token endpoint is unreachable → any non-2xx/transport error. `ensureFreshAuthorizationHeader` calls `clear()` and throws `RefreshTokenFailedException`. Phase 3 propagates it unchanged (`phase-03:30-31`); the wiring PR maps it to `handleRefreshTokenFailedException()` → `clearDataAndGoToLoginPage()`. The user is force-logged-out and their local cache wiped because of one dropped packet — exactly the regression `bfde3527a` / `fa12f7198` fixed for the Dio path.
- **Secondary flaw:** `_handleRefreshErrorOnWeb` / `_handleRefreshErrorOnMobile` both take an `ErrorInterceptorHandler` and a `DioException originalError` and terminate in `handler.reject(...)`. They are structurally unreachable from an off-Dio caller. "Route through the same classifier" therefore requires extracting a handler-free decision function, which no implementation step describes.
- **Evidence:**
  - `authorization_interceptors.dart:209-253` — `_handleRefreshErrorOnWeb`: `clear()` + reject **only** when `_errorClassifier.isServerRejection(error)`; `:247-252` logs "keeping session" otherwise
  - `authorization_interceptors.dart:287-310` — mobile handler: same shape, `_isRefreshRejectedByTokenEndpoint` gate at `:293`
  - `authorization_interceptors.dart:214`, `:227-231`, `:302-306` — both handlers depend on `ErrorInterceptorHandler` + `originalError`
  - `lib/features/base/base_controller.dart:291-301` — `handleRefreshTokenFailedException` → `_performSaveAndReconnection` / `_performReconnection` → `clearDataAndGoToLoginPage()`
- **Suggested fix:** Rewrite the requirement to: "A refresh rejected *by the token endpoint* clears the session and throws `RefreshTokenFailedException`; a transport/unclassified failure keeps the session and throws the original error." Add an explicit step extracting the classification decision (`bool shouldLogout(Object error)`) out of the two handler-bound methods so both entry points share one predicate, and add a success criterion: "a `connectionError` during an off-Dio refresh does **not** call `clear()`."

---

## Finding 5: Phase 2 and Phase 3 specify contradictory types for `XhrUploadFileRequest.authHeader`; Phase 2 alone does not compile

- **Severity:** Critical
- **Location:** Phase 2, Requirements (`phase-02:24-26`) and Implementation Step 5 (`phase-02:87-88`) vs. Phase 3, Implementation Step 1 (`phase-03:95-96`) and Architecture (`phase-03:52-54`)
- **Flaw:** Phase 2 says `ResolveAuthHeader` replaces `String authHeader` on all four request classes **including `XhrUploadFileRequest`**. Phase 3 says `XhrUploadFileRequest.authHeader` "becomes nullable at the transport" and its pseudo-code passes an already-resolved `header` string into `transport.uploadFile(... authHeader: header ...)`. Those are two different types for the same field. Phase 2's completion signal is "treat a clean analyze as the completion signal" — but under Phase 2's own spec, `xhr.setRequestHeader('Authorization', request.authHeader)` would receive a `Future<String?> Function({bool})` where a `String` is required, and analyze cannot be clean without doing Phase 3's work.
- **Failure scenario:** Phase 2 is executed as written and landed on the strength of "analyze clean". It cannot be. The implementer resolves the ambiguity ad hoc — most likely by invoking the resolver *inside* `OpfsXhrUpload`, which silently contradicts Phase 3's architectural premise ("the transport stays a dumb one-shot send", `phase-03:42`) and puts the refresh call inside a synchronous method that returns an `XhrUploadHandle` before `send`. If instead they leave `XhrUploadFileRequest` as `String`, Phase 2's success criterion "No `String authHeader` field remains in `workplace/lib/`" (`phase-02:92`) is false and the phase is unlandable by its own gate.
- **Evidence:**
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:26` — `final String authHeader;`
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:131` — `xhr.setRequestHeader('Authorization', request.authHeader);` inside `_applyHeaders`, a **synchronous** method
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:59` — `XhrUploadHandle uploadFile(...)` is synchronous by contract (returns a handle, not a Future)
  - `workplace/lib/data/datasource/drive_transfer/opfs_drive_file_uploader_web.dart:63` — `authHeader: request.authHeader` is the sole bridge site
- **Suggested fix:** Fix the boundary in Phase 2: `ResolveAuthHeader` on `DriveTransferRequest` / `DriveUploadRequest` / `OpfsUploadRequest` only; `XhrUploadFileRequest.authHeader` becomes `String?` in Phase 2 (not Phase 3), with the uploader passing `await request.resolveAuthHeader(forceRefresh: false)` from day one. Then Phase 2 genuinely compiles standalone and Phase 3 adds only the retry flag.

---

## Finding 6: Two live `AuthorizationInterceptors` instances; the memo, the epoch and "exactly one refresh" are all per-instance

- **Severity:** High
- **Location:** Phase 1, Architecture (`phase-01:39-52`) and Success Criteria (`phase-01:165-168`); Phase 4 step 2 (`phase-04:49-52`)
- **Flaw:** The plan reasons as if there is one `AuthorizationInterceptors`. There are two singletons in GetX — the default one on the main Dio and a second under `BindingTag.isolateTag` on the isolate Dio — each with its own `_token`, and (post-plan) its own `_refreshTokenOnce` memo and `_sessionEpoch`. The plan never states which instance backs the drive resolver, and single-flight does not span them.
- **Failure scenario:** A background/isolate JMAP call 401s at the same moment a drive upload 401s. The isolate interceptor runs `_refreshTokenThenRetry` on its own memo; the main interceptor runs `ensureFreshAuthorizationHeader` on its own memo. **Two** concurrent `refreshingTokensOIDC` calls with the same refresh token. With refresh-token rotation the loser's grant is consumed/invalidated; the second response either 400s (→ `clear()` → forced logout) or the two instances end up holding divergent tokens, with only `reloadable_controller.dart:138-139` ever resynchronising them (and only on a full reload). Phase 1's headline criterion "exactly one `refreshingTokensOIDC` call, zero logouts" passes in a single-instance unit test and is false in the app.
- **Evidence:**
  - `lib/main/bindings/network/network_bindings.dart:92-99` — `Get.put(AuthorizationInterceptors(dio, ...))` (untagged)
  - `lib/main/bindings/network/network_isolate_binding.dart:55-62` — second instance, `Get.put(authorizationInterceptors, tag: BindingTag.isolateTag)`
  - `lib/features/base/base_controller.dart:79-80` — both are resolved and held side by side
  - `lib/features/base/reloadable/reloadable_controller.dart:138-139` — the only place both are given the same token
  - `authorization_interceptors.dart:367` — `_updateNewToken` mutates only `this`, so a refresh on one instance leaves the other stale
- **Suggested fix:** State the instance explicitly in Phase 1 and Phase 4 ("the resolver binds the untagged instance"). Either add an explicit non-goal ("cross-instance single-flight is out of scope; the isolate interceptor can still double-refresh — pre-existing") or hoist the memo + epoch to a shared collaborator injected into both. Do not let the criterion at `phase-01:165-168` imply an app-wide guarantee it cannot make.

---

## Finding 7: The memo dedupes overlapping refreshes only; N staggered drive uploads produce N forced refreshes

- **Severity:** High
- **Location:** Phase 3, Architecture (`phase-03:52-58`) and Requirements (`phase-03:26-27`); Phase 4 step 2 (`phase-04:49-52`)
- **Flaw:** `attempt(forceRefresh: true)` unconditionally forces a refresh on every 401, with no "has `_token` already changed since the header I sent?" check. The memo only collapses refreshes that are *in flight simultaneously*. Concurrent drive uploads do not 401 simultaneously — each 401 arrives when its own multi-hundred-MB send finishes, i.e. seconds to minutes apart. The dedupe therefore does not apply to the very workload it was designed for.
- **Failure scenario:** User attaches five drive files. All five resolve headers with token T1 (not yet expired, so no refresh) and start sending. T1 expires mid-transfer. Upload #1 finishes → 401 → `forceRefresh: true` → refresh → T2. Upload #2 finishes 8 s later → 401 (it sent T1) → `forceRefresh: true` → **another** refresh, even though `_token` is already T2 and a plain re-send would have succeeded. Five sequential refreshes, four of them gratuitous. Against an IdP with refresh-token reuse detection or token-endpoint rate limiting, that is an account-level session revocation. Note the existing Dio path avoids this precisely via `validateToRetryTheRequestWithNewToken`, which retries with the *already-updated* token and does **not** refresh — Phase 3 has no analogue.
- **Evidence:**
  - `authorization_interceptors.dart:535-564` — `validateToRetryTheRequestWithNewToken` — the existing "token was updated by someone else, just retry" branch, invoked at `:124-133` *before* the refresh branch
  - `authorization_interceptors.dart:134-139` — refresh is the fallback only when the retry gate fails
  - `phase-03:52-58` — the plan's flow has no equivalent gate; attempt 2 always forces
  - `phase-04:49-52` — the concurrency test scripts *simultaneous* 401s, which is the case the memo already handles; the staggered case is untested
- **Suggested fix:** Mirror the Dio path. Have the uploader capture the header it sent, and on 401 first call `resolveAuthHeader(forceRefresh: false)`; force a refresh only if the returned header is byte-identical to the one that 401'd. Add a test: two uploads 401 five seconds apart → exactly one `refreshingTokensOIDC`.

---

## Finding 8: No timeout on the refresh; an off-Dio memo holder stalls the entire Dio error queue

- **Severity:** High
- **Location:** Phase 1, Architecture (`phase-01:39-52`) and Implementation Step 3 (`phase-01:139-147`); plan.md "Superseded approach" (`plan.md:85-90`)
- **Flaw:** After Phase 1, `_refreshTokenThenRetry` **joins** a memo that may have been started by an off-Dio caller. There is no timeout anywhere in the chain — not on `ensureFreshAuthorizationHeader`, not on `_refreshTokenOnce`, not in `refreshingTokensOIDC`, not in the interceptor. `_refreshTokenThenRetry` executes inside `QueuedInterceptor`'s serialised `_errorQueue`, so awaiting the memo blocks the queue head.
- **Failure scenario:** A drive upload 401s and calls `ensureFreshAuthorizationHeader(forceRefresh: true)`. The memo is created and awaits `_appAuthWeb.token(...)` (or the native `flutter_appauth` channel on mobile). The IdP accepts the TCP connection and never responds; there is no timeout, so the future never settles. Two seconds later any other request in the app 401s → `onError` → `_refreshTokenThenRetry` → joins the never-settling memo → the `_errorQueue` head never calls `_processNextInQueue`. Every subsequent Dio *error* in the app now queues behind it, unbounded, for the lifetime of the tab. This is structurally the same unbounded-stall failure the plan used to reject the adapter approach — it has been reintroduced through the memo instead of through the request path, and the plan's Risk table (`phase-01:182-189`) does not list it.
- **Evidence:**
  - `dio-5.2.0/lib/src/interceptor.dart:364-367` — `QueuedInterceptor` with a single `_errorQueue`
  - `dio-5.2.0/lib/src/interceptor.dart:385-388, 390-410` — `_handleQueue` runs one task at a time; the next task only starts via `_processNextInQueue`
  - `authorization_interceptors.dart:28` — `class AuthorizationInterceptors extends QueuedInterceptorsWrapper`
  - `authorization_interceptors.dart:610-619` — `_invokeRefreshTokenFromServer`: no timeout
  - `lib/features/login/data/network/authentication_client/authentication_client_web.dart:76-104` — `refreshingTokensOIDC`: no timeout
  - grep for `timeout` across the auth client + interceptor: 1 hit, and it is a doc comment (`authorization_interceptors.dart:201`)
  - `plan.md:85-90` — the plan's own statement of why an unbounded await inside the error queue is unacceptable
- **Suggested fix:** Put a hard timeout on `_refreshTokenOnce()` (e.g. `.timeout(Duration(seconds: 30))`), classify a timeout as transient (keep session), and clear the memo on timeout so the next caller can retry. Add this to Phase 1's Risk table and a success criterion: "a refresh that never settles does not block a subsequent Dio 401 for more than the timeout."

---

## Finding 9: `null` header conflates `AuthenticationType.none` with "logged out", so a dead session uploads unauthenticated

- **Severity:** High
- **Location:** Phase 2, Architecture (`phase-02:47-48`) and Phase 3, Requirements (`phase-03:28-29`) / Step 1 (`phase-03:95-96`)
- **Flaw:** The plan declares "Null means *send no Authorization header*, not an error — this is the `AuthenticationType.none` case and is not an error." But `clear()` sets `_authenticationType = AuthenticationType.none`. After any logout or any refresh rejection, `ensureFreshAuthorizationHeader` therefore returns `null` under the plan's own step-4 rules — indistinguishable from a genuinely unauthenticated deployment.
- **Failure scenario:** A drive upload is in progress. A concurrent Dio 401 triggers a refresh rejection → `clear()` → `_authenticationType = none`. The upload's `_attempt` calls `resolveAuthHeader(forceRefresh: false)`. Per the contract it returns `null` (not an error), so Phase 3 skips `setRequestHeader('Authorization', ...)` and **POSTs the whole staged file to the server-supplied `uploadUri` with no credentials**. Server 401s. Attempt 2 forces a refresh, which under a cleared session either throws or returns `null` again. Net result: a full-file upload burned on a request that could never succeed, and the failure surfaces as a generic `badResponse` rather than "your session ended". The plan's success criterion "A null resolved header sends no `Authorization` header" (`phase-03:122`) *asserts this bug as correct behaviour*.
- **Evidence:**
  - `authorization_interceptors.dart:673-678` — `clear()` sets `_authenticationType = AuthenticationType.none`
  - `authorization_interceptors.dart:106-107` — `onRequest` treats `none` as "attach nothing", the same conflation
  - `phase-01:149-150` — "`basic` → return the existing basic header; `none` → return null"
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:131` — the header write to be skipped
  - `phase-01:198-200` — the plan already notes the bearer goes to an unchecked server-supplied `uploadUrl`
- **Suggested fix:** Distinguish "this deployment has no auth" from "this session is dead". Either have `ensureFreshAuthorizationHeader` throw when it is called on a session that was cleared (track a `_wasCleared` flag alongside the epoch), or make `AuthenticationType.none` a startup-only state the drive path refuses to enter. At minimum, add a Phase 3 criterion: "resolving after `clear()` fails the upload rather than sending it unauthenticated."

---

## Finding 10: The deferred monotonic-progress handoff is under-specified and the plan ships an untested double-report

- **Severity:** Medium
- **Location:** Phase 3, Risk table row 4 (`phase-03:135`); Phase 4, "Deferred to the drive→composer wiring PR" item 2 (`phase-04:88-99`)
- **Flaw:** Two gaps. (a) The handoff names only `max(current, mapped)`, but the OPFS transport normalises an unknown total to `-1`, and the mapping at both `upload_controller` sites divides by `success.total` — `-1` yields a **negative** percentage. A `max(current, mapped)` clamp then freezes the bar at its last good value forever rather than exposing the sentinel, so the bug becomes invisible instead of fixed. (b) Phase 3 has no criterion for progress behaviour across a retry at all, so nothing in the plan pins that a retried upload re-reports the same byte range twice.
- **Failure scenario:** Wiring PR applies the clamp exactly as handed off. A drive upload whose response lacks `Content-Length` reports `total = -1`; every mapped value is negative; the clamp holds the bar at 0 for the whole transfer and the user sees a hung upload. Separately, on a 401 retry the consumer receives `loaded` running 0→N twice for one file — with the clamp the bar freezes at its attempt-1 peak until attempt 2 passes it, which for a large file is minutes of apparent stall.
- **Evidence:**
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:83-92` — `event.lengthComputable ? event.total : -1`
  - `lib/features/upload/presentation/controller/upload_controller.dart:98` — `uploadingProgress: (success.progress * 100 / success.total).floor()`
  - `lib/features/upload/presentation/controller/upload_controller.dart:154` — identical mapping on the inline-image path
  - `phase-04:80-81` — verified: `DriveTransferPipeline`, `ResolveAuthHeader`, `updateUploadProgress` all return 0 hits under `lib/` and `workplace/` (independently re-confirmed)
- **Suggested fix:** Extend the handoff to `progress = total > 0 ? max(current, mapped) : current`, and add a Phase 3 criterion asserting the retried attempt re-invokes `onUploadProgress` from 0 — so the wiring PR inherits a *documented, tested* contract rather than an inferred one.

---

## Finding 11: The design's trigger condition is validated only after all four phases have landed

- **Severity:** Medium
- **Location:** Phase 4, Implementation Step 4 (`phase-04:62-76`) and Unresolved question 1 (`phase-04:122-124`)
- **Flaw:** The entire plan keys on the upload endpoint answering **401** and that 401 being CORS-exposed. The plan correctly identifies this as unanswerable from the repo — and then places the check in the last phase, marks it "Blocked until the drive→composer wiring exists", and defers it. Since the wiring is out of scope for this plan, the check cannot happen within it. Every phase merges before the premise is tested.
- **Failure scenario:** All four phases land (~2.5-3.5 days). The wiring PR runs the manual check and finds the endpoint answers 403, or that the 401 lacks `Access-Control-Allow-Origin` (arriving as `status == 0` → `connectionError`, retry never fires). Phase 3's retry branch is then dead code, Phase 2's repo-wide type churn bought nothing, and the plan's own instruction is "stop and re-open the ADR" — at which point the ADR reopens against three merged commits. Note that the design also has zero net user-visible effect on this branch (no resolver call sites exist), so nothing forces the discovery earlier.
- **Evidence:**
  - `phase-04:73-76` — "If either answer is unfavourable, stop and re-open the ADR… Blocked until the drive→composer wiring exists"
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:98-103` — `onerror` → `DioExceptionType.connectionError`, which the Phase 3 retry does not match
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:167-176` — the `badResponse` + `statusCode` shape the retry does match
  - `phase-04:80-81` / re-verified: 0 call sites exist, so nothing on this branch exercises the design
- **Suggested fix:** Move the empirical check to a Phase 0 spike: point `curl`/a scratch fetch at the JMAP upload endpoint with an expired bearer against the dev backend (`backend-docker`, or a real OIDC deployment) and record status + CORS headers *before* Phase 1 begins. It costs under an hour and gates ~3 days of work. Alternatively broaden the retry trigger to `badResponse(401|403) || connectionError-with-unused-retry` so the design survives an unfavourable answer.

---

## Verification Results

**Tier:** Standard — FACT CHECKER + CONTRACT VERIFIER
**Claims checked:** 31 · **Verified:** 27 · **Failed:** 3 · **Unverified:** 1

### Line-number citations (Fact Checker)

| Plan claim | Result |
|---|---|
| `authorization_interceptors.dart:357` duplicate-token guard reads old `_token` | VERIFIED — `if (newTokenOidc.token == _token?.token)` at `:357` |
| `:367` `_updateNewToken` after the guard | VERIFIED |
| `:510-533` `validateToRefreshToken`; `:511` the 401 gate | VERIFIED (`:512` is the literal `== 401`, header at `:510`) |
| `:570-589` `_updateCurrentAccount` two durable writes | VERIFIED (`persistOneTokenOidc` `:576`, `setCurrentAccount` `:586`) |
| `:613-617` `_configOIDC!` / `_token!` deref in `_invokeRefreshTokenFromServer` | VERIFIED |
| `:673-678` `clear()` nulls in-memory fields only | VERIFIED |
| `:456-458` `_performRetry` awaits the whole retried request | VERIFIED (`_performRetry` `:451`, await `:457`, resolve `:458`) |
| `model/lib/oidc/token_oidc.dart:61` `isTokenValid()` has no expiry term | VERIFIED |
| `token_oidc.dart:66-73` `isExpired` returns false when `expiredTime == null` | VERIFIED |
| `base_controller.dart:291` `handleRefreshTokenFailedException` | VERIFIED |
| `upload_controller.dart:98` and `:154` progress mapping | VERIFIED — identical expression at both |
| `dio-5.2.0/lib/src/interceptor.dart:364-410` `QueuedInterceptor` `_errorQueue` | VERIFIED (`class` at `:364`, `_errorQueue` `:367`, `_handleQueue` `:390-410`) |
| `network_bindings.dart:60-64` default `Content-Type` in `BaseOptions` | VERIFIED |
| `core/lib/data/constants/constant.dart:3` `contentTypeHeaderDefault` | VERIFIED |
| `opfs_xhr_upload.dart:50` "auth header is read once" doc comment | VERIFIED (`:49-50`) |
| `opfs_xhr_upload.dart:167-176` non-2xx → `badResponse` + `statusCode` | VERIFIED |
| `opfs_xhr_upload.dart:98-103` `onerror` → `connectionError` | VERIFIED |
| `opfs_xhr_upload.dart:131` `setRequestHeader('Authorization', ...)` | VERIFIED |
| `opfs_drive_file_uploader_web.dart:43` `upload()`; `:58` charset future; `:87-90` `finally` | VERIFIED |
| `buffered_web_drive_file_stager.dart:84` doc comment about `request.authHeader` | VERIFIED |
| `test/features/interceptor/` exists, `test/features/login/...` does not | VERIFIED |
| `DriveTransferPipeline` / `ResolveAuthHeader` / `updateUploadProgress` = 0 hits | VERIFIED — 0 hits each under `lib/` and `workplace/` |
| `CancelToken.whenCancel` has no removal | VERIFIED — `dio-5.2.0/lib/src/cancel_token.dart:15,31`; plain `Completer.future`, multiple `.then` listeners are legal and an already-completed token fires a late listener asynchronously (so the plan's per-attempt-listener scheme works, at the cost of one permanently-retained listener per attempt) |

### FAILED claims

1. **`phase-03:141-142`** — "today they interpolate `request.fileName` only, at `:73` and `:139`". `opfs_drive_file_uploader_web.dart:139` is `logWarning('BrowserOpfsDriveFileUploader: charset sniff failed: $e')` — it interpolates the **error**, not `request.fileName`. Only `:73` matches the claim. Low impact (the security conclusion still holds) but the citation is wrong.
2. **`phase-02:20` / `phase-02:52`** — "13 production sites across **5 files**". The enumerated list names **6** files, and grep confirms 13 `authHeader` lines across 6 files in `workplace/lib/` (12 code + 1 doc comment at `buffered_web_drive_file_stager.dart:84`). The 13 individual line citations are all exact; the file count is off by one.
3. **`phase-04:31-36`** — "Lives in the app package because it needs a real `AuthorizationInterceptors`; `workplace` is a path dependency of the app, so both are importable here." **False.** Import reachability ≠ platform compatibility; see Finding 1. This is a load-bearing claim for the whole phase.

### UNVERIFIED

- ADR-0105 content (PR #4755, `linagora/tmail-flutter`). `gh pr diff 4755` was not run in this review; all ADR-attributed statements in the plan are taken at face value. If the plan's paraphrase of the ADR is wrong, Findings 5, 7 and 9 may attach to the plan rather than the ADR.

### Contract Verification — `AuthorizationInterceptors` public surface

Adding `ensureFreshAuthorizationHeader` to `AuthorizationInterceptors` touches **32** generated mock files, not the 1 the plan names (`phase-01:122-126` mentions only `test/features/interceptor/authorization_interceptor_test.mocks.dart`).

`class MockAuthorizationInterceptors extends _i1.Mock implements ...AuthorizationInterceptors` appears in:
`test/features/base/base_controller_test.mocks.dart`, `.../reloadable_controller_test.mocks.dart`, `.../urgent_exception_handler_service_test.mocks.dart`, `test/features/composer/presentation/composer_controller_test.mocks.dart`, `.../manager/composer_manager_test.mocks.dart`, `test/features/email/presentation/controller/single_email_controller_test.mocks.dart`, `.../extensions/update_attendance_status_extension_test.mocks.dart`, `test/features/home/presentation/home_controller_test.mocks.dart`, `test/features/identity_creator/presentation/identity_creator_controller_test.mocks.dart`, `test/features/login/presentation/login_controller_test.mocks.dart`, `test/features/mailbox_dashboard/presentation/controller/{advanced_filter,mailbox_dashboard,search,spam_report}_controller_test.mocks.dart`, `.../extensions/{initialize_app_language,quick_search_emails_extension,restore_mailbox_email_list_after_search_extension,update_current_emails_flags_extension}_test.mocks.dart`, `.../view/mailbox_dashboard_view_widget_test.mocks.dart`, `test/features/manage_account/presentation/notification/notification_controller_test.mocks.dart`, `.../profiles/identities/identities_controller_test.mocks.dart`, `test/features/rule_filter_creator/presentation/rule_filter_creator_controller_test.mocks.dart`, `test/features/search/verify_before_time_in_search_email_filter_test.mocks.dart`, `test/features/thread/presentation/controller/thread_controller_test.mocks.dart`, `test/features/thread_detail/presentation/extension/*.mocks.dart` (7 files).

These compile without regeneration (mockito `noSuchMethod` forwarding), so nothing breaks at analyze time — but any of them that reaches the new method gets a `noSuchMethod` null against a non-nullable `Future<String?>` return, failing at runtime with an opaque message. Phase 1 should state "run `build_runner` across the workspace; 32 `.mocks.dart` files regenerate" rather than naming one sibling.

### Contract Verification — `authHeader` consumers (Phase 2)

- `workplace/lib/`: **13 lines / 6 files** — `drive_transfer_strategy.dart:28,67,76,91,99`; `opfs_drive_file_uploader.dart:23,32`; `opfs_drive_transfer_strategy.dart:47`; `opfs_drive_file_uploader_web.dart:63`; `opfs_xhr_upload.dart:26,33,131`; `buffered_web_drive_file_stager.dart:84` (comment). Every plan line citation matches exactly.
- `workplace/test/`: **11 lines / 5 files** — `drive_transfer_strategy_test.dart` (3), `buffered_web_drive_file_stager_test.dart` (3), `opfs_drive_file_stager_test.dart` (2), `opfs_drive_file_uploader_test.dart` (2), `opfs_xhr_upload_test.dart` (1). Matches the plan's list of 5 exactly.
- Outside `workplace/`: **0** references to `DriveTransferRequest` / `DriveUploadRequest` / `OpfsUploadRequest` / `XhrUploadFileRequest`. Confirmed — the type change is contained.
- No `const DriveTransferRequest(...)` / `const XhrUploadFileRequest(...)` *invocations* exist (only the const constructor declarations at `drive_transfer_strategy.dart:73,96`, `opfs_drive_file_uploader.dart:28`, `opfs_xhr_upload.dart:30`), so a function-typed field introduces no const-evaluation breakage.

---

## Unresolved questions

1. Which `AuthorizationInterceptors` instance backs the drive resolver — untagged or `BindingTag.isolateTag`? (Finding 6)
2. Is a transient (network) refresh failure during a drive upload meant to log the user out? Phase 1's requirement says yes; the live Dio behaviour says no. (Finding 4)
3. What is `XhrUploadFileRequest.authHeader`'s type after Phase 2 — `ResolveAuthHeader` or `String?`? (Finding 5)
4. Who owns adding the new/changed browser tests to `CHROME_TEST_PATHS`? (Finding 2)
5. Can the endpoint's 401 + CORS behaviour be answered against `backend-docker` before Phase 1, rather than after Phase 4? (Finding 11)
6. ADR-0105's actual text was not read in this review; if the plan misparaphrases it, Findings 5/7/9 may need re-attribution.
