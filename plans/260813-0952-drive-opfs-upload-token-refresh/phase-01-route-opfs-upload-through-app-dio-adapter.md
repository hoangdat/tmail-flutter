---
phase: 1
title: "Route OPFS upload through app Dio adapter"
status: pending
priority: P1
effort: "1-1.5d"
dependencies: []
---

# Phase 1: Route OPFS upload through app Dio adapter

## Overview

Move the OPFS raw-XHR send from a standalone transport into an `HttpClientAdapter`
installed on the app's Dio, and make `BrowserOpfsDriveFileUploader` issue an
ordinary `DioClient.post`. After this phase the upload leg inherits header
injection and 401 -> refresh -> retry from `AuthorizationInterceptors` with no
auth code of its own.

## Requirements

Functional:
- Upload still streams the OPFS `File` off disk (no full-file materialisation in
  the JS heap) and still reports byte progress.
- Cancellation still aborts the in-flight XHR.
- A 401 triggers the interceptor's refresh, and the retry re-sends the same staged
  file with the new bearer token.
- Non-OPFS requests on the app Dio are unaffected.

Non-functional:
- No `package:web` / `dart:js_interop` symbol reachable from an IO (Android/iOS)
  compilation.
- Failure shapes stay `DioException`, as the current drive-transfer contract
  promises.
