---
phase: 1
title: "Interceptor refresh gateway"
status: pending
priority: P1
effort: "1.5-2d"
dependencies: []
---

# Phase 1: Interceptor refresh gateway

# [RED TEAM REVISED 2026-08-14] — see "Red team changes" at the end for what moved.

## Overview

Add `ensureFreshAuthorizationHeader({bool forceRefresh = false})` to
`AuthorizationInterceptors` as the app's only non-Dio auth entry point, backed by
a single-flight `_refreshTokenOnce()` memo shared with the Dio 401 path. This is
the riskiest phase — it refactors live auth code — so it lands first and alone.

## Requirements

Functional:
- `ensureFreshAuthorizationHeader()` returns the header to send, refreshing first
  when the token is expired-or-expiring (see lead time) or when `forceRefresh` is
  set.
- A refresh already in flight **on the same interceptor instance** is joined,
  never duplicated.
- A refresh resolving during or after logout performs **no** durable write.
- A refresh rejected **by the token endpoint** clears the session and throws
  `RefreshTokenFailedException`. A transport/network/unclassified failure **keeps
  the session** and throws the original error. These are not the same thing, and
  conflating them would undo work just shipped on this branch (`3dabbbe94`,
  `aad7df7b3`, `fa12f7198`, `bfde3527a`).
- The refresh is bounded by a timeout; exceeding it is transient, not a rejection.
- A cleared session is distinguishable from a never-authenticated one, so callers
  can abort rather than send an unauthenticated request.
- The Dio 401 path behaves as today, including forced-logout classification and
  Sentry tagging.

Non-functional:
- No forked refresh logic: keychain lookup, persistence, account-cache update and
  error classification are reached through the existing private chain.
- No behaviour change for `basic` / `none` auth.

## Architecture

```
AuthorizationInterceptors  (NOTE: two instances exist — see "Instance scope")
  _sessionEpoch: int        bumped by clear() AND by setTokenAndAuthorityOidc()
  _refreshTokenOnce() ───── single-flight memo (assign-before-await, cleared in whenComplete)
     |                       performs: _getNewToken… -> epoch recheck -> _updateNewToken
     |                                 -> _updateCurrentAccount -> keychain(iOS)
     |                       returns:  _RefreshOutcome(token, previousToken, performed)
     |
     ├── _refreshTokenThenRetry()          (Dio 401 path)
     │      duplicate-token guard, against outcome.previousToken
     │      then _refreshAttemptedKey + _performRetry
     │
     └── ensureFreshAuthorizationHeader()  (new, off-Dio)
            guards -> maybe refresh -> AuthHeaderResult
```

### Return type: not a bare `String?`

A bare nullable string cannot distinguish "no auth configured" from "the session
just died", and the second must **not** result in an unauthenticated request. On
the retry path that would POST a whole drive file with no credential.

```dart
sealed class AuthHeaderResult {}
class AuthHeaderAvailable implements AuthHeaderResult { final String header; }
class AuthHeaderNone      implements AuthHeaderResult {}  // basic/none, never authenticated
class AuthHeaderUnavailable implements AuthHeaderResult {} // session cleared mid-flight
```

Phase 2's typedef carries this type, and Phase 3 aborts on `AuthHeaderUnavailable`
instead of sending. (`AuthHeaderNone` still means "send no header" — that is a
legitimate unauthenticated backend, not a dead session.)

### Three rules from ADR-0105, plus one correction

1. **Expiry is `_isTokenExpired`, never `isTokenValid()`.** `isTokenValid()` is
   `token.isNotEmpty && tokenId.uuid.isNotEmpty` (`model/lib/oidc/token_oidc.dart:62`),
   with no expiry term.
