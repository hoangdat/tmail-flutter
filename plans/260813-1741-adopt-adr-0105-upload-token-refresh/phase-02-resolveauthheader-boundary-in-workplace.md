---
phase: 2
title: "ResolveAuthHeader boundary in workplace"
status: pending
priority: P1
effort: "0.5d"
dependencies: [1]
---

# Phase 2: ResolveAuthHeader boundary in workplace

## Overview

Replace the eagerly-resolved `String authHeader` on the drive-transfer request
types with an injected function, so the header can be resolved (and refreshed) at
send time. `workplace` cannot depend on the main app, so the refresher crosses the
boundary the same way `StagedFileUploader` already does — as a typedef.

Mechanical but wide: 13 production sites across 5 files and 5 test files.

## Requirements

Functional:
- `ResolveAuthHeader` replaces `String authHeader` on `DriveTransferRequest`,
  `DriveUploadRequest` and `OpfsUploadRequest` — **three** classes, not four.
- `XhrUploadFileRequest.authHeader` becomes `String?` (an already-resolved header),
  **in this phase**. `OpfsXhrUpload.uploadFile` is synchronous by contract — it
  returns an `XhrUploadHandle`, not a Future (`opfs_xhr_upload.dart:59`) — so it
  cannot await a resolver, and `_applyHeaders` (`:131`) is synchronous too. The
  uploader resolves and passes a plain header down from day one; Phase 3 adds only
  the retry policy on top. Without this split, Phase 2 cannot compile standalone
  and its "clean analyze" completion signal is unreachable.
- Nothing in `workplace` learns about tokens, sessions, or logout — the only thing
  crossing the boundary is a `Future<AuthHeaderResult>`.
- Strategies that authenticate through Dio (buffered web, IO) are unaffected.

Non-functional:
- No new package dependency in `workplace` (no `get`, no app import).

## Architecture

```dart
// workplace/lib/data/model/workplace_type_defs.dart — alongside StagedFileUploader
typedef ResolveAuthHeader = Future<AuthHeaderResult> Function({bool forceRefresh});
```

**Not `Future<String?>`.** A bare nullable string cannot distinguish "no auth
configured" from "the session just died", and Phase 3 must abort on the second
rather than send a drive file unauthenticated. `AuthHeaderResult` is a sealed type
declared in `workplace` (so the package owns its own boundary vocabulary and needs
no app import) with three variants — `AuthHeaderAvailable(header)`,
`AuthHeaderNone`, `AuthHeaderUnavailable`. See Phase 1, "Return type".

Threaded unchanged through `DriveTransferStrategy.transfer` →
`DriveUploadRequest` → `OpfsUploadRequest` → `XhrUploadFileRequest`, and invoked
only in the OPFS uploader (Phase 3). The buffered strategy keeps ignoring it,
with its existing comment updated
(`buffered_web_drive_file_stager.dart:84` currently explains the `String` field).

`AuthHeaderNone` means "send no Authorization header" — a legitimate
unauthenticated backend, not an error. `AuthHeaderUnavailable` means the session
died mid-transfer and Phase 3 must **not** send. State both on the typedef.

## Related Code Files

Modify — production (13 `authHeader` sites across 5 files, enumerated):
- `workplace/lib/data/model/workplace_type_defs.dart` — add the typedef
- `workplace/lib/data/datasource/drive_transfer/drive_transfer_strategy.dart:28,67,76,91,99`
- `workplace/lib/data/datasource/drive_transfer/opfs_drive_transfer_strategy.dart:47`
- `workplace/lib/data/datasource/drive_transfer/opfs_drive_file_uploader.dart:23,32`
- `workplace/lib/data/datasource/drive_transfer/opfs_drive_file_uploader_web.dart:63`
- `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart:26,33,131`
- `workplace/lib/data/datasource/drive_transfer/buffered_web_drive_file_stager.dart:84`
  (doc comment only)