- No upload timeout is imposed (a cap large enough for a slow multi-hundred-MB
  upload cannot catch a stall; cancellation is the caller's job).

## Architecture

```
DioClient.post(uploadUri, extra: {opfsUploadFile: resolver}, onSendProgress:, cancelToken:)
  |
app Dio
  |- DynamicUrlInterceptors
  |- AuthorizationInterceptors     onRequest: inject bearer
  |                                onError 401: refresh -> _retryRequest -> retryDio.fetch(requestOptions)
  |- Sentry (installed last)
  '- DriveUploadRoutingHttpClientAdapter
        |- extra has opfsUploadFile -> resolve web.File, XHR POST, ResponseBody(status)
        '- otherwise               -> delegate to platform default adapter
```

Why the retry works, verified in source:
- `AuthorizationInterceptors._createRetryDio()` copies `_dio.httpClientAdapter`
  (`lib/features/login/data/network/interceptors/authorization_interceptors.dart:670`),
  so the retry Dio carries the routing adapter too.
- `_retryRequest` only takes its byte-stream-rebuilding branch for
  `FileUploader.uploadAttachmentExtraKey`
  (`authorization_interceptors.dart:645`). Our key differs, so the retry falls to
  `retryDio.fetch(requestOptions)`, preserving `extra`, `headers` and
  `onSendProgress`.
- `data` stays null, so `DioMixin._transformData` returns a null request stream
  (`dio-5.2.0/lib/src/dio_mixin.dart:605`) and the adapter is still invoked.
- The adapter re-invokes the resolver per attempt, so the retry gets a live
  `web.File` rather than a stale snapshot.

**Do not** reuse `FileUploader.uploadAttachmentExtraKey` for this — the retry
would try to rebuild a byte stream via `_getDataUploadRequest` and break the send.

## Related Code Files

Create:
- `workplace/lib/data/datasource/drive_transfer/drive_upload_routing_adapter.dart`
  — conditional-export barrel, mirroring `opfs_file_handle.dart:2`.
- `workplace/lib/data/datasource/drive_transfer/drive_upload_routing_adapter_web.dart`
  — the routing adapter + XHR send.
- `workplace/lib/data/datasource/drive_transfer/drive_upload_routing_adapter_mobile.dart`
  — passthrough that returns the given delegate unchanged; no `package:web`.

Modify:
- `workplace/lib/data/datasource/drive_transfer/opfs_drive_file_uploader_web.dart`
  — post through `DioClient` instead of `DriveUploadTransport`.
- `lib/main/bindings/network/network_bindings.dart` — install the routing adapter.

Delete:
- `workplace/lib/data/datasource/drive_transfer/opfs_xhr_upload.dart` — its XHR
  body moves into the adapter; `XhrUploadHandle` / `DriveUploadTransport` collapse
  into Dio's `CancelToken` + `cancelFuture`.

## Implementation Steps

1. **Adapter skeleton.** `DriveUploadRoutingHttpClientAdapter implements
   HttpClientAdapter`, constructed with a `delegate` (default `HttpClientAdapter()`
   — the platform factory). `close({force})` forwards to the delegate.

2. **Extra contract.** Define in the barrel:
   - `const opfsUploadFileExtraKey = 'drive-upload-opfs-file';`
   - `typedef OpfsUploadFileResolver = Future<web.File> Function();`
   `fetch()` reads `options.extra[opfsUploadFileExtraKey]`; when it is not an
   `OpfsUploadFileResolver`, delegate untouched.

3. **XHR send.** Port from the deleted `opfs_xhr_upload.dart:59-123`, with these
   changes:
   - Headers come from `options.headers` (already carries `Authorization` from the
     interceptor and `Accept: DioClient.jmapHeader` from `DioClient.post`).
     Strip `content-length` before applying — the browser forbids setting it (the
     dio browser adapter does the same, `dio-5.2.0/lib/src/adapters/browser_adapter.dart:49`).
   - Progress: `options.onSendProgress?.call(loaded, lengthComputable ? total : -1)`,
     keeping the existing guard so a throwing consumer callback cannot escape into
     JS and kill the transfer.
   - Cancel: `cancelFuture?.then((_) => xhr.abort())`, guarded with `catchError`.
   - Set no `xhr.timeout`; ignore `options.sendTimeout` / `receiveTimeout`
     deliberately, and say why in a comment.

4. **Response mapping — the crux.** On `onload`, complete with
   `ResponseBody.fromBytes(utf8.encode(xhr.responseText), xhr.status, headers:
   parsed from xhr.getAllResponseHeaders(), statusMessage: xhr.statusText)` for
   **every** status, 401 included. Dio then raises `DioException.badResponse`
   itself (`dio_mixin.dart:592`) and the interceptor's refresh path engages.
   Parse the header block into `Map<String, List<String>>` (split lines on CRLF,
   name on first `:`, values on `,`) so `DefaultTransformer` sees the JSON
   content type and decodes the body.
   - `onerror` -> throw `DioException(type: connectionError, error: e, ...)`,
     spelled out rather than `DioException.connectionError` (which hardcodes
     `error: null` and would drop the browser's own failure — same reason
     `OpfsFetchDownload.openDownload` builds its own).
   - `onabort` -> throw `DioException.requestCancelled`.
   - Synchronous throws from `open`/`setRequestHeader`/`send` route to the same
     connectionError shape.

5. **Mobile stub.** `HttpClientAdapter createDriveUploadRoutingAdapter(
   HttpClientAdapter delegate) => delegate;` plus the same const/typedef surface
   (`typedef OpfsUploadFileResolver = Future<Object> Function();`), so main-app
   code compiles unconditionally.

6. **Uploader rewrite.** `BrowserOpfsDriveFileUploader` takes a `DioClient`
   (workplace already depends on `core`) and replaces the transport call with:
   ```dart
   final json = await _dioClient.post(
     Uri.decodeFull(request.uploadUri.toString()),
     options: Options(
       headers: {
         if (request.mimeType?.isNotEmpty == true)
           HttpHeaders.contentTypeHeader: request.mimeType,
       },
       extra: {opfsUploadFileExtraKey: () => _store.getFile(request.fileHandle)},
     ),
     cancelToken: request.cancelToken,
     onSendProgress: request.onUploadProgress,
   );
   ```
   Keep unchanged: the explicit content type (an OPFS-created `File` carries an
   empty type), the parallel charset sniff, `_parseUploadResponse`'s
   `badResponse` classification, `_asDioFailure`'s `unknown` fallback, and
   `_throwIfCancelled` so a cancel reads as a cancel however it surfaced. Drop the
   now-dead `whenCancel`/`activeUpload` bookkeeping — Dio's `CancelToken` owns
   abort. `Accept` no longer needs setting by hand; `DioClient.post` adds it.

7. **Binding.** In `NetworkBindings._bindingInterceptors`, after the interceptors
   and **before** `SentryDioHelper.addIfAvailable(dio)`:
   ```dart
   dio.httpClientAdapter =
       createDriveUploadRoutingAdapter(dio.httpClientAdapter);
   ```
   Ordering matters only in that Sentry must wrap the final adapter, not be
   wrapped away by it.

8. **Compile both targets.** `flutter analyze`, then confirm the IO build does not
   pull web symbols (`flutter build apk --debug` or at minimum an analyze with the
   mobile branch selected).

## Success Criteria

- [ ] `opfs_xhr_upload.dart` deleted; no `DriveUploadTransport` references remain.
- [ ] OPFS upload issues one `DioClient.post`; the bearer header is supplied by
      `AuthorizationInterceptors.onRequest`, never by drive-transfer code.
- [ ] A scripted 401 followed by a successful refresh re-sends the staged file with
      the new token and returns the parsed `Attachment` (test lands in Phase 3).
- [ ] Non-OPFS requests are byte-identical to before (delegate untouched).
- [ ] `flutter analyze` clean; Android/iOS build unaffected by web-only imports.

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Adapter throwing on non-2xx would silently kill the whole refresh path — the bug looks like "auth just doesn't work" | Explicit test asserting the adapter *returns* a 401 `ResponseBody` rather than throwing |
| Retry rebuilds the body from the wrong extra key | Never use `FileUploader.uploadAttachmentExtraKey`; assert the retry path in test |
| Stale `web.File` on retry | Resolver closure re-opens `getFile(handle)` per attempt |
| Sentry adapter wrapping order | Install routing adapter before `SentryDioHelper.addIfAvailable` |
| `dart:html` (dio's default adapter) vs `package:web` (ours) coexisting | Both compile under dart2js; dio 5.2.0 already blocks wasm, so no new constraint is introduced |
| Losing the deliberate "no upload timeout" property by inheriting Dio options | App `BaseOptions` sets no timeouts today (`network_bindings.dart:60`); adapter ignores them regardless, documented in a comment |

## Security Considerations

- Token never leaves the interceptor: drive-transfer code stops carrying an
  `authHeader` string entirely (`DriveTransferRequest.authHeader` /
  `DriveUploadRequest.authHeader` become dead for the OPFS path — remove them if no
  other strategy needs them, they were documented as OPFS-only).
- Upload target is the JMAP upload URI only; the download leg keeps sending no
  credentials, so a drive link cannot be turned into a token carrier.