2. **Non-OIDC short-circuits before touching `_configOIDC`.** `_invokeRefreshTokenFromServer`
   dereferences `_configOIDC!` and `_token!` (`authorization_interceptors.dart:613-617`).
   Guard on **`_isAuthenticationOidcValid()`** (`:504`), which checks the config is
   non-null — not on the auth type alone. `oidc` with a null config is reachable:
   `setTokenAndAuthorityOidc` takes a nullable config (`:72`) and
   `_classifySkippedRefresh401` has a dedicated `forced_logout_401_oidc_config_missing`
   branch (`:178`). Without this, a null-config crash poisons the *shared* memo for
   the Dio path too.
3. **A missing refresh token is not a refresh.** Return the current header and let
   the server's 401 decide — the gate `validateToRefreshToken` already applies
   (`:510-533`).
4. **Lead time (correction to the ADR).** `isExpired` is a bare
   `expiredTime!.isBefore(now)` (`token_oidc.dart:66-73`), so a token expiring 90
   seconds into an eight-minute upload is "fresh" at send time, dies mid-flight,
   and the retry costs a **full re-upload** — not just a re-request. Refresh when
   the token expires within a lead window (start at 2 minutes; it must exceed a
   typical send duration only for small files, not large ones — the retry remains
   the backstop for long uploads).
   Note `expiredTime` is never null on the OIDC path:
   `lib/features/login/data/extensions/authentication_token_extension.dart:12`
   sets `accessTokenExpirationDateTime ?? DateTime.now()`, so a token whose
   response omitted the expiry is **born already expired**. Confirm the lead
   window does not turn that into a refresh on every single upload; if it does,
   treat `expiredTime == construction time` as unknown-expiry and skip the
   proactive refresh.

### G1: the duplicate-token guard (the gap in ADR-0105)

The guard compares against `_token` *before* `_updateNewToken` assigns it:

```dart
// authorization_interceptors.dart:357-367 (today)
final newTokenOidc = ...;
if (newTokenOidc.token == _token?.token) {     // :357 — reads the OLD token
  _logForcedLogoutFor401(
    authErrorType: 'forced_logout_401_refreshed_token_duplicated', ...);
  return super.onError(err, handler);
}
_updateNewToken(newTokenOidc);                 // :367 — assignment happens after
```

Once the memo owns the assignment, a joining caller resumes with `_token` already
updated, the comparison is trivially true, and the user is force-logged-out after
a **successful** refresh.

Fix: the memo returns the pre-refresh token it started from; the guard compares
against that snapshot, and only the caller that *performed* the refresh evaluates
it (`outcome.performed`).

**Accepted behaviour change, documented rather than hidden:** when the OPFS caller
performs the refresh and a Dio 401 joins, that Dio caller no longer evaluates the
duplicate check, so an IdP returning the same token produces one extra retry
before forced logout instead of logging out immediately. The outcome converges —
the retry re-401s with `_refreshAttemptedKey` set and falls to the
`forced_logout_401_after_refresh_attempted` branch (`:172-174`) — but the Sentry
tag differs. Note this in the code comment so the tag change is not read as a
regression later.

### Logout policy: the classifier must be extracted, not "reused"

Saying the off-Dio path is "routed through the same classifier" is not
implementable as written. `_handleRefreshErrorOnWeb` (`:209-253`) and
`_handleRefreshErrorOnMobile` (`:287-310`) both take an `ErrorInterceptorHandler`
and a `DioException originalError` and terminate in `handler.reject(...)` — they
are structurally unreachable from a caller that has neither.

Both already contain the decision this phase needs, buried in handler plumbing:
clear **only** when `_errorClassifier.isServerRejection(error)` (`:217`, `:293`);
otherwise log and keep the session (`:247-252`).

Required step: extract that predicate into a handler-free
`bool _shouldLogoutForRefreshError(Object error)` used by **both** entry points,
so the Dio path and `ensureFreshAuthorizationHeader` cannot drift on the one
decision that logs users out. Without it, the literal reading of "a rejected
refresh clears the session" force-logs-out a user on flaky wifi mid-upload and
wipes their local cache — precisely the regression the four recent auth commits
fixed for the Dio path.