Modify — tests (5 files; all construct or assert on `authHeader`):
- `workplace/test/data/datasource/drive_transfer/drive_transfer_strategy_test.dart`
  (incl. an assertion that the field is forwarded verbatim — becomes "the same
  function instance is forwarded")
- `workplace/test/data/datasource/drive_transfer/opfs_drive_file_uploader_test.dart`
- `workplace/test/data/datasource/drive_transfer/opfs_xhr_upload_test.dart`
- `workplace/test/data/datasource/drive_transfer/opfs_drive_file_stager_test.dart`
- `workplace/test/data/datasource/drive_transfer/buffered_web_drive_file_stager_test.dart`

The last two only *construct* `DriveTransferRequest` as fixture setup — they are
otherwise untouched, but they will not compile until updated — a detail easy to
miss, since neither test exercises auth.

## Implementation Steps

1. Add `ResolveAuthHeader` to `workplace_type_defs.dart` next to
   `StagedFileUploader`, together with the sealed `AuthHeaderResult` and its three
   variants, documenting what each means at the send site.
2. Swap the field type on the **three** higher-level request classes, renaming
   `authHeader` → `resolveAuthHeader` so the compiler flags every site rather than
   silently accepting a wrong positional. `XhrUploadFileRequest.authHeader` becomes
   `String?` and keeps its name.
2b. In `BrowserOpfsDriveFileUploader.upload`, resolve once
   (`await request.resolveAuthHeader(forceRefresh: false)`) and pass the result
   into `XhrUploadFileRequest`. This is the minimum that makes the phase compile;
   the retry policy is Phase 3.
3. Update the buffered strategy's comment: the function is unused there for the
   same reason the string was — that path authenticates through Dio interceptors.
4. Update the 5 test files: replace literal header strings with a stub function
   (`({bool forceRefresh = false}) async => AuthHeaderAvailable('Bearer test')`),
   and record calls where the test asserts on forwarding.
5. `flutter analyze` — treat a clean analyze as the completion signal for this
   phase, since it is a type-level change.

**Test-runner caveat.** `flutter test workplace/` **skips** `@TestOn('chrome')`
files, which is 3 of the 5 above (`opfs_drive_file_uploader_test.dart`,
`opfs_xhr_upload_test.dart`, `opfs_drive_file_stager_test.dart`).
`drive_transfer_strategy_test.dart` and `buffered_web_drive_file_stager_test.dart`
are VM tests. Run both:
```
flutter test workplace/
flutter test --platform chrome workplace/test/data/datasource/drive_transfer/
```
Chrome paths are also enumerated in `.github/workflows/analyze-test.yaml:16-25`
(`CHROME_TEST_PATHS`); no new file is added here, so no CI edit is needed in this
phase.

## Success Criteria

- [ ] No `String authHeader` field remains on the three higher-level request
      classes. `XhrUploadFileRequest.authHeader` is `String?` by design — it
      carries an already-resolved header, not a resolver.
- [ ] `flutter analyze` clean; **both** the VM and chrome runs above green.
- [ ] `workplace/pubspec.yaml` gains no dependency.
- [ ] The buffered and IO strategies are behaviourally unchanged (their tests pass
      without logic edits — fixture construction aside).

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Wide mechanical change missing a site | The type change makes every site a compile error; the enumerated list above is the checklist |
| A test stub that silently returns a stale header hides Phase 3 regressions | Phase 3 tests assert on *call timing* and `forceRefresh`, not just the returned value |
| Ambiguity between "no auth" and "dead session" at the XHR | Sealed `AuthHeaderResult` makes it a compile-time distinction; asserted in Phase 3 |
| A green `flutter test workplace/` mistaken for full coverage | Chrome run documented as a separate mandatory command |

## Red team changes (2026-08-14)

Applied: typedef returns `AuthHeaderResult` rather than `String?`; chrome
test-runner caveat added to the steps and success criteria.

## Security Considerations

- The function is a capability handed to `workplace`, narrower than exposing the
  interceptor: it can request a header and nothing else — it cannot read the
  token object, the refresh token, or the session state.
