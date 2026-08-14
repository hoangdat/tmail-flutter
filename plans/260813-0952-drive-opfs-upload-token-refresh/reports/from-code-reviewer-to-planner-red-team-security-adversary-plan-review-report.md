# Red-team plan review — security adversary — drive OPFS upload token refresh

Reviewer: code-reviewer (Standard tier: fact checker + contract verifier)
Date: 2026-08-13
Plan: `plans/260813-0952-drive-opfs-upload-token-refresh/`
Verdict: **NOT READY TO IMPLEMENT.** 4 Critical, 4 High, 2 Medium.

---

## Finding 1: Phase 2's entire premise is factually wrong — `isTokenValid()` does not check expiry

- **Severity:** Critical
- **Location:** Phase 2, "Overview" (first paragraph); referenced again in Phase 2 "Architecture / A"
- **Flaw:** The plan states that when the token is already expired, `AuthorizationInterceptors.onRequest` attaches **no** `Authorization` header ("the header is only set when `isTokenValid()`"), so the upload is "guaranteed to 401". `isTokenValid()` has nothing to do with expiry — it is `token.isNotEmpty && tokenId.uuid.isNotEmpty`. An expired token IS attached, every time.
- **Failure scenario:** An implementer takes the stated mechanism at face value and writes the Phase 2 guard/tests around "no header on expiry". The real behaviour is "stale bearer sent, server 401s". Two concrete consequences the plan never reasons about: (a) an expired-but-non-empty token is transmitted on the wire to the upload endpoint on every attempt, which is the opposite of the "no header" model the plan reasons from; (b) the 401 is first evaluated by `validateToRetryTheRequestWithNewToken`, whose `isTokenStillValid = !_isTokenExpired(...)` gate is what actually routes an expired token to refresh — a branch the plan never mentions and whose tests would be written wrong. Anything asserting "no Authorization header when expired" will fail against real code.
- **Evidence:**
  - `model/lib/oidc/token_oidc.dart:61` — `bool isTokenValid() => token.isNotEmpty && tokenId.uuid.isNotEmpty;`
  - `model/lib/oidc/token_oidc.dart:66-73` — `isExpired` is a separate getter, never consulted by `isTokenValid()`
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:101-105` — the oidc branch attaches the header on `isTokenValid()`, i.e. always when a token exists
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:542,546-550` — `isTokenStillValid` in `validateToRetryTheRequestWithNewToken` is the real expiry gate
- **Suggested fix:** Rewrite the Phase 2 overview: the cost being avoided is "a stale bearer is sent and the server 401s", not "no header". Re-derive the guard and the Phase 3 assertions from the actual 401-classification order (`validateToRetryTheRequestWithNewToken` → `validateToRefreshToken`).

---

## Finding 2: `_refreshCore()` extraction inverts the duplicate-token guard into an always-true forced-logout

