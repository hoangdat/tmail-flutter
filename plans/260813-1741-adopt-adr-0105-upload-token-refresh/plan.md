---
title: "Adopt ADR-0105 upload-phase token refresh"
description: "Implement ADR-0105: one shared refresh reachable off-Dio via ensureFreshAuthorizationHeader, injected into workplace as a ResolveAuthHeader function, with late header resolution and retry-once in the OPFS uploader."
status: pending
priority: P1
branch: "feat/add_as_attachment"
tags: [drive-transfer, auth, web, opfs, adr-0105]
blockedBy: []
blocks: []
created: "2026-08-13T14:00:08.306Z"
createdBy: "ck:plan"
source: skill
---

# Adopt ADR-0105 upload-phase token refresh

## Overview

The web+OPFS drive upload leg uploads with raw XHR (the only transport that can
stream an OPFS-backed `File` off disk while reporting progress), so it bypasses
every Dio interceptor. It reads the bearer once at transfer start and cannot
recover from a 401 — its own doc comment says so
(`workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:50`).

ADR-0105 (PR #4755) fixes this without a second refresh implementation: add one
public entry point to the *existing* refresh chain, share a single-flight memo
between the Dio and off-Dio callers, inject it into `workplace` as a plain
function, resolve the header immediately before `xhr.send`, and retry once on a
401.

This plan implements that ADR against `feat/add_as_attachment`, plus the one gap
found reviewing it (the duplicate-token guard, see Key decisions).

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Interceptor refresh gateway](./phase-01-interceptor-refresh-gateway.md) | Pending |
| 2 | [ResolveAuthHeader boundary in workplace](./phase-02-resolveauthheader-boundary-in-workplace.md) | Pending |
| 3 | [OPFS uploader late-resolve and retry-once](./phase-03-opfs-uploader-late-resolve-and-retry-once.md) | Pending |
| 4 | [Tests verification and deferred wiring](./phase-04-tests-verification-and-deferred-wiring.md) | Pending |

## Key decisions

- **ADR-0105 is the design; this plan does not relitigate it.** The alternative
  (routing the XHR through the app Dio behind a custom `HttpClientAdapter`) was
  planned, red-teamed, and rejected — see "Superseded approach" below.
- **G1 — the one ADR gap this plan closes.** ADR-0105 says
  `_refreshTokenThenRetry` is refactored to call the shared memo, but does not
  mention the duplicate-token guard at
  `authorization_interceptors.dart:357`, which sits *before* `_updateNewToken` at
  `:367`. If the memo performs the assignment, a caller that *joins* it resumes
  with `_token` already updated, the guard reads true, and the user is logged out
  after a **successful** refresh. Phase 1 relocates the comparison to a
  pre-refresh snapshot and keeps it out of the joiner path.
- **Header resolution moves to send time.** Today it happens at transfer start,
  before a download that can run for minutes, so the header can be stale even
  when nothing expired. This is a real pre-existing bug the `String authHeader`
  shape hid.
- **Expiry is `TokenOIDC.isExpired`, never `isTokenValid()`.**
  `isTokenValid()` is `token.isNotEmpty && tokenId.uuid.isNotEmpty`
  (`model/lib/oidc/token_oidc.dart:61`) — it has no expiry term. A freshness check
  written against it would never refresh anything.

## Scope boundary

In scope: the auth/token mechanism end to end (interceptor gateway, injection
boundary, uploader behaviour, tests).

Deferred to the drive→composer wiring PR, because the call sites do not exist on
this branch (verified: `DriveTransferPipeline`, `ResolveAuthHeader` and
`updateUploadProgress` all return 0 grep hits under `lib/` and `workplace/`):
- `ComposerController` constructing the resolver closure and handling
  `RefreshTokenFailedException`.
- The monotonic-progress guard. ADR-0105 names
  `UploadController.updateUploadProgress`; that method does not exist. The actual
  mapping is `lib/features/upload/presentation/controller/upload_controller.dart:98`
  and `:154`. Phase 4 records this handoff.

## Superseded approach

`plans/260813-0952-drive-opfs-upload-token-refresh/` planned the adapter route.
Three hostile reviewers found it unimplementable; the decisive findings, all
verified against source:
- Routing the upload through Dio puts its 401 retry inside
  `QueuedInterceptorsWrapper`'s single `_errorQueue`
  (`dio-5.2.0/lib/src/interceptor.dart:364-410`), and `_performRetry` awaits the
  whole retried request before resolving (`authorization_interceptors.dart:456-458`)
  — so a multi-hundred-MB re-upload stalls every other Dio error in the app,
  unbounded. ADR-0105's design never puts the upload in Dio.
- `BaseOptions` carries a default `Content-Type: application/json`
  (`network_bindings.dart:60-64`, `core/lib/data/constants/constant.dart:3`) which
  would ride onto every OPFS upload with an empty mime type — the normal case.
- `workplace` has no `get` dependency and no route to the app's Dio.

Red-team reports are preserved in that plan's `reports/` directory.

## Red Team Review

