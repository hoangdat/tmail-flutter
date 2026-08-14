---
phase: 3
title: "OPFS uploader late-resolve and retry-once"
status: pending
priority: P1
effort: "1d"
dependencies: [1, 2]
---

# Phase 3: OPFS uploader late-resolve and retry-once

# [RED TEAM REVISED 2026-08-14] — see "Red team changes" at the end.

## Overview

Resolve the auth header immediately before `xhr.send` instead of at transfer
start, and on a 401 refresh once and resend the same staged file. The staged file
is still on OPFS and the strategy still owns its `dispose()` in a `finally`, so
the replay costs no re-download.

It does cost a **full re-upload**. That is the trade, and it is why Phase 1 adds a
lead window rather than relying on the retry.

## Requirements

Functional:
- The header is resolved inside `BrowserOpfsDriveFileUploader.upload`, per attempt.
- On HTTP 401 with the retry unused: check cancellation, then **re-resolve with
  `forceRefresh: false` first** and force a refresh only if the header comes back
  identical to the one that just 401'd (see "Don't force what someone else already
  refreshed"), then resend the same `web.File` once.
- A second 401 fails the file normally. The bound is a flag, never a loop.
- A cancel during the refresh gap stays a cancel, not an auth error.
- `AuthHeaderNone` → send no `Authorization` header (legitimate unauthenticated
  backend). `AuthHeaderUnavailable` → **abort without sending**; the session died
  mid-transfer and an unauthenticated POST of the file body is not an acceptable
  fallback.
- A refresh rejection surfaces to the composer with its identity intact (see
  "Exception boundary").

Non-functional:
- Streaming unchanged: the `File` still goes to `xhr.send` directly.
- No `xhr.timeout`; cancellation remains the mechanism.

## Architecture

Retry lives in `BrowserOpfsDriveFileUploader.upload`
(`opfs_drive_file_uploader_web.dart:43`), not in `OpfsXhrUpload`. The transport
stays a dumb one-shot send; the uploader owns the policy and keeps the
`_store` / `FileUtils` seams.

```
upload(request):
  try {                                  # everything stays inside the one try
    throwIfCancelled
    file = store.getFile(handle)         # once; reused by both attempts
    charsetFuture = resolveCharset(file)
    attempt(forceRefresh: false)
      result = await request.resolveAuthHeader(forceRefresh: …)
      if result is AuthHeaderUnavailable -> throw (no send)
      throwIfCancelled                   # cancel during resolve
      send …
    on 401 && !retried:
      throwIfCancelled                   # cancel during the refresh gap
      retried = true
      attempt(forceRefresh: true)
  } catch (e) { throwIfCancelled; throw _asDioFailure(e, uri); }
```

**Keep `getFile` inside the `try`.** The file's doc comment
(`opfs_drive_file_uploader_web.dart:34-41`) documents that every leg sits inside
one `try` precisely because `getFile` throws a bare `DOMException` when the entry
has gone. Hoisting it out to share the handle across attempts would break the
"all failures become `DioException`" contract.

Reusing one `web.File` across attempts is safe: the stager writes it before
`stage()` returns, the strategy's `finally` disposal runs only after `upload()`
completes (`drive_transfer_strategy.dart:24-35`), and the stale sweep is 4h-scoped
(`opfs_file_ops.dart:89-93`). It also keeps the charset sniff working off the same
handle it already uses at `:58`.

### Don't force what someone else already refreshed

Phase 1's memo only collapses refreshes that overlap **in flight**. Concurrent
drive uploads do not 401 together — each 401 lands when its own multi-hundred-MB
send finishes, seconds to minutes apart. So an unconditional
`forceRefresh: true` on every 401 produces one refresh per file, nearly all
gratuitous: five files sharing token T1 give five sequential refreshes, four of
which would have succeeded with the T2 the first refresh already fetched. Against
an IdP with refresh-token reuse detection or token-endpoint rate limiting, that is
an account-level revocation.

The Dio path already solves this, and the uploader should mirror it:
`validateToRetryTheRequestWithNewToken` (`authorization_interceptors.dart:535-564`)
is checked *before* the refresh branch (`:124-133`) and retries with the
already-updated token without refreshing at all.

Uploader equivalent: remember the header that 401'd; on retry call
`resolveAuthHeader(forceRefresh: false)`; only if the returned header is identical
does it call again with `forceRefresh: true`. Costs one extra cheap call, removes
the stampede.

### Exception boundary — `RefreshTokenFailedException` does not cross into workplace

`RefreshTokenFailedException` lives in `lib/main/exceptions/remote/authentication_exception.dart`,
which `workplace` cannot import (Phase 2 forbids adding the dependency, and the
direction is app → workplace). Worse, `_asDioFailure`
(`opfs_drive_file_uploader_web.dart:120-128`) rewraps every non-`DioException` as
`DioExceptionType.unknown`, so a naive "let it pass through" would erase it.

Resolution: **the app-side resolver closure is the boundary.** The closure that
`ComposerController` injects (wiring PR) catches `RefreshTokenFailedException`
itself, calls `handleRefreshTokenFailedException()`
(`lib/features/base/base_controller.dart:291`), and then returns
`AuthHeaderUnavailable` to `workplace`. The uploader treats that as "abort without
sending" and fails the chip through the ordinary `DioException` path. No app
exception type ever enters `workplace`, and the draft-save handler still fires.

This is a correction to ADR-0105, which says the resolver "rethrows" and the
uploader propagates — not implementable across this package boundary.

### 401 detection and its known limit

