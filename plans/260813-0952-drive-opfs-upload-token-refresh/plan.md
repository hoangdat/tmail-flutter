---
title: "Drive OPFS upload token refresh parity"
description: "SUPERSEDED by plans/260813-1741-adopt-adr-0105-upload-token-refresh. Planned the HttpClientAdapter route; red team found it unimplementable. Kept for its red-team reports."
status: cancelled
priority: P2
branch: "feat/add_as_attachment"
tags: [drive-transfer, auth, web, opfs]
blockedBy: []
blocks: []
created: "2026-08-13T04:28:54.347Z"
createdBy: "ck:plan"
source: skill
---

# Drive OPFS upload token refresh parity

> **SUPERSEDED — do not implement.** Replaced by
> [`plans/260813-1741-adopt-adr-0105-upload-token-refresh/`](../260813-1741-adopt-adr-0105-upload-token-refresh/plan.md),
> which adopts ADR-0105 (PR #4755) instead.
>
> Why: routing the upload through the app Dio puts its 401 retry inside
> `QueuedInterceptorsWrapper`'s single `_errorQueue`, where `_performRetry` awaits
> the whole retried request — so a multi-hundred-MB re-upload stalls every other
> Dio error in the app. Two further blockers: `BaseOptions`' default
> `Content-Type: application/json` would ride onto every empty-mime OPFS upload,
> and `workplace` has no route to the app's Dio.
>
> The red-team reports in `reports/` remain useful — most findings apply to the
> replacement plan too, and are carried into it.

## Overview

The OPFS drive-transfer path uploads with raw XHR because only XHR can stream an
OPFS-backed `File` off disk while reporting upload progress. That bypasses Dio,
so it gets neither `AuthorizationInterceptors.onRequest` header injection nor its
401 -> refresh -> retry recovery. The code says so itself
(`workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:50`):
*"Not refresh-and-retry safe: the auth header is read once, up front."*

Fix: keep XHR as the transport, but put it **behind** Dio as a request-routing
`HttpClientAdapter`. The upload becomes an ordinary `DioClient.post` whose body
lives in `options.extra`; the adapter recognises it and sends the OPFS `File` via
XHR. Auth then needs no new code — the existing, verified interceptor does header
injection, refresh, forced-logout classification and retry, and the retry is cheap
because the staged file is still in OPFS.

Scope is auth/token handling only. The part-3 drive->composer wiring (factory
injection, upload URI resolution, progress into upload state, composer error
surfacing) is a separate plan.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Route OPFS upload through app Dio adapter](./phase-01-route-opfs-upload-through-app-dio-adapter.md) | Pending |
| 2 | [Preflight token freshness](./phase-02-preflight-token-freshness.md) | Pending |
| 3 | [Tests and verification](./phase-03-tests-and-verification.md) | Pending |

## Key decisions

- **Approach: adapter, not a parallel auth path.** Re-implementing refresh next to
  the interceptor would duplicate an auth state machine that already encodes
  forced-logout classification, per-platform refresh error routing, iOS keychain
  handoff and account-cache persistence — and would risk two concurrent refreshes
  against a one-time-use refresh token.
- **The adapter must not throw on non-2xx.** It returns a `ResponseBody` carrying
  the status so Dio raises `DioException.badResponse` and the interceptor sees the
  401. This single behaviour is what buys the whole refresh path.
- **Phase 2 is separable.** Phase 1 alone is correct; Phase 2 only avoids paying
  for a doomed first upload of a large file.

## Dependencies

- Depends on merged commits `7cbda0dd0` (part-1 interfaces) and `7d7ad0f15`
  (part-2 OPFS stager/uploader). Both on `feat/add_as_attachment`.
- No cross-plan dependencies. No unfinished plan in `plans/` touches
  `workplace/` or the auth layer.