### Refresh timeout — the stall the memo would otherwise reintroduce

There is no timeout anywhere in the refresh chain: not in
`_invokeRefreshTokenFromServer` (`:610-619`), not in the web client's
`refreshingTokensOIDC`
(`lib/features/login/data/network/authentication_client/authentication_client_web.dart:76-104`),
not in the interceptor. That is survivable today because refreshes only start
inside dio's error queue.

After this phase, `_refreshTokenThenRetry` can **join a memo started off-Dio**.
If that memo never settles (IdP accepts the connection and never answers;
`flutter_appauth` channel hangs), the Dio caller awaits it *inside*
`QueuedInterceptor`'s serialized `_errorQueue`, so the queue head never advances
and every subsequent Dio error in the app stalls unbounded for the tab's lifetime.

That is structurally the same unbounded-stall failure this plan cites as the
reason for rejecting the adapter approach — reintroduced through the memo instead
of the request path. Mitigation is mandatory, not optional:
- Hard timeout on `_refreshTokenOnce()` (start at 30s).
- A timeout classifies as **transient** — keep the session.
- Clear the memo on timeout so the next caller can retry rather than joining a
  dead future.

### Epoch guard — placement matters more than existence

`clear()` nulls in-memory fields only (`:673-678`) and cannot cancel an in-flight
refresh, while `_updateCurrentAccount` writes durably (`:570-589`).

**The naive design does not work.** `BaseController._clearAllData()` runs
`cachingManager.clearAll()` **before** `authorizationInterceptors.clear()`
(`lib/features/base/base_controller.dart:652-662`), so a refresh resolving inside
that window sees an unmoved epoch, passes a single up-front check, and re-persists
a live token and selected account into the just-wiped boxes.

Requirements for the guard:
- **Bump early.** Increment the epoch at the *start* of logout, not only in
  `clear()`. Add a public `beginSessionTeardown()` (or bump from `clear()` *and*
  have `_clearAllData` call it before `cachingManager.clearAll()`).
- **Bump on identity change too.** `setTokenAndAuthorityOidc` (`:72`) swaps
  session identity without going through `clear()` — called from
  `reloadable_controller.dart:138` and `fcm_message_controller.dart:195`. A stale
  refresh must not clobber a newer token.
- **Re-check between every durable write, not once.** `_updateCurrentAccount` has
  three awaits (`getCurrentAccount`, `persistOneTokenOidc`, `setCurrentAccount`,
  `:571-586`) and the iOS keychain save is a fourth (`:371-373`). A single check
  before the first write leaves the rest exposed; the epoch can move mid-sequence.
- Re-checking `_authenticationType` alone is insufficient — a re-login between
  capture and check restores `oidc` and passes a type check while being a
  different session.

### Instance scope (must be stated, not assumed)

**Two `AuthorizationInterceptors` instances exist:** the main one
(`network_bindings.dart:92`) and an isolate-tagged one
(`network_isolate_binding.dart:52-62`, `Get.put(..., tag: BindingTag.isolateTag)`),
both held by `BaseController` (`base_controller.dart:79-80`). The memo is an
instance field, so single-flight does **not** span them.

Decision for this plan: the drive OPFS path is web-only and the resolver binds to
the **main** instance (`Get.find<AuthorizationInterceptors>()`, untagged). Record
that cross-instance refresh coordination is unchanged and out of scope — the same
carve-out ADR-0105 makes for multi-tab. Do not claim app-wide single-flight.

## Related Code Files

Modify:
- `lib/features/login/data/network/interceptors/authorization_interceptors.dart`
- `lib/features/base/base_controller.dart` — bump the epoch before
  `cachingManager.clearAll()` in `_clearAllData()` (`:652-662`)
- `test/features/interceptor/authorization_interceptor_test.dart`
  (path is `test/features/interceptor/`, **not** `test/features/login/...`)