### Session — 2026-08-14
**Findings:** 16 (14 accepted, 2 rejected)
**Severity breakdown:** 7 Critical, 7 High, 2 Medium
**Reviewers:** Security Adversary, Assumption Destroyer, Failure Mode Analyst —
all three. (The third was interrupted while returning its summary, but had already
written its full 11-finding report to `reports/`; four of its findings were unique
and are #13-16 below.) Reports in `reports/`.

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | Epoch guard useless: `_clearAllData()` wipes Hive before `clear()`, so a refresh resolving in the gap re-persists a live session | Critical | Accept | Phase 1 |
| 2 | Post-logout `null` header → retry sends the file unauthenticated | Critical | Accept | Phases 1-3 |
| 3 | Cross-cutting test unbuildable: interceptor is `dart:io` (VM), uploader is `@TestOn('chrome')` | Critical | Accept | Phase 4 |
| 4 | 17 `.mocks.dart` files break on a new public method, not 1 | Critical | Accept | Phase 1 |
| 5 | `RefreshTokenFailedException` cannot cross into `workplace`; `_asDioFailure` would erase it | Critical | Accept | Phase 3 |
| 6 | `flutter test workplace/` skips every `@TestOn('chrome')` file — success criteria green while testing nothing | High | Accept | Phases 2-4 |
| 7 | Two `AuthorizationInterceptors` instances; memo is per-instance, so single-flight does not span them | High | Accept | Phase 1 |
| 8 | Zero lead time on the freshness check; mid-flight expiry costs a full re-upload | High | Accept | Phase 1 |
| 9 | Epoch only bumped by `clear()`; `setTokenAndAuthorityOidc` swaps identity without it | High | Accept | Phase 1 |
| 10 | `oidc` with null `_configOIDC` is reachable and would poison the shared memo | High | Accept | Phase 1 |
| 11 | `forceRefresh` is an unrate-limited refresh capability exported to a package | Medium | Reject | — |
| 12 | Server-supplied `uploadUrl` origin validation should be in scope | Medium | Reject (noted) | Phase 1 security note |
| 13 | "A rejected refresh clears the session" would log users out on transient failures, undoing four auth commits just shipped on this branch; the two `_handleRefreshError*` methods are handler-bound and unreachable off-Dio | Critical | Accept | Phase 1 |
| 14 | Phases 2 and 3 specify contradictory types for `XhrUploadFileRequest.authHeader`; Phase 2 cannot compile standalone, and `uploadFile` is synchronous so it cannot await a resolver | Critical | Accept | Phases 2-3 |
| 15 | No timeout anywhere in the refresh chain: a hung off-Dio memo holder stalls dio's error queue unbounded — the same failure this plan cites for rejecting the adapter approach, reintroduced via the memo | High | Accept | Phase 1 |
| 16 | The memo only collapses *overlapping* refreshes; staggered 401s from N uploads force N refreshes, risking reuse-detection revocation | High | Accept | Phase 3 |

**Rejection rationale.** #11: the sole caller has a once-flag and the memo
coalesces concurrent calls; adding rate-limiting machinery is speculative (YAGNI).
#12: pre-existing behaviour shared with `FileUploader`, not introduced here — but
the reviewer is right that this design amplifies the exposure (guaranteed-fresh
token, inducible rotation, two full-body sends), so Phase 1's security section now
says so and recommends a separate ticket.

**Held under scrutiny:** the G1 duplicate-token fix. Both reviewers probed it;
neither broke it. Its one real consequence — a joining Dio caller no longer
evaluating the duplicate check, yielding one extra retry and a different Sentry tag
before the same forced logout — is now documented in Phase 1 rather than implicit.

### Corrections this plan makes to ADR-0105

Findings 1, 2, 5, 13, 15 and 16 are gaps in the ADR itself, not in this plan's
reading of it. Together with the `updateUploadProgress` symbol that does not
exist, that is seven items to take back to PR #4755 before it merges:
1. The duplicate-token guard vs. the shared memo (G1).
2. Epoch/teardown ordering — `clear()` alone cannot protect the durable writes.
3. `RefreshTokenFailedException` cannot be rethrown across the `workplace`
   boundary; the app-side resolver closure must absorb it.
4. `UploadController.updateUploadProgress` does not exist
   (`upload_controller.dart:98,154` is the real site).
5. The ADR does not say a *transport* refresh failure must keep the session. Read
   literally it regresses `3dabbbe94` / `aad7df7b3` / `fa12f7198` / `bfde3527a`.
6. The refresh chain has no timeout, so an off-Dio memo holder can stall dio's
   error queue indefinitely.
7. "Single-flight" only dedupes *overlapping* refreshes; the ADR's own motivating
   workload (a batch of large uploads) 401s in a stagger the memo does not cover.
   The uploader needs the `validateToRetryTheRequestWithNewToken` analogue.

### Whole-Plan Consistency Sweep
- Files reread: plan.md, phase-01, phase-02, phase-03, phase-04
- Decision deltas checked: 10
- Reconciled stale references: 4 — `Future<String?>` → `Future<AuthHeaderResult>`
  and "the null contract" → the three-way result (both Phase 2, caught by a
  post-edit grep, not by the rewrite); test commands across Phases 2-4; effort
  estimates in Phases 1 and 3
- Unresolved contradictions: 0
- Second pass after reading the third reviewer's report: the Phase 2/Phase 3 type
  split (#14) resolved a contradiction the first sweep missed entirely — Phase 2
  claimed a completion signal ("clean analyze") it could not reach. Phase 3's
  "Related Code Files" was corrected to stop claiming a transport change that now
  happens in Phase 2.

## Dependencies

- ADR: `docs/adr/0105-upload-phase-token-refresh-for-drive-attachments.md`
  (PR #4755, branch `feature/TF-4728-ADR-OPFS-refresh-token`, status Proposed).
  If the ADR changes before merge, re-check Phases 1-3 against it.
- Builds on merged `7cbda0dd0` (part-1 interfaces) and `7d7ad0f15` (part-2 OPFS
  stager/uploader).