`OpfsXhrUpload` maps non-2xx to `DioException.badResponse` carrying `statusCode`
(`opfs_xhr_upload.dart:167-176`), so the uploader branches on
`DioExceptionType.badResponse` + `response?.statusCode == 401`. Verify the status
survives `_parseUploadResponse` / `_asDioFailure` re-wrapping — branch before
`_asDioFailure` runs.

**Known limit — status 0.** A cross-origin 401 without
`Access-Control-Allow-Origin` reaches `onerror` with `status == 0`, mapping to
`connectionError` (`opfs_xhr_upload.dart:98-103`), and the retry does not fire.
Not fixable client-side; confirmed empirically in Phase 4.

### Cancellation across attempts

`CancelToken.whenCancel` is a single Future with no removal, so per-attempt
listener registration needs care: an attempt starting on an already-cancelled
token must be stopped by the explicit `_throwIfCancelled` guards, not by a
listener that fires only on transition. Keep the existing per-attempt
subscribe/`finally`-release shape (`:69-75`, `:87-90`) and rely on the guards for
the already-cancelled case.

## Related Code Files

Modify:
- `workplace/lib/data/datasource/drive_transfer/opfs_drive_file_uploader_web.dart`
  — the retry policy. (`XhrUploadFileRequest.authHeader` already became `String?`
  and `OpfsXhrUpload` already skips the header when absent, both in Phase 2 — this
  phase adds no transport change.)
- `workplace/test/data/datasource/drive_transfer/opfs_drive_file_uploader_test.dart`
- `workplace/test/data/datasource/drive_transfer/opfs_xhr_upload_test.dart`

Unchanged: `drive_transfer_strategy.dart`'s `transfer()` and its `finally`
disposal — the retry is strictly inside `upload()`.

## Implementation Steps

1. Extract the current body of `upload()` into `_attempt({required bool
   forceRefresh})` that resolves the header, handles the three `AuthHeaderResult`
   cases, sends, and returns the parsed response — also returning (or recording)
   the header it actually sent. Keep the `cancelSubscription` / `whenCancel`
   bookkeeping and its `finally` cleanup per attempt.
2. Add the retry policy in `upload()`: catch a `badResponse` 401 once, re-check
   cancellation, then `_attempt(forceRefresh: false)`; if that resolves to the same
   header that just 401'd, `_attempt(forceRefresh: true)` instead.
4. Keep `_parseUploadResponse`'s `badResponse` classification, `_asDioFailure`'s
   `unknown` fallback, and the final `_throwIfCancelled`.
5. Keep `getFile` inside the existing `try`.
6. `flutter analyze`; run the drive-transfer suite **on Chrome** (see Phase 2 —
   `flutter test workplace/` skips these files).

## Success Criteria

- [ ] Header resolved once per attempt — asserted on the stub, not inferred from
      the result.
- [ ] **Two uploads 401 five seconds apart → exactly one `refreshingTokensOIDC`.**
      The second sees a changed header from `forceRefresh: false` and does not
      force. This is the staggered case the memo alone does not cover.
- [ ] When the header is unchanged after `forceRefresh: false`, the retry does
      call `forceRefresh: true`.
- [ ] 401 → refresh → success returns the parsed `Attachment`, sends twice, second
      send carries the new header.
- [ ] Two consecutive 401s fail the file; the transport is invoked exactly twice.
- [ ] `AuthHeaderUnavailable` on either attempt → **no send at all** for that
      attempt, and the transfer fails.
- [ ] `AuthHeaderNone` → send proceeds with no `Authorization` header.
- [ ] Cancel between attempts → `DioExceptionType.cancel`, no second send.
- [ ] Cancel on an already-cancelled token before attempt 1 → no send.
- [ ] Charset sniffing still works on the retried path (text/plain fixture).
- [ ] Staged file disposed exactly once, after the final attempt.
- [ ] A `getFile` failure still surfaces as `DioExceptionType.unknown`
      (contract preserved).

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Retry loop on a broken server | Local flag; two-401s test asserting exactly two sends |
| Unauthenticated re-send after mid-transfer logout | `AuthHeaderUnavailable` aborts before send; dedicated test |
| Cancel during the refresh gap read as an auth failure | Explicit `_throwIfCancelled` before attempt 2 |
| Already-cancelled token slipping past a transition-only listener | Guards, not listeners, handle that case |
| Hoisting `getFile` breaking the all-failures-are-DioException contract | Explicitly kept inside the `try`, with a test |
| Progress restarts at 0 on the retried attempt | Out of this phase's reach — the consumer must clamp. **Handed to the wiring PR (Phase 4); Phase 3 must not be called done-and-shippable without it** |
| 401 hidden as `status == 0` by CORS | Documented; verified empirically in Phase 4 |
| **Refresh stampede from staggered 401s** — N files, N forced refreshes, possible reuse-detection revocation | Re-resolve with `forceRefresh: false` first and force only on an unchanged header, mirroring `validateToRetryTheRequestWithNewToken`; staggered-401 test |

## Security Considerations

- The resolved header lives in a local for one send and is never logged. Existing
  log calls in this file interpolate `request.fileName` (`:73`) and a bare error
  (`:139`) — neither touches the header. Keep it that way.
- The abort-on-`AuthHeaderUnavailable` rule is a security control, not an
  ergonomic one: it prevents a dead session from degrading into an
  unauthenticated upload of user data to a server-supplied URL.

## Red team changes (2026-08-14)

Applied: `AuthHeaderUnavailable` abort path; `RefreshTokenFailedException`
boundary moved to the app-side resolver closure (ADR correction); `getFile` kept
inside the `try`; already-cancelled-token case separated from listener
registration; full-re-upload cost stated; Chrome test-runner note. Effort raised
0.5-1d → 1d.