Regenerate (do not hand-edit):
- **17 `.mocks.dart` files** contain `class MockAuthorizationInterceptors`
  (`grep -rln "class MockAuthorizationInterceptors" test` → 17). Adding a public
  method breaks every one of them. `dart run build_runner build --workspace
  --delete-conflicting-outputs` is a required step, and the phase is not done
  until the **full** suite compiles — not just the interceptor suite.

## Implementation Steps

1. **Add the epoch and its bump points.** `int _sessionEpoch = 0;` incremented in
   `clear()`, in `setTokenAndAuthorityOidc`, and at the start of logout teardown
   (`_clearAllData`, before `cachingManager.clearAll()`). No other behaviour
   change. Run the existing suite.
2. **Extract `_refreshTokenOnce()`** returning `Future<_RefreshOutcome>`:
   capture `previousToken = _token?.token` and `epoch = _sessionEpoch` *before*
   the await; perform `_getNewTokenForIOSPlatform` / `_getNewTokenForOtherPlatform`;
   then re-check the epoch **before each** of `_updateNewToken`,
   `persistOneTokenOidc`, `setCurrentAccount` and the iOS keychain save, abandoning
   the result on mismatch. Memo: assign the future to a field before awaiting,
   clear in `whenComplete`, and attach a no-op `catchError` to the stored future so
   a failure with no joiner is not an unhandled async error. Wrap the whole memo
   in `.timeout(const Duration(seconds: 30))`, clearing the memo field so a
   timed-out refresh does not strand later joiners.
2b. **Extract `_shouldLogoutForRefreshError(Object error)`** from
   `_handleRefreshErrorOnWeb` / `_handleRefreshErrorOnMobile` (the
   `_errorClassifier.isServerRejection` decision at `:217` / `:293`), leaving both
   handlers to call it. Pure refactor; run the suite before continuing.
3. **Rewire `_refreshTokenThenRetry`** to call `_refreshTokenOnce()` and evaluate
   the duplicate-token guard against `outcome.previousToken`, gated on
   `outcome.performed` (G1). `_refreshAttemptedKey` and `_performRetry` stay in
   `_refreshTokenThenRetry` — retry-only code must not move into the shared memo.
   Preserve the `on DioException` / `on PlatformException` / generic `catch`
   classification, and propagate the original `StackTrace` to joiners
   (`completeError(e, st)`).
4. **Add `ensureFreshAuthorizationHeader({bool forceRefresh = false})`** returning
   `AuthHeaderResult`:
   - `basic` → `AuthHeaderAvailable(basic header)`; `none` → `AuthHeaderNone`.
     Neither touches `_configOIDC`.
   - not `_isAuthenticationOidcValid()` (covers null config) → `AuthHeaderNone`.
   - oidc, no refresh token → current bearer unchanged.
   - oidc, `forceRefresh` or expired/within-lead-window → `await _refreshTokenOnce()`,
     return the new bearer.
   - session cleared during the call (epoch moved, or type became `none`) →
     `AuthHeaderUnavailable`.
   - refresh failed → ask `_shouldLogoutForRefreshError(error)`. **True** (token
     endpoint rejected it): `clear()` and throw `RefreshTokenFailedException`
     (`lib/main/exceptions/remote/authentication_exception.dart`). **False**
     (transport, timeout, unclassified): keep the session and rethrow the original
     error, so the caller fails one upload instead of the user's session.
5. Reuse `_getTokenAsBearerHeader` / `_getAuthorizationAsBasicHeader`.
6. `dart run build_runner build --workspace --delete-conflicting-outputs`, then
   `flutter analyze` and the **full** `flutter test` (not just the interceptor
   suite — see the 17 mocks).

## Success Criteria

- [ ] Two concurrent callers on the same instance (one Dio 401, one
      `ensureFreshAuthorizationHeader`) → exactly one `refreshingTokensOIDC` call,
      two successful outcomes, **zero** logouts. (G1 regression test.)
- [ ] A refresh genuinely returning the same token still logs
      `forced_logout_401_refreshed_token_duplicated` when the Dio caller performed it.
