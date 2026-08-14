---
phase: 4
title: "Tests verification and deferred wiring"
status: pending
priority: P1
effort: "0.5-1d"
dependencies: [1, 2, 3]
---

# Phase 4: Tests verification and deferred wiring

# [RED TEAM REVISED 2026-08-14] — the cross-cutting test as originally specified
# cannot exist on any platform. See "Test topology".

## Overview

Close out the suites, settle the questions the repo cannot answer, and hand the
composer-side items to the wiring PR with exact locations.

## Test topology (the constraint that shapes this phase)

There is **no platform that can host both sides**:
- `AuthorizationInterceptors` imports `dart:io`
  (`lib/features/login/data/network/interceptors/authorization_interceptors.dart:3`,
  `File(filePath!).openRead()` at `:490`) → VM only.
- `BrowserOpfsDriveFileUploader` imports `package:web` / `dart:js_interop`, and its
  suite is `@TestOn('chrome')` → browser only.

So the originally-planned "real interceptor + real uploader in one test" is
impossible. Split it:

| Test | Platform | Proves |
|---|---|---|
| Interceptor suite (Phase 1) | VM | memo single-flight, G1, epoch/logout ordering, `AuthHeaderResult` cases |
| Uploader suite (Phase 3) | Chrome | late resolve, `forceRefresh` on attempt 2, abort on `AuthHeaderUnavailable`, cancel interleavings |
| Contract test (new, this phase) | VM | the resolver closure's shape: expired token → refresh → header; rejection → `handleRefreshTokenFailedException` → `AuthHeaderUnavailable` |

The seam between them is the `ResolveAuthHeader` typedef. The uploader suite
drives it with a fake; the contract test drives the real interceptor through the
same signature. Nothing proves the two halves in one process — accept that and
compensate with the manual browser check, rather than pretending a test covers it.

## CI registration (missed by the previous revision)

Chrome tests are enumerated one path per line in
`.github/workflows/analyze-test.yaml` under `CHROME_TEST_PATHS` (`:16-25`).
`flutter test workplace/` **skips** every `@TestOn('chrome')` file, so a green run
there proves nothing about Phases 2-3.

- Existing registered drive-transfer paths: `drive_transfer_strategy_factory_web_test.dart`,
  `opfs_drive_file_stager_test.dart`, `opfs_drive_file_uploader_test.dart`,
  `opfs_fetch_download_test.dart`, `opfs_xhr_upload_test.dart`.
- **Not** `@TestOn('chrome')` and therefore VM-run: `drive_transfer_strategy_test.dart`,
  `buffered_web_drive_file_stager_test.dart`.
- Any new chrome test file must be added to that list or it never runs in CI.

## Related Code Files

Create:
- `test/features/upload/drive_upload_auth_resolver_contract_test.dart` — VM test
  of the resolver closure against a real `AuthorizationInterceptors` (stub
  `AuthenticationClientBase`, stub cache managers). Imports no `workplace` web
  code; it exercises the typedef's app side only.

Modify:
- `.github/workflows/analyze-test.yaml` — register any new chrome test path.

Covered by their own phases: `test/features/interceptor/authorization_interceptor_test.dart`
(Phase 1), `workplace/test/data/datasource/drive_transfer/*` (Phases 2-3).

## Implementation Steps

1. **Contract test (VM).** Real interceptor + the closure shape
   `ComposerController` will use. Assert: expired token → one refresh → bearer
   returned; `forceRefresh: true` → refresh even when unexpired; refresh rejected
   → `handleRefreshTokenFailedException` invoked → `AuthHeaderUnavailable`
   returned (not thrown across the boundary); session cleared mid-call →
   `AuthHeaderUnavailable`.
2. **Concurrency test (VM, interceptor suite).** Three simulated OPFS callers
   refreshing alongside a Dio 401 **on the same instance**: exactly one
   `refreshingTokensOIDC`, four successful outcomes, zero logouts. Scoped to one
   instance — cross-instance coordination is explicitly out of scope (Phase 1,
   "Instance scope").
2b. **Transient-failure test (VM, interceptor suite).** A `connectionError` and a
   timeout during an off-Dio refresh each keep the session: no `clear()`, no
   `RefreshTokenFailedException`, original error rethrown. This guards the
   behaviour shipped in `3dabbbe94` / `aad7df7b3` / `fa12f7198` / `bfde3527a`
   against the new entry point.
2c. **Queue-stall test (VM).** A refresh that never settles must not block a
   subsequent Dio 401 beyond the timeout, and the next caller must start a fresh
   refresh rather than joining the dead future.
2d. **Staggered-401 test (Chrome, uploader suite).** Two uploads 401 five seconds
   apart → exactly one refresh, because the second re-resolves without forcing and
   sees a changed header. The simultaneous case in step 2 does not cover this.
