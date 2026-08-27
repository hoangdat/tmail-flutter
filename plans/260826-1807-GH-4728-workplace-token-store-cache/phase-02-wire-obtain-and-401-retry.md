---
phase: 2
title: "Wire obtain and Expired-token recover"
status: pending
priority: P1
effort: "2h"
dependencies: [1]
---

# Phase 2: Wire obtain and Expired-token recover

## Overview

Extension stops calling `ExchangeDriveTokenInteractor`. `_fetchIntent` obtains a
session, calls `createIntent`, and on Expired/Invalid token (cozy-client
`fetchJSON` match, or HTTP 401) calls `recoverAfterUnauthorized` then retries
`createIntent` once.

## Requirements

- Functional: tap path uses cached session when warm; Expired/Invalid retries
  this call exactly once; a sibling's newer session is not wiped; recover prefers
  refresh over exchange.
- Non-functional: keep `createIntent(... accessToken:)`; no interceptor.

## Architecture

The extension already constructs datasource + repository. Own the store there —
same lifetime as the keepAlive plugin, shared across every composer.

Match [cozy-client `fetchJSON`](https://github.com/linagora/cozy-client/blob/master/packages/cozy-stack-client/src/CozyStackClient.js):
on Expired/Invalid, single-flight refresh, then retry the same JSON call once.
If refresh throws, cozy-client rethrows the **original** request error. We
instead fall back to `token_exchange` inside the store (we still have an OIDC
`id_token`). If that also fails, `_fetchIntent` throws the recover error.

Trigger — `errors.js` plus HTTP 401 (Dio body is often empty):

```
EXPIRED_TOKEN     = /Expired token/
INVALID_TOKEN     = /Invalid JWT token/
INVALID_TOKEN_ALT = /Invalid token/
WWW-Authenticate  access_token_expired → Expired token
WWW-Authenticate  invalid_token        → Invalid token
```

401 is per HTTP call. Each composer retries **its own** `/intents`. Coordination
is data: `recoverAfterUnauthorized(T)` is a cache hit if the store already holds
a different access token.

```
A and B both Expired on token T
  A: recoverAfterUnauthorized(T) -> refresh -> T2, retry /intents
  B: recoverAfterUnauthorized(T) -> T2 (join or cache), retry /intents
```

Do **not** `obtain()` after Expired — that cache-hits T.

## Related Code Files

- Modify: `workplace/lib/presentation/extension/workplace_composer_attachment_extension.dart`
- Delete: `workplace/lib/domain/usecase/exchange_drive_token_interactor.dart`
- Modify: `workplace/lib/domain/state/workplace_intent_state.dart` — remove
  `ExchangingWorkplaceToken`, `ExchangeWorkplaceTokenSuccess`,
  `ExchangeWorkplaceTokenFailure` after grep shows no remaining references.
- Keep: `WorkplaceExchangeTokenException`

## Implementation Steps

1. Construct the store. Do not register anything on `WorkplaceDio`.

   ```dart
   late final _dataSource = WorkplaceDataSourceImpl();
   late final _repository = WorkplaceRepositoryImpl(_dataSource);
   late final WorkplaceTokenStore _tokenStore = InMemoryWorkplaceTokenStore(
     exchange: _repository.exchangeToken,
     refresh: _repository.refreshToken,
   );
   late final _createIntentInteractor = CreateDriveIntentInteractor(_repository);
   ```

2. Replace `_fetchIntent`:

   ```dart
   Future<WorkplaceIntent> _fetchIntent(
     Uri platformUrl, {
     required WorkplaceFilePickerConfigRequest filePickerConfig,
   }) async {
     final oidcToken = oidcTokenGetter();
     if (oidcToken == null) throw WorkplaceExchangeTokenException();

     final session = await _tokenStore.obtain(
       platformUrl: platformUrl,
       oidcIdToken: oidcToken,
     );
     try {
       return await _createIntent(
         platformUrl,
         session.accessToken,
         filePickerConfig: filePickerConfig,
       );
     } catch (e) {
       if (!_isExpiredOrInvalidToken(e)) rethrow;
       final fresh = await _tokenStore.recoverAfterUnauthorized(
         usedAccessToken: session.accessToken,
         platformUrl: platformUrl,
         oidcIdToken: oidcToken,
       );
       return _createIntent(
         platformUrl,
         fresh.accessToken,
         filePickerConfig: filePickerConfig,
       );
     }
   }

   final _expiredToken = RegExp('Expired token');
   final _invalidJwt = RegExp('Invalid JWT token');
   final _invalidToken = RegExp('Invalid token');
   final _wwwExpired = RegExp('access_token_expired');
   final _wwwInvalid = RegExp('invalid_token');

   bool _isExpiredOrInvalidToken(Object error) {
     if (error is! DioException) return false;
     if (error.response?.statusCode == 401) return true;
     final www = error.response?.headers.value('www-authenticate') ?? '';
     if (_wwwExpired.hasMatch(www) || _wwwInvalid.hasMatch(www)) return true;
     return _expiredToken.hasMatch(_dioMessage(error)) ||
         _invalidJwt.hasMatch(_dioMessage(error)) ||
         _invalidToken.hasMatch(_dioMessage(error));
   }
   ```

   `_dioMessage` reads `error.message`, string `response.data`, or JSON
   `message` / `error` fields. One retry only: the second `_createIntent` is not
   wrapped. A second Expired surfaces to the modal.

3. Delete `_exchangeAccessToken` and the exchange interactor field.

4. Grep `ExchangeWorkplaceToken|ExchangingWorkplaceToken|ExchangeDriveTokenInteractor`
   in `workplace/` and `lib/`. Delete unused states. Keep the exception class.

5. `fvm flutter analyze workplace lib` — clean.

## Success Criteria

- [ ] `_fetchIntent` does not call `token_exchange` when the store has a session.
- [ ] First `/intents` Expired/Invalid/401 → `recoverAfterUnauthorized` + one more
      `/intents`. With `canRefresh`, that recover is `access_token` not exchange.
- [ ] If the store already holds a different access token, recover does not HTTP.
- [ ] Second `/intents` Expired → that error surfaces, no third attempt.
- [ ] Non-token createIntent failure still throws (modal toast path unchanged).
- [ ] Null OIDC throws `WorkplaceExchangeTokenException`.
- [ ] `ExchangeDriveTokenInteractor` and unused exchange states are gone.
- [ ] `createIntent` still takes `accessToken`.

## Risk Assessment

- **Unwrap — verified.** `_isExpiredOrInvalidToken` sees the raw `DioException`.
  Chain: datasource `createIntent` (no wrap) →
  `CreateWorkplaceIntentFailure(exception: e)` →
  `_createIntent` `throw failure is FeatureFailure ? failure.exception : ...`
- 401 with empty body: status check is required; cozy-client regexes alone would
  miss it on Dio.
- Dual recover after both see T: one refresh (store single-flight), two `/intents`
  retries. Story 9.
- Leaving `accessToken` on `createIntent` is intentional workaround scope.