- [ ] A refresh resolving after the epoch moves performs no `_updateNewToken`, no
      `persistOneTokenOidc`, no `setCurrentAccount`, no keychain write —
      **including** when the epoch moves between two of those writes.
- [ ] Logout ordering test: epoch bump precedes `cachingManager.clearAll()`.
- [ ] `ensureFreshAuthorizationHeader` returns `AuthHeaderUnavailable` (never
      `AuthHeaderNone`) when the session is cleared mid-call.
- [ ] No network call for a valid token outside the lead window; none at all under
      `basic` / `none` / null-config.
- [ ] A refresh rejected by the token endpoint clears the session and throws
      `RefreshTokenFailedException`.
- [ ] **A `connectionError` during an off-Dio refresh does NOT call `clear()`** —
      the session survives, one upload fails. Same for a timeout.
- [ ] A refresh that never settles does not block a subsequent Dio 401 for longer
      than the timeout, and the next caller starts a fresh refresh rather than
      joining the dead one.
- [ ] Memo failure does not poison the next refresh; a failure with no joiner
      raises no unhandled async error.
- [ ] All 17 `.mocks.dart` regenerated; **full** `flutter test` compiles and passes.

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| **G1** — joiner trips the duplicate guard, logging out after a successful refresh | Guard compares `outcome.previousToken`, gated on `performed`; two-concurrent-callers test |
| Session resurrection during logout (epoch bumped too late) | Bump at teardown start, before `cachingManager.clearAll()`; ordering test |
| Partial durable writes when the epoch moves mid-sequence | Re-check before each of the four writes, not once |
| Stale refresh clobbering a newer session established without `clear()` | Bump on `setTokenAndAuthorityOidc` too |
| 17 mock files break the build outside the touched suite | build_runner step is explicit; the gate is the full suite, not the interceptor suite |
| Null-config `oidc` crash poisoning the shared memo | Guard on `_isAuthenticationOidcValid()`, not auth type |
| Lead window causing a refresh on every upload for `?? DateTime.now()` tokens | Explicitly checked in step 4; fallback is to treat that shape as unknown-expiry |
| Cross-instance refresh (main vs isolate) still uncoordinated | Stated as out of scope, matching the ADR's multi-tab carve-out; resolver pinned to the main instance |
| **Logging users out on transient failures**, undoing `3dabbbe94`/`aad7df7b3`/`fa12f7198`/`bfde3527a` | Requirement split by cause; `_shouldLogoutForRefreshError` extracted so both entry points share one predicate; explicit "connectionError does not clear()" criterion |
| **A hung off-Dio refresh stalling dio's error queue** — the same unbounded stall used to reject the adapter approach, reintroduced via the memo | 30s timeout on the memo, classified transient, memo cleared so later callers retry |

## Security Considerations

- `AuthHeaderAvailable.header` is the token in bearer form. It is handed to one
  caller and never stored, logged, or placed in `RequestOptions.extra`.
- `AuthHeaderUnavailable` exists specifically so a dead session cannot be
  downgraded into an unauthenticated request.
- Forced-logout tagging and Sentry extras keep their shape, except the documented
  G1 tag change.
- The bearer still goes to a server-supplied `uploadUrl` with no origin check
  (`model/lib/extensions/session_extension.dart:53-69`). Pre-existing and shared
  with `FileUploader`, but this design **amplifies** it: the token is now
  guaranteed-fresh, a forced refresh can be induced, and the body is sent twice.
  Out of scope here; raise as its own ticket.

## Red team changes (2026-08-14)

Applied: epoch bump moved to teardown start + `setTokenAndAuthorityOidc`, with
per-write re-checks; `AuthHeaderResult` replaces `String?` so a cleared session
cannot become an unauthenticated send; null-config `oidc` short-circuit; expiry
lead window; 17-mock regeneration; instance-scope decision; G1 tag-change
documented. Effort raised 1-1.5d → 1.5-2d.