- **Severity:** Critical
- **Location:** Phase 2, "Architecture / A" and "Implementation Steps" 1-3
- **Flaw:** The plan says to extract "the body between 'Perform get New Token' and `_updateNewToken` + `_updateCurrentAccount` + iOS keychain save (`authorization_interceptors.dart:348-376`)" into `_refreshCore()`. That range *contains* `_updateNewToken(newTokenOidc)`, which assigns `_token = newToken`. But the duplicate-token guard sits **before** it and compares `newTokenOidc.token == _token?.token`. Once `_refreshCore()` owns the assignment and the 401 path only awaits a shared completer, `_token` has already been replaced by the time the guard runs.
- **Failure scenario:** OIDC user's token expires. Preflight `ensureTokenFresh()` wins the single-flight race and runs `_refreshCore()`, which sets `_token = <new token>`. The queued 401 path joins the shared future, resumes, and evaluates the guard — `newTokenOidc.token == _token?.token` is now trivially true because both are the new token. The interceptor logs `forced_logout_401_refreshed_token_duplicated` and calls `super.onError(err, handler)`, which propagates the 401 to `RemoteExceptionThrower` → `BadCredentialsException` → **the user is logged out on every successful refresh**. Step 1's "pure extraction verified by the existing suite" does not catch this, because the bug only appears once step 2 adds the shared completer.
- **Evidence:**
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:357-366` — the `newTokenOidc.token == _token?.token` guard and its forced-logout branch
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:367` — `_updateNewToken(newTokenOidc)` sits inside the cited 348-376 range
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:79-82` — `_updateNewToken` mutates shared `_token`
  - Range check: line 375 (`requestOptions.extra[_refreshAttemptedKey] = true`) and 376 (`return await _performRetry(...)`) are retry-only code that cannot live in a shared refresh at all — the cited extraction boundary is wrong on both ends.
- **Suggested fix:** `_refreshCore()` must return the new token **without** mutating `_token`, or the guard must be restated as "the refresh returned a token identical to the one that produced this 401", captured before awaiting. State the exact extraction boundary as line-accurate ranges and add an explicit test: successful shared refresh → retry, never logout.

---

## Finding 3: public `ensureTokenFresh()` can resurrect a session that `clear()` already killed

- **Severity:** Critical
- **Location:** Phase 2, "Architecture / A", "Security Considerations" ("`ensureTokenFresh()` exposes no token material")
- **Flaw:** Today refresh is only ever initiated from inside `QueuedInterceptor`'s serialized `_errorQueue`. Phase 2 adds a second, *unqueued*, publicly callable entry point that runs concurrently with everything else — including the forced-logout path. `clear()` nulls `_token`/`_configOIDC`/`_authenticationType`, but an already in-flight `_refreshCore()` holds its own captured references and, on completion, calls `_updateNewToken` + `_updateCurrentAccount`, which **persists the new token to Hive and re-selects the account**.
- **Failure scenario:** User's refresh token is revoked server-side (admin revocation / password change). Drive transfer starts; `ensureTokenFresh()` fires a refresh. Meanwhile another request 401s, `_handleRefreshErrorOnWeb` classifies the rejection and calls `clear()` — the app believes the session is dead and routes to login. The in-flight preflight refresh (which the IdP happened to honour, e.g. a race against revocation propagation, or a refresh started before revocation) then resolves and writes a live `TokenOIDC` back into `_token`, into `TokenOidcCacheManager.persistOneTokenOidc`, and into `AccountCacheManager.setCurrentAccount`. The "logged out" session is silently reinstated in cache and survives restart. The plan's Security Considerations section asserts safety here without analysing the write side-effects at all.
- **Evidence:**
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:673-678` — `clear()` only nulls in-memory fields; it cannot cancel an in-flight refresh
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:570-589` — `_updateCurrentAccount` calls `persistOneTokenOidc` then `setCurrentAccount` (durable writes)
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:226`, `:301`, `:394` — the three `clear()` call sites that race the new entry point
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:364` (QueuedInterceptor serialization today) vs. `~/.pub-cache/hosted/pub.dev/dio-5.2.0/lib/src/interceptor.dart:364-411` — the existing single-entry guarantee the plan removes
- **Suggested fix:** Add a session epoch/generation counter incremented by `clear()`; `_refreshCore()` must discard its result (no `_updateNewToken`, no cache writes) if the epoch moved while it was in flight. Add this as an explicit Phase 2 success criterion and test.

---

## Finding 4: Phase 1 has no path to the app Dio — the only Dio `workplace` can reach has no interceptors

- **Severity:** Critical
- **Location:** Phase 1, "Implementation Steps" 6 ("takes a `DioClient` (workplace already depends on `core`)"), "Related Code Files / Modify"
- **Flaw:** Phase 1 says `BrowserOpfsDriveFileUploader` "takes a `DioClient`" but never says *which* one, never lists the two files that construct it, and explicitly defers "factory injection" to a part-3 plan that does not exist. `OpfsDriveTransferStrategy` defaults its uploader to `BrowserOpfsDriveFileUploader()` (no args), and the factory constructs `OpfsDriveTransferStrategy()` (no args). Neither file is in the Modify list. The only `Dio` the `workplace` package can reach without injection is `WorkplaceDio.instance` — a bare `Dio` with **no interceptors at all** and 10s connect/send/receive timeouts. Every other network call in `workplace` uses exactly that.
- **Failure scenario:** Implementer follows Phase 1 literally, hits "where does the DioClient come from?", and reaches for the established in-package pattern: `WorkplaceDio.instance`. Result: the OPFS upload now goes through Dio with **zero** `AuthorizationInterceptors` — no bearer header, no refresh, no retry. Every drive attachment upload 401s unauthenticated, and the plan's entire stated goal is silently inverted (worse than the status quo, which at least passed an explicit `authHeader`). Even if it somehow works in a test, `WorkplaceDio`'s 10s `sendTimeout` kills any multi-hundred-MB upload — the exact workload this path exists for, and the exact property Phase 1's non-functional requirement says must be preserved ("No upload timeout is imposed").
- **Evidence:**
  - `workplace/lib/data/workplace_dio.dart:5-11` — `static Dio _instance = Dio(BaseOptions(sendTimeout: 10s, receiveTimeout: 10s, connectTimeout: 10s))`, no interceptors
  - `workplace/lib/data/datasource/drive_transfer/opfs_drive_transfer_strategy.dart:20` — `_uploader = uploader ?? BrowserOpfsDriveFileUploader();` (not in Modify list)
  - `workplace/lib/data/datasource/drive_transfer/drive_transfer_strategy_factory_web.dart:39` — `return OpfsDriveTransferStrategy();` (not in Modify list)
  - `workplace/lib/data/datasource/drive_transfer/buffered_web_drive_file_stager.dart:19`, `workplace/lib/data/datasource_impl/workplace_datasource_impl.dart:35,105` — the in-package precedent an implementer will copy
  - `lib/main/bindings/network/network_bindings.dart:65-69, 88-97` — the authenticated `DioClient` lives in the app package's GetX container, unreachable from `workplace` without injection
- **Suggested fix:** Make the `DioClient` a **required** constructor parameter with no default, all the way up through `OpfsDriveTransferStrategy` and `DriveTransferStrategyFactory.create()`, and state in Phase 1 that it MUST be `Get.find<DioClient>()` (the interceptor-bearing app Dio) and MUST NOT be `WorkplaceDio.instance`. List both files in Modify. Do not defer this to part-3 — Phase 1 does not compile or authenticate without it.

---

## Finding 5: `Uri.decodeFull` on the upload URI introduces a request-target double-decode the current path does not have

- **Severity:** High
- **Location:** Phase 1, "Implementation Steps" 6 (the `_dioClient.post(Uri.decodeFull(request.uploadUri.toString()), ...)` snippet)
- **Flaw:** The snippet is copy-pasted from `FileUploader`, including `Uri.decodeFull`. The upload URI has **already** been percent-decoded once and then re-encoded by URI-template expansion in `Session.getUploadUri`. Decoding it a second time undoes the template's encoding of the server-supplied `accountId`. The current OPFS XHR path passes `request.uploadUri.toString()` verbatim — no decode.
- **Failure scenario:** A JMAP session whose `accountId` contains `%2F`, `%3F` or `%23` after template expansion is decoded back into `/`, `?` or `#`. The POST target silently changes: path segments are appended, or the remainder of the path is demoted to a query string / fragment. The request still carries a valid `Authorization: Bearer` header injected by the interceptor, so an attacker-influenced accountId becomes a way to steer an authenticated, file-carrying POST at a different path on the origin. The plan presents this line as a mechanical port and never flags it.
- **Evidence:**
  - `model/lib/extensions/session_extension.dart:63-68` — `Uri.decodeFull(baseUrl)` then `UriTemplate(...).expand({'accountId': ...})` (encodes) then `Uri.parse`
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:70` — current path: `xhr.open('POST', request.uploadUri.toString())`, no decode
  - `lib/features/upload/data/network/file_uploader.dart:107` — the `Uri.decodeFull(...)` the snippet was copied from
  - `lib/features/composer/presentation/composer_controller.dart:537` — `uploadUri` originates from the server-supplied JMAP session
- **Suggested fix:** Pass `request.uploadUri.toString()` unchanged. If `Uri.decodeFull` is genuinely required for parity with `FileUploader`, the plan must say why and prove the double-decode is a no-op; otherwise drop it and add a Phase 3 assertion that the adapter opens the exact URI it was given.

---

## Finding 6: "Upload target is the JMAP upload URI only" is asserted, never enforced — and the plan removes the only conscious hand-off of the token

- **Severity:** High
- **Location:** Phase 1, "Security Considerations" (second bullet)
- **Flaw:** The plan claims the change cannot turn a drive link into a token carrier, and cites that the download leg sends no credentials. But nothing in the plan validates the *upload* URI's scheme or origin. `uploadUrl` comes from the server-controlled JMAP session document; `getUploadUri` accepts it as-is when it `hasOrigin`. After Phase 1 the bearer is attached automatically by `AuthorizationInterceptors.onRequest` to whatever URL reaches the app Dio — whereas today drive-transfer code had to explicitly hand over an `authHeader`, which is at least an auditable choice. The download leg has an explicit https-only guard; the upload leg gets none, and the plan does not even note the asymmetry.
- **Failure scenario:** A compromised or hostile JMAP server (or a MITM on a plain-http dev/self-hosted deployment) returns `uploadUrl: "https://attacker.example/collect/{accountId}"`. The app POSTs the user's staged drive file **plus `Authorization: Bearer <access token>`** cross-origin. The token is now in the attacker's logs, and because the interceptor also refreshes on 401, the attacker can farm a freshly minted token. The plan's security section explicitly says this cannot happen.
- **Evidence:**
  - `model/lib/extensions/session_extension.dart:53-69` — `getUploadUri` performs no scheme/origin allow-listing; `uploadUrl` is taken from the session
  - `workplace/lib/domain/entity/drive_document_extension.dart:22-25` (`_sanitizeUrl`, https-only) and `:44-51` (`resolveDownloadLinkForStaging`, throws `DriveDownloadInsecureLinkException`) — the guard the download leg has and the upload leg does not
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:101-104` — the header is attached unconditionally by origin-agnostic interceptor logic
- **Suggested fix:** Add an explicit Phase 1 requirement: the routing adapter refuses to send (fail closed, `DioException`) unless `options.uri.origin` matches the configured JMAP origin (`DynamicUrlInterceptors.jmapUrl` / `baseUrl`), mirroring `resolveDownloadLinkForStaging`. Add a Phase 3 test for a mismatched-origin upload URI.

