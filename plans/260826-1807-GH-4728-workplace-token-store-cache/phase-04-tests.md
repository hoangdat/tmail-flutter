---
phase: 4
title: "Tests"
status: pending
priority: P1
effort: "3h"
dependencies: [3]
---

# Phase 4: Tests

## Overview

Cover store semantics (including multi-caller recover), Expired/Invalid retry
wiring, refresh grant, and composer-open prime. No clock, no `Future.delayed`.

## Requirements

- Functional: every Success Criterion in Phases 1–3 has a named test.
- Non-functional: counting `HttpClientAdapter` like
  `workplace_datasource_impl_test.dart` `_MockAdapter`. Do not stub the store
  in the recover integration tests.

## Related Code Files

- Create: `workplace/test/domain/entity/workplace_token_session_test.dart`
- Create: `workplace/test/data/network/in_memory_workplace_token_store_test.dart`
- Modify: `workplace/test/data/workplace_datasource_impl_test.dart`
- Modify: `workplace/test/presentation/extension/workplace_composer_attachment_extension_test.dart`
- Modify: `test/features/composer/presentation/composer_controller` test if one
  already covers `onInit`; otherwise a focused test that `onInit` `read`s the
  registry is enough. No warmup widget test file.

## Implementation Steps

1. **Session**
   - `canRefresh` true only when refresh + client id + client secret are all
     non-empty. False if any is null or `''`.

2. **Datasource**
   - `exchangeToken` maps refresh/client fields onto the session.
   - `refreshToken` POST path ends with `auth/access_token`; body is form
     (`grant_type`, `refresh_token`, `client_id`, `client_secret`); no
     `Authorization` header.
   - Refresh response without `refresh_token` keeps the previous refresh string.
   - `createIntent` still sends `Authorization: Bearer ...`.

3. **Store** (fake exchange + refresh callbacks, counting)

   | Case | Assert |
   |---|---|
   | First obtain | one exchange |
   | Second obtain, same seed | still one |
   | Two obtain, different oidc / platform | two exchanges |
   | `recoverAfterUnauthorized` other access token | session kept, zero HTTP |
   | `recoverAfterUnauthorized` same token, `canRefresh` | one refresh, zero exchange |
   | `recoverAfterUnauthorized` same token, not `canRefresh` | one exchange |
   | Refresh throws | one exchange fallback |
   | Failed exchange then sequential obtain | one new exchange |
   | Concurrent same-seed obtain on a failing exchange | all get that error; **no** automatic second HTTP |
   | `prime` null args | zero HTTP, completes |
   | `prime` exchange throws | completes, no throw |
   | 8 concurrent `obtain` on empty store | **one** exchange, all 8 get the same session |
   | 8 concurrent `recoverAfterUnauthorized(T)` | **one** refresh |
   | Different-seed mint while a flight is in progress | does not join; late old flight does not clobber `_session` |

4. **Extension `_fetchIntent`** (real Dio + counting adapter + real store)

   | Existing test | Becomes |
   |---|---|
   | null OIDC → `StateError` | `WorkplaceExchangeTokenException` |
   | exchange fails | still throws; failure originates in `obtain()` |
   | intent fails after exchange | same |
   | both succeed | same; **two** HTTP on a cold store, **one** (`/intents` only) on a warm store |
   | size forwarding | unchanged |

   Add:
   - warm store: `_fetchIntent` performs zero `token_exchange` and zero refresh.
   - `/intents` 401 once, `canRefresh`: one `access_token`, one retry `/intents`,
     zero extra `token_exchange`; caller gets 200.
   - `/intents` body `Expired token` (or `WWW-Authenticate: access_token_expired`):
     same recover path even if you also assert 401.
   - `/intents` Expired when store already holds a newer token: zero extra HTTP
     besides the retry `/intents`.
   - `/intents` Expired twice: no third `/intents`.
   - 403 / unrelated 400: no recover, no retry.

5. **Plugin construct / controller onInit**
   - Constructing the extension with a non-null uri calls `prime` once.
   - Two `ComposerController.onInit` (or two `read`s of the keepAlive registry)
     still one exchange.
   - Do not add a warmup widget test.

6. **Uri re-prime**
   - Extension with `ValueNotifier<Uri?>(null)`, then set a uri: one `prime` /
     exchange. First `_fetchIntent` after that is `/intents` only.

7. Run `fvm flutter test` in `workplace/`, then the touched `lib/` / `test/`
   files. `./setup_local prod` first if codegen is missing.

## Success Criteria

- [ ] Phases 1–3 success criteria each mapped to a named test.
- [ ] No test for `expiresAt` / TTL / `isExpiring`.
- [ ] `fvm flutter test` green in `workplace/`.
- [ ] Touched app tests green.
- [ ] No test asserts a token value was logged.

## Risk Assessment

- Static `WorkplaceDio.setInstance`: restore in `tearDown` (existing pattern).
- New store per extension instance in tests: share one store when simulating
  two composers.
- Manual check still needed for perceived latency (Network tab: exchange at
  composer open, `/intents` only on tap, refresh only after Expired).
