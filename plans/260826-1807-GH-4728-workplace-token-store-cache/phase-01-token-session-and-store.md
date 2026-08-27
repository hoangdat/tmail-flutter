---
phase: 1
title: "Token session and store"
status: pending
priority: P1
effort: "3h"
dependencies: []
---

# Phase 1: Token session and store

## Overview

Introduce `WorkplaceTokenSession`, abstract `WorkplaceTokenStore` (domain port),
and `InMemoryWorkplaceTokenStore` (RAM + single-flight). The extension depends
only on the port. `obtain()` returns the cached session until Drive rejects it.
`recoverAfterUnauthorized` refreshes via `POST /auth/access_token`, or exchanges
if the grant cannot run.

## Requirements

- Functional: `obtain` cache-hits when seed matches (no TTL). `recoverAfterUnauthorized`
  returns a sibling's newer access token, else one refresh (else one exchange).
  Concurrent same-seed `obtain` / `prime` / recover join that one HTTP Future.
  `prime` swallows errors.
- Non-functional: in-memory only; never log token values; no `expiresAt` /
  `defaultTtl` / `isExpiring`; no `force` / generation counter.

## Architecture

Seed = `(platformUrl, oidcIdToken)`.

Do **not** parse or invent `expires_in`. cozy-stack `AccessTokenReponse` has no
such field. cozy-client does not clock tokens; it refreshes when the stack says
Expired/Invalid ([`fetchJSON`](https://github.com/linagora/cozy-client/blob/master/packages/cozy-stack-client/src/CozyStackClient.js)).

`token_exchange` mints a **normal OAuth client**. Refresh is the OAuth grant, not
AppToken `GET /?refreshToken` (cookies):

```
POST {platform}/auth/access_token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token&refresh_token=...&client_id=...&client_secret=...
```

No `Authorization` header on that call (expired Bearer is useless; credentials
are in the body).

`canRefresh` = refreshToken, clientId, and clientSecret are all non-empty.

`_ongoing` is any mint (exchange **or** refresh). Write `_session` only if
`identical(_ongoing, started)`. Different seed: do not join; start a second HTTP.

`recoverAfterUnauthorized(usedAccessToken)` must **not** call `obtain()` — that
would cache-hit the dead access token.

## Related Code Files

- Create: `workplace/lib/domain/entity/workplace_token_session.dart`
- Create: `workplace/lib/domain/repository/workplace_token_store.dart` (abstract)
- Create: `workplace/lib/data/network/in_memory_workplace_token_store.dart`
- Modify: `workplace/lib/data/datasource/workplace_datasource.dart`
- Modify: `workplace/lib/data/datasource_impl/workplace_datasource_impl.dart`
- Modify: `workplace/lib/domain/repository/workplace_repository.dart`
- Modify: `workplace/lib/data/repository_impl/workplace_repository_impl.dart`
- Modify: `workplace/lib/domain/usecase/exchange_drive_token_interactor.dart`
  (keep compiling: `ExchangeWorkplaceTokenSuccess` still takes `session.accessToken`)
- Do **not** add `expiresIn` to `WorkplaceExchangeTokenResponse`.

## Implementation Steps

1. Session entity:

   ```dart
   class WorkplaceTokenSession {
     final String accessToken;
     final String? refreshToken;
     final String? clientId;
     final String? clientSecret;

     const WorkplaceTokenSession({
       required this.accessToken,
       this.refreshToken,
       this.clientId,
       this.clientSecret,
     });

     bool get canRefresh =>
         refreshToken != null &&
         refreshToken!.isNotEmpty &&
         clientId != null &&
         clientId!.isNotEmpty &&
         clientSecret != null &&
         clientSecret!.isNotEmpty;
   }
   ```

2. `exchangeToken` returns `Future<WorkplaceTokenSession>`:

   ```dart
   final data = WorkplaceExchangeTokenResponse.fromJson(_asJsonMap(response.data));
   return WorkplaceTokenSession(
     accessToken: data.accessToken,
     refreshToken: data.refreshToken,
     clientId: data.clientId,
     clientSecret: data.clientSecret,
   );
   ```

3. Add `refreshToken` on datasource / repository. Form body, no Bearer:

   ```dart
   Future<WorkplaceTokenSession> refreshToken(
     Uri platformUrl,
     WorkplaceTokenSession current,
   ) async {
     if (!current.canRefresh) {
       throw StateError('WorkplaceTokenSession cannot refresh');
     }
     final response = await WorkplaceDio.instance.post(
       platformUrl.replace(
         pathSegments: [
           ...platformUrl.pathSegments.where((s) => s.isNotEmpty),
           'auth',
           'access_token',
         ],
       ).toString(),
       options: Options(
         headers: {
           'Accept': 'application/json',
           'Content-Type': 'application/x-www-form-urlencoded',
         },
       ),
       data: {
         'grant_type': 'refresh_token',
         'refresh_token': current.refreshToken,
         'client_id': current.clientId,
         'client_secret': current.clientSecret,
       },
     );
     final data = WorkplaceExchangeTokenResponse.fromJson(_asJsonMap(response.data));
     return WorkplaceTokenSession(
       accessToken: data.accessToken,
       refreshToken: (data.refreshToken == null || data.refreshToken!.isEmpty)
           ? current.refreshToken
           : data.refreshToken,
       clientId: current.clientId,
       clientSecret: current.clientSecret,
     );
   }
   ```

   Dio sends `Map` as urlencoded when `Content-Type` is
   `application/x-www-form-urlencoded`.

4. Thread session through datasource, repository, repository impl. Adapt
   `ExchangeDriveTokenInteractor` so analyze stays green. Do not delete it yet
   (Phase 2).

5. Store **port** (domain). Extension and tests depend on this type only:

   ```dart
   abstract class WorkplaceTokenStore {
     Future<WorkplaceTokenSession> obtain({
       required Uri platformUrl,
       required String oidcIdToken,
     });

     Future<WorkplaceTokenSession> recoverAfterUnauthorized({
       required String usedAccessToken,
       required Uri platformUrl,
       required String oidcIdToken,
     });

     Future<void> prime({
       Uri? platformUrl,
       String? oidcIdToken,
     });
   }
   ```

6. Store **impl** (data). Cache and `_mint` stay here. No `invalidateIf`.

   ```dart
   typedef WorkplaceTokenExchange =
       Future<WorkplaceTokenSession> Function(Uri platformUrl, String oidcIdToken);
   typedef WorkplaceTokenRefresh =
       Future<WorkplaceTokenSession> Function(
         Uri platformUrl,
         WorkplaceTokenSession current,
       );

   class InMemoryWorkplaceTokenStore implements WorkplaceTokenStore {
     InMemoryWorkplaceTokenStore({
       required WorkplaceTokenExchange exchange,
       required WorkplaceTokenRefresh refresh,
     }) : _exchange = exchange,
          _refresh = refresh;

     final WorkplaceTokenExchange _exchange;
     final WorkplaceTokenRefresh _refresh;
     WorkplaceTokenSession? _session;
     _TokenSeed? _seed;
     Future<WorkplaceTokenSession>? _ongoing;
     _TokenSeed? _ongoingSeed;

     @override
     Future<WorkplaceTokenSession> obtain({
       required Uri platformUrl,
       required String oidcIdToken,
     }) {
       final seed = _TokenSeed(platformUrl, oidcIdToken);
       final cached = _session;
       if (cached != null && seed == _seed) return Future.value(cached);
       return _mint(seed, () => _exchange(platformUrl, oidcIdToken));
     }

     @override
     Future<WorkplaceTokenSession> recoverAfterUnauthorized({
       required String usedAccessToken,
       required Uri platformUrl,
       required String oidcIdToken,
     }) {
       final seed = _TokenSeed(platformUrl, oidcIdToken);
       final cached = _session;
       if (cached != null &&
           seed == _seed &&
           cached.accessToken != usedAccessToken) {
         return Future.value(cached);
       }
       return _mint(seed, () async {
         final current = _session;
         if (current != null && current.canRefresh) {
           try {
             return await _refresh(platformUrl, current);
           } catch (_) {}
         }
         return _exchange(platformUrl, oidcIdToken);
       });
     }

     Future<WorkplaceTokenSession> _mint(
       _TokenSeed seed,
       Future<WorkplaceTokenSession> Function() start,
     ) {
       final ongoing = _ongoing;
       if (ongoing != null && seed == _ongoingSeed) return ongoing;
       late final Future<WorkplaceTokenSession> started;
       started = start().then((session) {
         if (identical(_ongoing, started)) {
           _session = session;
           _seed = seed;
         }
         return session;
       });
       _ongoing = started;
       _ongoingSeed = seed;
       return started.whenComplete(() {
         if (identical(_ongoing, started)) {
           _ongoing = null;
           _ongoingSeed = null;
         }
       });
     }

     @override
     Future<void> prime({Uri? platformUrl, String? oidcIdToken}) async {
       if (platformUrl == null || oidcIdToken == null) return;
       try {
         await obtain(platformUrl: platformUrl, oidcIdToken: oidcIdToken);
       } catch (e) {
         logWarning('InMemoryWorkplaceTokenStore::prime failed: $e');
       }
     }
   }
   ```

7. `./setup_local prod` from repo root. Not a per-package `build_runner build`.

8. `fvm flutter analyze workplace` — must be clean.

## Success Criteria

- [ ] Abstract `WorkplaceTokenStore` has only `obtain`, `recoverAfterUnauthorized`,
      `prime`. Extension field type is the abstract class.
- [ ] `InMemoryWorkplaceTokenStore implements WorkplaceTokenStore`. Cache fields
      are private on the impl.
- [ ] `refreshToken` POST is urlencoded, no Bearer, keeps client id/secret, keeps
      old refresh if the response omits it.
- [ ] Store cache hit issues zero HTTP.
- [ ] Seed change issues a new exchange.
- [ ] No `expiresAt`, `expiresIn`, `defaultTtl`, or `isExpiring` in workplace token code.
- [ ] `recoverAfterUnauthorized` with a newer cached access token issues zero HTTP.
- [ ] `recoverAfterUnauthorized` with `canRefresh` issues one `access_token`, zero
      `token_exchange`.
- [ ] `recoverAfterUnauthorized` without `canRefresh`, or after refresh throw, issues
      one `token_exchange`.
- [ ] `prime` with null uri/oidc is a no-op; failed exchange does not throw.
- [ ] N concurrent same-seed `obtain()` on an empty store issue **one** `token_exchange`.
- [ ] N concurrent `recoverAfterUnauthorized(T)` issue **one** refresh (or one exchange).
- [ ] Concurrent same-seed mint on a failing HTTP all get that error; the next
      sequential call starts one new HTTP.
- [ ] Different-seed mint while a flight is in progress does not join it; a late
      old flight does not clobber `_session`.
- [ ] Analyze clean.

## Risk Assessment

- `_ongoing` is the current mint Future, not a retry coordinator. Each Expired
  `/intents` still retries its own request after recover.
- Refresh then exchange inside the same `_mint` future: joiners wait for both
  legs. Do not start a second recover.
- Failed mint: every joiner sees the same error. Next tap starts one new HTTP.
- Write `_session` only when `identical(_ongoing, started)`.
- Dio Map + urlencoded: pin with a datasource test that the body is form, not JSON.
