---
phase: 2
title: "Preflight token freshness"
status: pending
priority: P2
effort: "0.5-1d"
dependencies: [1]
---

# Phase 2: Preflight token freshness

## Overview

Phase 1 makes a 401 recoverable, but not free. Staging a multi-hundred-megabyte
drive file can outlive an access token, and when the token is already expired at
upload start `AuthorizationInterceptors.onRequest` attaches **no** Authorization
header at all (`authorization_interceptors.dart:102` — the header is only set when
`isTokenValid()`), so the request is guaranteed to 401 and the file may be pushed
across the wire twice.

This phase refreshes the token *before* the upload leg starts, when it is already
expired.

Separable: skipping it leaves Phase 1 correct, only wasteful on large files with a
dead token.

## Requirements

Functional:
- Before the upload leg, an expired OIDC token is refreshed once.
- A refresh already in flight (from Dio's queued interceptor) is joined, never
  duplicated — refresh tokens are frequently one-time-use, so two concurrent
  refreshes can invalidate the session.
- Preflight failure is non-fatal: log and continue into the upload, letting the
  existing 401 path stay the single authority on forced logout.

Non-functional:
- No duplication of refresh-error classification, forced-logout tagging, iOS
  keychain handoff or account-cache persistence.

## Architecture

Two options. Recommended is A; B is the zero-auth-change fallback if touching
`AuthorizationInterceptors` is judged too risky this close to the feature branch.

**A. `ensureTokenFresh()` on AuthorizationInterceptors (recommended)**

```
AuthorizationInterceptors
  _refreshCore()                  <- extracted from _refreshTokenThenRetry
  _inFlightRefresh: Completer?    <- single-flight guard, shared by both entries
  |- onError 401 path             (existing)
  '- ensureTokenFresh()           (new, public)
```
- Extract the body between "Perform get New Token" and `_updateNewToken` +
  `_updateCurrentAccount` + iOS keychain save (`authorization_interceptors.dart:348-376`)
  into `_refreshCore()`.
- Wrap it in a single-flight completer that **both** entry points await, so a
  preflight and a queued 401 refresh cannot overlap.
- `ensureTokenFresh()` returns early unless
  `_authenticationType == AuthenticationType.oidc && _configOIDC != null &&
  _isTokenExpired(_token) && _isRefreshTokenNotEmpty(_token)`.
- Errors are swallowed at the call site, not reclassified here — the existing
  handlers keep sole ownership of the logout decision.

**B. Cheap warm-up request (fallback)**

Before the upload leg, issue an existing cheap authenticated Dio call (e.g. the
JMAP session fetch). If the token is dead, the interceptor refreshes on *that*
request's 401 and the cheap call pays the cost instead of the upload. Zero change
to auth code; costs one extra round trip per transfer and depends on an unrelated
endpoint staying cheap.

## Related Code Files

Option A:
- Modify: `lib/features/login/data/network/interceptors/authorization_interceptors.dart`
  — extract `_refreshCore()`, add `_inFlightRefresh` single-flight, add public
  `ensureTokenFresh()`.
- Modify: the drive-transfer orchestration entry (main-app side, exact call site
  lands with the part-3 wiring plan) — `await ensureTokenFresh()` between stage and
  upload, wrapped in try/catch that only logs.
- Modify: `test/features/login/data/network/interceptors/authorization_interceptors_test.dart`
  (or the nearest existing suite) for the new surface.

## Implementation Steps

1. Extract `_refreshCore()` with no behaviour change; run the existing interceptor
   tests to prove the extraction is inert **before** adding anything.
2. Add `Future<void> _sharedRefresh()` holding a `Completer<void>? _inFlightRefresh`:
   first caller runs `_refreshCore()`, later callers await the same future, and the
   field is cleared in `finally`.
3. Route the existing 401 path through `_sharedRefresh()`.
4. Add `ensureTokenFresh()` with the precondition guard above; make it a no-op for
   basic auth and for a still-valid token.
5. Call it from the drive-transfer orchestration between stage and upload, logging
   and swallowing failures.
6. Verify no double-refresh: test two concurrent callers observe one
   `refreshingTokensOIDC` invocation.

## Success Criteria

- [ ] Expired token + drive transfer -> exactly one refresh, then one upload
      (no 401, no double send).
- [ ] Concurrent preflight + Dio 401 refresh -> one `refreshingTokensOIDC` call.
- [ ] Valid token -> `ensureTokenFresh()` performs no network call.
- [ ] Preflight failure does not fail the transfer and does not log the user out
      on its own.
- [ ] All pre-existing `AuthorizationInterceptors` tests still pass unchanged.

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Refactoring live auth code on a feature branch | Step 1 is a pure extraction verified by the existing suite before any new behaviour is added |
| Single-flight completer leaking on error | Clear in `finally`; test the error path re-allows a later refresh |
| Preflight racing the queued interceptor and burning a one-time-use refresh token | The shared completer is the whole point — both entry points must go through it, never `_refreshCore()` directly |
| Preflight swallowing a genuinely dead session and hiding logout | Deliberate: the 401 path still runs immediately after and owns the logout decision |

## Security Considerations

- `ensureTokenFresh()` exposes no token material; it returns `void` and leaves the
  header to `onRequest`.
- The forced-logout classification and Sentry tagging paths are untouched, so
  auth-failure forensics keep their current shape.
