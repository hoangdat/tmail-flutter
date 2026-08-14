---
phase: 3
title: "Tests and verification"
status: pending
priority: P1
effort: "0.5-1d"
dependencies: [1]
---

# Phase 3: Tests and verification

## Overview

Replace the tests that die with `opfs_xhr_upload.dart`, and add the one test that
actually proves the point of this plan: a 401 on the OPFS upload triggers the
interceptor's refresh and the retry re-sends the staged file with the new bearer.

## Requirements

- Adapter behaviour covered at unit level through the existing scripted-XHR seam
  (`createXhr()`, as `opfs_xhr_upload_test.dart` already does).
- One end-to-end-ish test wiring a real `Dio` + real `AuthorizationInterceptors` +
  scripted XHR, since the refresh/retry contract spans all three and no unit test
  can assert it.
- Download-leg suites stay untouched.

## Related Code Files

Create:
- `workplace/test/data/datasource/drive_transfer/drive_upload_routing_adapter_test.dart`
- `workplace/test/data/datasource/drive_transfer/opfs_upload_token_refresh_test.dart`
  (or the equivalent under `test/features/upload/` if it must reach
  `AuthorizationInterceptors`, which lives in the main app package — pick by where
  the interceptor can be constructed without a dependency inversion)

Modify:
- `workplace/test/data/datasource/drive_transfer/opfs_drive_file_uploader_test.dart`
  — retarget from the removed `DriveUploadTransport` to a `DioClient` backed by a
  stub adapter.

Delete:
- `workplace/test/data/datasource/drive_transfer/opfs_xhr_upload_test.dart`
  — its assertions migrate into the adapter test.

Untouched:
- `opfs_drive_file_stager_test.dart`, `opfs_fetch_download_test.dart`,
  `staged_drive_file_test.dart`, `buffered_web_drive_file_stager_test.dart`

## Implementation Steps

1. **Adapter unit tests.**
   - Routing: extra absent -> delegate called, XHR never constructed; extra present
     -> XHR path, delegate never called.
   - Headers: `Authorization` and `Accept` from `options.headers` reach
     `setRequestHeader`; `content-length` is stripped; `Content-Type` passes through.
   - Progress: `lengthComputable: false` reports total `-1`; a throwing
     `onSendProgress` consumer does not fail the upload.
   - Cancel: resolving `cancelFuture` calls `abort()`; the resulting error is
     `DioExceptionType.cancel`.
   - **Non-2xx returns, does not throw**: status 401 yields a `ResponseBody` with
     `statusCode == 401`. Assert explicitly — this is the load-bearing behaviour.
   - Transport failure -> `DioExceptionType.connectionError` carrying the original
     error; synchronous `open`/`send` throws map to the same shape.
   - Response headers parse into `Map<String, List<String>>` well enough that the
     JSON body decodes.
   - Resolver is invoked per `fetch()` call, not cached.

2. **Refresh/retry integration test.** Real `Dio` with `AuthorizationInterceptors`
   (stub `AuthenticationClientBase` returning a new token, stub cache managers) plus
   the routing adapter over a scripted XHR that answers 401 then 200.
   Assert: two XHR sends; the second carries `Bearer <new token>`; the file
   resolver ran twice; the returned `Attachment` is parsed from the 200 body.

3. **Uploader tests retarget.** Keep the existing coverage of charset sniffing,
   `badResponse` on an unparseable body, `unknown` on an OPFS read failure, and
   cancel-before-send; drive them through a stubbed adapter instead of the removed
   transport.

4. **Run the suites.**
   ```
   flutter test workplace/test/data/datasource/drive_transfer/
   flutter test test/features/login/
   flutter analyze
   ```

5. **Manual web check** (needs a real OIDC backend — see `docs/configuration/`):
   `flutter run -d chrome --web-port=2025 --web-browser-flag --disable-web-security`,
   transfer a large drive file, and confirm from the network panel that a token
   expiring mid-transfer produces refresh + retry rather than a failed attachment.

## Success Criteria

- [ ] Adapter test asserts a 401 is *returned*, not thrown.
- [ ] Integration test proves refresh -> retry -> success with the new bearer.
- [ ] No test references `OpfsXhrUpload` / `DriveUploadTransport`.
- [ ] Full `flutter test` green; `flutter analyze` clean.
- [ ] Download-leg suites unchanged (diff shows no edits to those files).

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Interceptor lives in the app package, adapter in `workplace` — the integration test may not have one home | Put it in the app package (`test/features/upload/`) where both are importable; `workplace` is a path dependency of the app |
| Scripted-XHR stubs drifting from real browser semantics (header casing, `getAllResponseHeaders` formatting) | Keep the manual web check in step 5 as the backstop; do not treat unit tests as proof of browser behaviour |
| Test asserting the number of XHR sends is brittle if Dio retries elsewhere | Assert on bearer values carried per attempt rather than call counts alone |

## Unresolved questions

- Where the drive-transfer orchestration calls `ensureTokenFresh()` (Phase 2, step 5)
  depends on the part-3 wiring plan that does not exist yet — Phase 2 can be
  implemented and tested at the interceptor level regardless, but its call site
  lands with that plan.
- Whether `DriveTransferRequest.authHeader` / `DriveUploadRequest.authHeader` should
  be deleted outright in Phase 1 or left until the wiring plan confirms no other
  strategy wants them. They are documented as OPFS-only, so deletion looks safe.