---

## Finding 7: refresh-then-retry of a multi-hundred-MB upload blocks the interceptor's error queue app-wide

- **Severity:** High
- **Location:** Phase 1, "Requirements / Non-functional" ("No upload timeout is imposed"), "Architecture" diagram
- **Flaw:** `AuthorizationInterceptors` is a `QueuedInterceptorsWrapper`; its `_errorQueue` processes exactly one `onError` at a time and only advances when the handler completes. `_performRetry` `await`s the *entire* retried request before resolving. Routing a deliberately untimed, multi-hundred-megabyte upload into that queue means one 401 stalls the queue for the full duration of a complete re-upload. The plan never mentions the queue.
- **Failure scenario:** User transfers a 600 MB drive file on a 10 Mbit uplink (~8 minutes). Token expires mid-transfer, upload 401s, interceptor refreshes and retries — and `handler.resolve` is not called until the retried 600 MB has finished, ~8 more minutes. For those 8 minutes **every other DioException in the app** (mailbox sync failure, session fetch 401, websocket reconnect) sits unprocessed in `_errorQueue`. Nothing recovers, nothing errors out, and there is no timeout because the plan forbids one. The app looks frozen for anything that touches the network error path.
- **Evidence:**
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:28` — `extends QueuedInterceptorsWrapper`
  - `~/.pub-cache/hosted/pub.dev/dio-5.2.0/lib/src/interceptor.dart:367` (`_errorQueue`), `:390-411` (`_handleQueue`: one task at a time), `:414-421` (`_processNextTaskInQueueCallback` only fires when the handler completes)
  - `lib/features/login/data/network/interceptors/authorization_interceptors.dart:456-458` — `await _retryRequest(...)` inside the queued `onError`
  - `lib/main/bindings/network/network_bindings.dart:59-63` — app `BaseOptions` sets no timeouts, so nothing bounds this
- **Suggested fix:** Either (a) make Phase 2's preflight non-optional so a 401 on the upload leg is a genuine edge case, and document the queue-blocking window as an accepted risk with a bound; or (b) have the routing adapter's own 401 path resolve the interceptor handler before the retry body completes. At minimum add this to Phase 1's Risk Assessment with a concrete mitigation.

---

## Finding 8: contract verification — `authHeader` removal breaks 3 suites the plan declares untouched, and misses a third `authHeader` field

- **Severity:** High
- **Location:** Phase 1, "Security Considerations" (bullet 1, "remove them"); Phase 3, "Untouched" list and "Unresolved questions" bullet 2
- **Flaw:** The plan proposes deleting `DriveTransferRequest.authHeader` / `DriveUploadRequest.authHeader` but (a) never mentions the third field in the same chain, `OpfsUploadRequest.authHeader`, nor its writer and reader; and (b) Phase 3 lists as "Untouched" two suites that construct `DriveTransferRequest(authHeader: ...)` and would stop compiling, and never mentions a third suite at all. Explicit counts:
  - Production fields/writers/readers that must change: **6** — `drive_transfer_strategy.dart:28, 67, 76, 91, 99`; `opfs_drive_transfer_strategy.dart:47`; plus `opfs_drive_file_uploader.dart:23, 32` and `opfs_drive_file_uploader_web.dart:63` (**not in any Modify/Delete list**).
  - Test call sites broken: **10** across **4** files — `drive_transfer_strategy_test.dart:74, 141, 152` (never mentioned in the plan); `opfs_drive_file_stager_test.dart:685, 701` (**declared Untouched**); `buffered_web_drive_file_stager_test.dart:247, 257, 275` (**declared Untouched**); `opfs_drive_file_uploader_test.dart:52, 94` (in scope).
  - `DriveUploadTransport` implementors to retire: **4** stub classes in `opfs_drive_file_uploader_test.dart:297, 320, 332, 342` plus its typedef use at `:62`.
- **Failure scenario:** Phase 1 lands, `flutter analyze` fails on three test files the plan promised not to touch, and Phase 3's "Download-leg suites unchanged (diff shows no edits to those files)" success criterion becomes unsatisfiable. The implementer either reverts the removal mid-phase (leaving dead token plumbing — the exact thing the security bullet claims to eliminate) or edits "untouched" files and the phase's own acceptance check is invalid.
- **Evidence:** all file:line citations above, obtained via `grep -rn "authHeader\|DriveUploadTransport" --include="*.dart" lib workplace`.
- **Suggested fix:** Resolve the "Unresolved question" before implementation, not during. If removing: list all 4 test files and both extra production files in Phase 1's Modify list, extend the removal to `OpfsUploadRequest.authHeader`, and correct Phase 3's Untouched/Success-Criteria lists. If deferring: state that the fields stay and the security bullet's claim ("drive-transfer code stops carrying an `authHeader` string entirely") is not yet true.

---

## Finding 9: the app's default `content-type: application/json` silently leaks onto the binary upload

- **Severity:** Medium
- **Location:** Phase 1, "Implementation Steps" 3 (headers come from `options.headers`) and 6 (conditional content-type)
- **Flaw:** Dio merges `BaseOptions.headers` into every request's headers. The app's `BaseOptions` sets `content-type: application/json`. The plan's uploader snippet only *adds* a content type when `request.mimeType` is non-empty; it never removes the inherited default. The current XHR path builds its header set from scratch, so no default leaks in.
- **Failure scenario:** An OPFS-staged file with a null/empty mime type (the plan itself notes OPFS-created `File`s carry an empty type) is uploaded with `Content-Type: application/json`. The JMAP server records the blob type as `application/json`; the resulting attachment is mislabelled and, on some servers, the upload endpoint rejects or mis-parses a JSON-typed binary body. Phase 3's header test as written ("`Content-Type` passes through") would pass while the bug ships.
- **Evidence:**
  - `lib/main/bindings/network/network_bindings.dart:59-63` — `BaseOptions(headers: {accept: ..., content-type: Constant.contentTypeHeaderDefault})`
  - `core/lib/data/constants/constant.dart:3` — `contentTypeHeaderDefault = 'application/json'`
  - `~/.pub-cache/hosted/pub.dev/dio-5.2.0/lib/src/options.dart:301-308` — `Options.compose`: `caseInsensitiveKeyMap(baseOpt.headers)` then per-request overrides
  - `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:128-137` — current path sets only Authorization / Accept / conditional Content-Type
- **Suggested fix:** The uploader must explicitly clear `content-type` when `mimeType` is empty (or the adapter must strip inherited content-type for the OPFS route, as it already does for `content-length`). Add a Phase 3 test: empty mimeType → no `Content-Type` reaches `setRequestHeader`.

---

## Finding 10: the mobile stub fails open — an OPFS extra on IO silently sends an authenticated empty POST; header stringification unspecified

- **Severity:** Medium
- **Location:** Phase 1, "Implementation Steps" 5 (mobile stub) and 3 (headers from `options.headers`)
- **Flaw (a):** `createDriveUploadRoutingAdapter(delegate) => delegate` is a pure passthrough. If any code path ever sets `opfsUploadFileExtraKey` on a non-web build (a shared orchestration layer, a mis-branched factory, a test), the file resolver is silently ignored and Dio sends `data: null` — a POST with a valid bearer and no body. Fail-open, not fail-closed.
- **Flaw (b):** `options.headers` is `Map<String, dynamic>` and may hold non-String or null values (`FileUploader` puts an `int` content-length in there). The plan says "headers come from `options.headers`" without specifying `'$v'` stringification or null-skipping. dio's own browser adapter does exactly that; the plan cites that file for `content-length` stripping but not for the stringification on the very next line.
- **Failure scenario (a):** A future part-3 wiring change routes drive transfer through shared code; on Android the strategy factory picks a non-OPFS path but the extra is set anyway. A zero-byte blob is created server-side under the user's account and attached to an outgoing email as a "successful" upload, with no error anywhere.
- **Failure scenario (b):** A non-String header value reaches `xhr.setRequestHeader` and throws a JS type error, which the plan's step 4 maps to `DioExceptionType.connectionError` — the upload is reported as a network failure and never as the header bug it is.
- **Evidence:**
  - `~/.pub-cache/hosted/pub.dev/dio-5.2.0/lib/src/adapters/browser_adapter.dart:49-50` — `options.headers.remove(Headers.contentLengthHeader); options.headers.forEach((key, v) => xhr.setRequestHeader(key, '$v'));` — the plan cites line 49 and omits line 50
  - `lib/features/upload/data/network/file_uploader.dart:95-96` — an `int` is written into a header map on the same shared Dio
  - `workplace/lib/data/datasource/drive_transfer/opfs_file_handle.dart:2` — the conditional-export idiom the stub mirrors
- **Suggested fix:** Mobile stub should throw (or the uploader should assert) when the OPFS extra is present on a non-web adapter — fail closed. Specify `'$v'` stringification and null-skipping in step 3, and add a Phase 3 case for a non-String header value.

---

## Verification Results

**Tier:** Standard (Fact Checker + Contract Verifier)
**Claims sampled:** 24 across 3 phases + plan.md

**VERIFIED (18)**
| Claim | Evidence |
|---|---|
| `_createRetryDio()` copies `_dio.httpClientAdapter` | `authorization_interceptors.dart:670-671` |
| Retry byte-stream branch is gated on `FileUploader.uploadAttachmentExtraKey` | `authorization_interceptors.dart:645` |
| `retryDio.fetch(requestOptions)` preserves extra/headers/onSendProgress | `authorization_interceptors.dart:664`; `dio-5.2.0/lib/src/options.dart:621` (`RequestOptions.onSendProgress` field) |
| `data == null` → null request stream, adapter still invoked | `dio-5.2.0/lib/src/dio_mixin.dart:563-570` (`_transformData` at `:604`), `:541-546` |
| dio browser adapter strips `content-length` | `dio-5.2.0/lib/src/adapters/browser_adapter.dart:49` |
| `HttpClientAdapter()` is a platform factory constructor | `dio-5.2.0/lib/src/adapter.dart:27` |
| `DioException.connectionError` hardcodes `error: null` (so hand-build it) | matches existing `opfs_xhr_upload.dart:169-183` rationale |
| App `BaseOptions` sets no timeouts | `network_bindings.dart:59-64` |
| Sentry must be installed last / wraps the adapter | `sentry_dio-9.8.0/lib/src/sentry_dio_extension.dart:102-106`; `network_bindings.dart:97` |
| `opfs_xhr_upload.dart:50` self-documenting comment quoted accurately | `opfs_xhr_upload.dart:49-50` |
| XHR body to port sits at `opfs_xhr_upload.dart:59-123` | verified |
| Conditional-export barrel idiom | `opfs_file_handle.dart:1-3` |
| `DioClient.post` accepts `onSendProgress` and adds `Accept: jmapHeader` | `dio_client.dart:57-81`, `:7` |
| `workplace` depends on `core` | `workplace/pubspec.yaml` (`core: path: ../core`) |
| `createXhr()` test seam exists | `opfs_xhr_upload.dart:126` |
| `onRequest` attaches nothing for `AuthenticationType.none` | `authorization_interceptors.dart:106-107` |
| Commits `7cbda0dd0` / `7d7ad0f15` on `feat/add_as_attachment` | git log |
| Download leg sends no credentials | `opfs_fetch_download.dart` / `drive_document_extension.dart` |

**FAILED (5)**
1. **"the header is only set when `isTokenValid()`" ⇒ no header on an expired token** (Phase 2 Overview). `isTokenValid()` ignores expiry — `token_oidc.dart:61`. See Finding 1.
2. **`authorization_interceptors.dart:348-376` is the refresh body** (Phase 2, Architecture A). Lines 375-376 are retry code (`_refreshAttemptedKey`, `_performRetry`) and 357-366 is a guard that needs `err`/`handler`. The range is not extractable as stated. See Finding 2.
3. **`test/features/login/data/network/interceptors/authorization_interceptors_test.dart`** (Phase 2, Related Code Files). Path does not exist; the suite is `test/features/interceptor/authorization_interceptor_test.dart`. Consequently Phase 3 step 4's `flutter test test/features/login/` runs **none** of the interceptor tests that Phase 2 step 1 depends on to prove the extraction is inert.
4. **`dio_mixin.dart:592` raises `DioException.badResponse`** (Phase 1, step 4). Actual site is `dio-5.2.0/lib/src/dio_mixin.dart:570`.
5. **"remove `DriveTransferRequest.authHeader` / `DriveUploadRequest.authHeader` … they were documented as OPFS-only"** — a third field, `OpfsUploadRequest.authHeader` (`opfs_drive_file_uploader.dart:23`), is in the same chain and is unlisted. See Finding 8.

**UNVERIFIED (1)**
- Phase 1 step 3's "`options.headers` already carries `Authorization`" — true only if the uploader is given the **app** `DioClient`; the plan never names the source. Unresolvable as written (Finding 4).

**Contract verification — explicit consumer counts**
| Interface change | Consumers | Files |
|---|---|---|
| Delete `DriveUploadTransport` / `XhrUploadHandle` / `XhrUploadFileRequest` | 9 prod + 12 test refs | `opfs_xhr_upload.dart`, `opfs_drive_file_uploader_web.dart:23,28,31,49,60`, `opfs_drive_file_uploader_test.dart:62,297,302,305,308,320,322,332,334,342,357,368` |
| Change `BrowserOpfsDriveFileUploader` ctor | 2 construction sites | `opfs_drive_transfer_strategy.dart:20` (**unlisted**), `opfs_drive_file_uploader_test.dart:65` |
| Thread `DioClient` to `OpfsDriveTransferStrategy` | 2 construction sites | `drive_transfer_strategy_factory_web.dart:39` (**unlisted**), `opfs_drive_file_stager_test.dart:669` |
| Remove `authHeader` (3 classes) | 6 prod + 10 test refs / 4 test files | see Finding 8 |
| Install adapter on shared app Dio | 1 site; affects **every** authenticated request | `network_bindings.dart:88-97` |
| New public `ensureTokenFresh()` | 0 call sites in this plan (deferred to a non-existent part-3 plan) | — |

---

## Unresolved questions

1. Which `DioClient` instance is the OPFS uploader supposed to receive, and who injects it in Phase 1 (not part-3)?
2. Is the upload URI trusted to be same-origin with the JMAP server, and if so, what enforces it?
3. Does the team accept an unbounded `_errorQueue` stall during a large-file refresh-retry, or must Phase 2 become mandatory?
4. Is `authHeader` removal in scope for Phase 1 or deferred? Phase 1 and Phase 3 currently disagree.