3. **Full run.**
   ```
   dart run build_runner build --workspace --delete-conflicting-outputs
   flutter analyze
   flutter test                      # full suite — the 17 regenerated mocks
   flutter test --platform chrome workplace/test/data/datasource/drive_transfer/
   ```
   The chrome run is separate and mandatory; the plain run does not execute it.
4. **Manual web check** against a real OIDC backend
   (`flutter run -d chrome --web-port=2025 --web-browser-flag --disable-web-security`).
   Capture two things the repo cannot answer:
   - **The status code** the JMAP upload endpoint returns for an expired/absent
     bearer. Everything keys on 401; a 403 or 400 means the retry never fires and
     `validateToRefreshToken` never triggers on the Dio path either
     (`authorization_interceptors.dart:511`).
   - **Whether that response carries `Access-Control-Allow-Origin`.** Without it a
     cross-origin 401 arrives as `status == 0` and the retry is silently disabled.
   If either answer is unfavourable, **stop and re-open the ADR** — the design's
   trigger condition would be wrong, not just its implementation.
   Blocked until the drive→composer wiring exists; deferred, not skipped.

## Deferred to the drive→composer wiring PR

Verified absent on this branch (0 grep hits under `lib/` and `workplace/`):
`DriveTransferPipeline`, `ResolveAuthHeader` call sites, `updateUploadProgress`.

1. **Resolver construction.** `ComposerController` builds the closure: call
   `ensureFreshAuthorizationHeader`, catch `RefreshTokenFailedException`, call
   `handleRefreshTokenFailedException()` (`lib/features/base/base_controller.dart:291`),
   return `AuthHeaderUnavailable`. Bind to the **main** interceptor instance
   (`Get.find<AuthorizationInterceptors>()`, untagged — not `BindingTag.isolateTag`).
2. **Monotonic progress — blocking, not cosmetic.** ADR-0105 names
   `UploadController.updateUploadProgress`; **that method does not exist**. The
   real mapping is `lib/features/upload/presentation/controller/upload_controller.dart:98`
   and `:154`:
   ```dart
   uploadingProgress: (success.progress * 100 / success.total).floor(),
   ```
   A retried upload restarts `sent` at 0, so without a `max(current, mapped)` clamp
   at both sites the bar snaps backwards mid-transfer. Phase 3 ships the retry that
   causes this, so the clamp must land with the wiring, not later.
3. **The manual web check** (step 4), which needs a runnable drive transfer.

## Success Criteria

- [ ] Contract test covers all four resolver outcomes, including
      `AuthHeaderUnavailable` on rejection and on mid-call clear.
- [ ] Concurrency test: one refresh across four concurrent same-instance callers,
      zero logouts.
- [ ] Transient failures (connectionError, timeout) keep the session.
- [ ] A never-settling refresh does not stall dio's error queue past the timeout.
- [ ] Staggered 401s five seconds apart → exactly one refresh.
- [ ] `flutter analyze` clean; full `flutter test` green **after** mock
      regeneration; the chrome run green.
- [ ] Any new chrome test path is registered in `CHROME_TEST_PATHS`.
- [ ] No test references a `String authHeader`.
- [ ] The two empirical questions are answered and recorded here, or carried into
      the wiring PR as blocking-before-release.

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| No single test proves the two halves together | Acknowledged as a platform constraint, not papered over; the typedef is the seam, the manual check is the backstop |
| A green `flutter test workplace/` read as proof | Chrome run is a separate mandatory command; the skip behaviour is documented here |
| New chrome test never runs in CI | Explicit `CHROME_TEST_PATHS` registration step |
| The whole design keying on a 401 the server may not send | Step 4 is an empirical gate with an explicit "re-open the ADR" branch |
| Deferred items lost at the wiring PR | Exact file:line locations recorded, including the ADR's wrong symbol name |

## Unresolved questions

1. Does the JMAP upload endpoint answer **401** (not 403/400) for an expired or
   absent bearer, and is that response CORS-exposed?
2. Does the lead window (Phase 1) cause a refresh on every upload for tokens built
   via `authentication_token_extension.dart:12`'s `?? DateTime.now()` fallback?
   Needs a real token response to settle.
3. ADR-0105 is still **Proposed**, and this plan now corrects it in three places
   (the duplicate-token guard, the `RefreshTokenFailedException` boundary, and the
   `updateUploadProgress` symbol name). Those corrections should go back to PR
   #4755 before it merges.

## Red team changes (2026-08-14)

Applied: cross-platform test split into VM contract test + chrome uploader suite
(the original single test was unbuildable); `CHROME_TEST_PATHS` registration;
build_runner + full-suite gate; concurrency test scoped to one instance; monotonic
progress reclassified from cosmetic to blocking-with-the-wiring.
