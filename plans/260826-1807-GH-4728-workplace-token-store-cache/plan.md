---
title: 'Workplace token exchange: TokenStore cache, 401 retry, composer-open prime'
description: >-
  Workaround: one in-memory WorkplaceTokenStore caches the Drive OAuth session
  with no TTL. Prime at composer open. On Expired/Invalid token from POST
  /intents (cozy-client fetchJSON), refresh via POST /auth/access_token then
  retry once; fall back to token_exchange if refresh cannot run.
status: pending
priority: P2
issue: 4728
branch: feature/TF-4728-file-picker-jmap-implementation
tags:
  - workplace
  - drive-picker
  - auth
  - workaround
blockedBy: []
blocks: []
created: '2026-08-26T11:08:39.010Z'
createdBy: 'ck:plan'
source: skill
---

# Workplace token exchange: TokenStore cache, 401 retry, composer-open prime

## Overview

Today every Drive picker tap pays two sequential round-trips inside lazy
`intentLoader()` before the iframe starts:

```
POST {platform}/auth/token_exchange  -> access_token
POST {platform}/intents              -> intent URL (Bearer access_token)
```

The exchanged token is discarded. This plan caches the OAuth session in memory,
primes at composer open, and on Expired/Invalid token from `/intents` refreshes
like cozy-client `fetchJSON` — **no `expires_in` / `expiresAt` clock**. Still a
workaround, not disk persistence or a Dio interceptor.

**Do not implement together with**
`plans/260826-1717-GH-4728-workplace-token-exchange-interceptor-cache`
(interceptor-owned cache). Same files, opposite shape. Pick one.

## Visual summary

Preview this file: the diagrams below are the whole plan.

### Architecture

```mermaid
flowchart TB
  subgraph app["Twake Mail"]
    CC["ComposerController.onInit"]
    REG["composerAttachmentExtensionRegistryProvider\nkeepAlive: true"]
    EXT["WorkplaceComposerAttachmentExtension\nONE instance for the app"]
    PORT["WorkplaceTokenStore\nabstract port"]
    IMPL["InMemoryWorkplaceTokenStore\n_session _seed _ongoing"]
    REPO["WorkplaceRepository"]
    DS["WorkplaceDataSourceImpl"]
  end

  subgraph drive["Drive / cozy-stack"]
    EX["POST /auth/token_exchange\nOIDC id_token → OAuth client"]
    RF["POST /auth/access_token\ngrant_type=refresh_token"]
    IN["POST /intents\nBearer access_token"]
  end

  CC -->|"read"| REG
  REG -->|"construct once"| EXT
  EXT -->|"prime obtain recover"| PORT
  PORT -.->|"implements"| IMPL
  IMPL -->|"exchange refresh"| REPO
  REPO --> DS
  DS --> EX
  DS --> RF
  DS -->|"Bearer"| IN
  EXT -->|"createIntent"| REPO
```

### Sequence: prime then Drive tap

```mermaid
sequenceDiagram
  actor User
  participant CC as ComposerController
  participant REG as Registry keepAlive
  participant EXT as Workplace plugin
  participant ST as TokenStore
  participant Drive as Drive / cozy-stack

  User->>CC: open composer
  CC->>REG: read provider
  REG->>EXT: construct once
  EXT->>ST: prime()
  ST->>Drive: POST /auth/token_exchange
  Note over ST,Drive: OIDC id_token, exchange_type app
  Drive-->>ST: access + refresh + clientId + clientSecret
  ST-->>EXT: session cached in RAM

  User->>EXT: tap Drive tile
  EXT->>ST: obtain()
  ST-->>EXT: cache hit, no clock
  EXT->>Drive: POST /intents Bearer access
  alt 200 intent URL
    Drive-->>EXT: intent URL
    EXT-->>User: iframe picker
  else Expired / Invalid token or HTTP 401
    Drive-->>EXT: unauthorized
    EXT->>ST: recoverAfterUnauthorized(usedAccessToken)
    alt sibling already recovered
      ST-->>EXT: newer access token
    else canRefresh
      ST->>Drive: POST /auth/access_token
      Note over ST,Drive: grant_type=refresh_token, no Bearer
      Drive-->>ST: new access token
    else no refresh or grant failed
      ST->>Drive: POST /auth/token_exchange
      Drive-->>ST: new OAuth session
    end
    EXT->>Drive: POST /intents once more
    Drive-->>EXT: intent URL
    EXT-->>User: iframe picker
  end
```

### Runtime: inject, tap, recover

No TTL. Cache until Drive says Expired / Invalid / 401.

```mermaid
flowchart TD
  OPEN([User opens composer]) --> ONINIT["ComposerController.onInit"]
  ONINIT --> READ["read registry provider"]
  READ --> FIRST{Plugin already\nconstructed?}
  FIRST -->|"no — first composer"| CTOR["construct Extension"]
  CTOR --> LISTEN["workplaceUri.addListener"]
  CTOR --> PRIME["store.prime()"]
  FIRST -->|"yes — later composers"| SKIP["keepAlive hit\nzero extra HTTP"]
  PRIME --> OBTAIN1["store.obtain()"]
  LISTEN -->|"uri null to non-null"| PRIME

  OBTAIN1 --> SEED1{seed matches\ncached session?}
  SEED1 -->|"yes"| HIT1["return _session"]
  SEED1 -->|"no"| JOIN1{same-seed\n_ongoing?}
  JOIN1 -->|"yes"| WAIT1["join that Future"]
  JOIN1 -->|"no"| EX1["POST /auth/token_exchange"]
  EX1 --> CACHE["write _session\naccess + refresh + clientId + clientSecret"]
  WAIT1 --> CACHE
  HIT1 --> READY([session in RAM])
  CACHE --> READY
  SKIP --> READY

  TAP([User taps Drive]) --> OBTAIN2["store.obtain()"]
  READY --> TAP
  OBTAIN2 --> HIT2["cache hit — no clock"]
  HIT2 --> INTENT["POST /intents Bearer"]
  INTENT --> OK{Expired / Invalid token\nor HTTP 401?}
  OK -->|"no"| IFRAME([intent URL — iframe])
  OK -->|"yes"| REC["store.recoverAfterUnauthorized\nusedAccessToken"]

  REC --> SIB{cache already has\na different access token?}
  SIB -->|"yes — sibling recovered"| HIT3["return T2"]
  SIB -->|"no"| JOIN2{same-seed\n_ongoing?}
  JOIN2 -->|"yes"| WAIT2["join that Future"]
  JOIN2 -->|"no"| CAN{canRefresh?}
  CAN -->|"yes"| RFP["POST /auth/access_token\nform: refresh_token + client_id + client_secret"]
  RFP --> RFOK{refresh OK?}
  RFOK -->|"yes"| CACHE2["write new access\nkeep client id/secret"]
  RFOK -->|"no"| EX2["POST /auth/token_exchange"]
  CAN -->|"no"| EX2
  EX2 --> CACHE2
  WAIT2 --> CACHE2
  HIT3 --> RETRY["POST /intents once more"]
  CACHE2 --> RETRY
  RETRY --> IFRAME
```

### What is not in this plan

```mermaid
flowchart LR
  subgraph inPlan["In scope"]
    A[RAM cache]
    B[prime at plugin construct]
    C[OAuth refresh on Expired]
    D[one retry of /intents]
    E[single-flight per seed]
  end

  subgraph outPlan["Out of scope"]
    F[expires_in / TTL / JWT exp]
    G[Dio interceptor]
    H["GET /?refreshToken AppToken"]
    I[persist across process death]
    J[inject at login]
    K[warmup widget]
  end
```

### Why a TokenStore, not a Dio interceptor

`WorkplaceDio` has one authenticated call (`POST /intents`). `token_exchange` and
`POST /auth/access_token` must stay unauthenticated (credentials in the body).
An interceptor is the N-endpoint tool. Refresh is store logic, matching
[cozy-client `fetchJSON`](https://github.com/linagora/cozy-client/blob/master/packages/cozy-stack-client/src/CozyStackClient.js)
(catch Expired/Invalid → single-flight `refreshToken` → retry once).

State lives in **one** object behind an abstract port. Extension, widgets, mixin,
and `WorkplaceDio` stay dumb.

### Store abstraction

The extension never sees cache fields or HTTP. It only calls this port
(`workplace/lib/domain/repository/workplace_token_store.dart`):

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

| Method | Contract |
|---|---|
| `obtain` | Return a usable session for this `(platformUrl, oidcIdToken)`. Cache hit if seed matches. Else one `token_exchange`. Same-seed concurrent calls share one HTTP Future. |
| `recoverAfterUnauthorized` | Called after `/intents` Expired/Invalid/401 with the **access token that failed**. If cache already holds a **different** access token, return it (sibling recovered). Else refresh grant, else `token_exchange`. Must **not** delegate to `obtain()` (that would return the dead token). |
| `prime` | Fire-and-forget `obtain`. No-op if uri or oidc is null. Swallow errors. |

Impl: `InMemoryWorkplaceTokenStore` in
`workplace/lib/data/network/in_memory_workplace_token_store.dart`.
RAM only. `_session`, `_seed`, `_ongoing`, `_ongoingSeed` stay private on the
impl. HTTP is injected:

```dart
typedef WorkplaceTokenExchange = Future<WorkplaceTokenSession> Function(
  Uri platformUrl,
  String oidcIdToken,
);

typedef WorkplaceTokenRefresh = Future<WorkplaceTokenSession> Function(
  Uri platformUrl,
  WorkplaceTokenSession current,
);

class InMemoryWorkplaceTokenStore implements WorkplaceTokenStore {
  InMemoryWorkplaceTokenStore({
    required WorkplaceTokenExchange exchange,
    required WorkplaceTokenRefresh refresh,
  });
}
```

Plugin field type is the **abstract** store:

```dart
late final WorkplaceTokenStore _tokenStore = InMemoryWorkplaceTokenStore(
  exchange: _repository.exchangeToken,
  refresh: _repository.refreshToken,
);
```

### Target flow

```
Composer open (first ComposerController.onInit)
  -> read registry provider -> construct plugin -> store.prime()

later composers onInit
  -> read keepAlive registry -> constructor does not run again

workplaceUri null -> non-null
  -> extension listener -> store.prime()

Tap Drive
  -> store.obtain()                                // cache hit, no TTL
  -> POST /intents

Expired / Invalid token on /intents (cozy-client match, or HTTP 401)
  -> store.recoverAfterUnauthorized(the access token that failed)
       // sibling already minted T2 → return T2
       // else POST /auth/access_token (refresh grant)
       // else POST /auth/token_exchange
  -> POST /intents once more
```

### Key decisions

| Decision | Choice | Why |
|---|---|---|
| Cache owner | Abstract `WorkplaceTokenStore`; impl `InMemoryWorkplaceTokenStore` | Extension depends on the port. Only the impl holds RAM + single-flight. |
| Session shape | `accessToken` + `refreshToken?` + `clientId?` + `clientSecret?` | token_exchange already returns all four. Refresh grant needs client id/secret. **No `expiresAt`.** |
| Expiry | **None.** Trust Drive. | cozy-stack omits `expires_in`. Guessing TTL causes extra exchanges or stale taps. cozy-client does not clock tokens; it refreshes when the stack says Expired/Invalid. |
| Recover trigger | cozy-client `fetchJSON` match + HTTP 401 | `Expired token` / `Invalid JWT token` / `Invalid token` in body or `WWW-Authenticate` (`access_token_expired` / `invalid_token`). Also status 401 (Dio body is often empty). |
| Recover action | `recoverAfterUnauthorized` then retry `/intents` once | Mirror cozy-client: refresh then retry the **same** call once. `_createIntent` unwraps to raw `DioException` (verified). |
| Refresh HTTP | `POST /auth/access_token` form | OAuth client from token_exchange, not AppToken `GET /?refreshToken` (that needs cookies). Fallback: `token_exchange` if refresh credentials missing or the grant fails. |
| Dual recover | used-access compare + **same-seed single-flight** | If cache already holds a different access token, return it. Same-seed callers **join** `_ongoing`. Write cache only if `identical(_ongoing, started)`. |
| Prime time | **Plugin construct** + uri `null → non-null` | Prime in the keepAlive extension constructor, not a per-composer widget. Force-create the plugin from `ComposerController.onInit` so native is not stuck waiting for attach-menu. Do **not** inject at login. |
| Multi-composer | **One store for the app** | Drive token is account-scoped, not composer-scoped. See below. |
| Signatures | Keep `createIntent(... accessToken:)` | Workaround. Do not strip the token through 4 layers. |
| Persistence | Out of scope | RAM only. Process death → next composer open exchanges again. |

### Multiple composers

Web can keep several composers at once (`ComposerManager.composers` is an
`RxMap<String, ComposerView>`, each with a tagged `ComposerController`).

The Drive token is **not** per composer. It is minted from the current OIDC
`id_token` + platform URL. Those are account-level
(`AuthorizationInterceptors.currentOidcIdToken`, one FQDN notifier).

`composerAttachmentExtensionRegistryProvider` is `@Riverpod(keepAlive: true)` and
builds **one** `WorkplaceComposerAttachmentExtension` for the app. Every
composer's toolbar calls `buildToolbarButton(composerId: thatId)` on that same
plugin. Per-composer data is only attachment remaining-bytes and pick dispatch.

So the store **must** be a field on that single extension (or injected into it),
never on `ComposerController` / picker State.

| Scenario | What happens |
|---|---|
| Composer A opens, then B | A's `onInit` constructs the plugin (one exchange). B's `onInit` only `read`s keepAlive. Cache hit. |
| 8 composers open in the same tick (story 8) | First `onInit` constructs + primes. The other seven `read` the same instance. Still **one** `token_exchange`. |
| A and B tap Drive together, cache warm | Two `/intents`, zero exchanges. |
| A and B tap together, cache empty | First `obtain()` starts **one** `token_exchange`. The other joins. |
| A and B `/intents` both Expired/Invalid on T | Each `recoverAfterUnauthorized(T)`. One refresh (or exchange if no grant); joiners reuse T2. Each retries **its own** `/intents`. |
| All recovers see T still cached (story 9) | N `recoverAfterUnauthorized(T)`. Still **one** refresh HTTP. |
| A closes, B stays | Store is on the keepAlive plugin, not on A's controller. Token stays. Do **not** invalidate on composer close. |
| Account switch / OIDC refresh | `oidcIdToken` seed changes. Next `obtain()` misses cache and exchanges. No logout hook. |
| Per-composer store | Reject. N composers = N exchanges for the same account token. |

Stampede (stories 8–9): same-seed callers **join** one mint (`token_exchange` or
`access_token` refresh). A failed mint errors every joiner; the next tap starts
clean. Each composer still retries **its own** `/intents` after Expired/Invalid.

```mermaid
sequenceDiagram
    autonumber
    participant A as Composer A
    participant B as Composer B
    participant C as Composer C
    participant S as TokenStore
    participant D as Drive

    Note over S: cache holds T, all /intents Expired or Invalid

    A->>S: recoverAfterUnauthorized T
    S->>D: POST /auth/access_token
    B->>S: recoverAfterUnauthorized T
    C->>S: recoverAfterUnauthorized T
    Note over B,C: join, do not start HTTP
    D-->>S: session T2
    S-->>A: T2
    S-->>B: T2
    S-->>C: T2
```


### User flows: app open to Drive tap

App open never calls Drive `token_exchange`. The OIDC `id_token` already exists
from login. Drive exchange starts at composer open (target) or Drive tap (today).

#### 1. App open — same on mobile and web

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App
    participant OIDC as OIDC login
    participant Mail as Mailbox dashboard
    participant Drive as Drive platform

    User->>App: launch
    App->>OIDC: restore or login
    OIDC-->>App: id_token in AuthorizationInterceptors
    App->>Mail: show mailbox
    Note over Drive: no token_exchange
```

#### 2. Today — exchange only when the user taps Drive

Web desktop mounts the Drive toolbar button at composer open (`BottomBarComposerWidget`
→ `ExternalAttachmentComposerButton` → `DriveAttachmentPickerButton`). Native
mobile does not: Drive is a tile built inside `attachFileAction`. Neither path
exchanges until tap.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant UI as Composer UI
    participant Ext as Workplace plugin
    participant Dio as WorkplaceDio
    participant Drive as Drive platform

    User->>UI: open composer
    alt Web desktop
        UI->>Ext: watch registry, mount Drive toolbar button
        Note over Ext: button exists, no HTTP
    else Native mobile
        UI->>UI: ComposerView app bar only
        Note over Ext: plugin not even watched yet
    end

    alt Native mobile only
        User->>UI: tap attach
        UI->>Ext: buildContextMenuTile, mount Drive tile
        Note over Ext: still no HTTP
    end

    User->>UI: tap Drive
    UI->>Ext: intentLoader / _fetchIntent
    Ext->>Dio: POST /auth/token_exchange
    Dio->>Drive: exchange OIDC id_token
    Drive-->>Ext: access_token discarded after this call
    Ext->>Dio: POST /intents Bearer
    Drive-->>UI: intent URL, iframe loads
```

#### 3. Target — TokenStore primes when the plugin is constructed

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Ctrl as ComposerController
    participant Ext as Workplace plugin
    participant Store as TokenStore
    participant Drive as Drive platform

    User->>Ctrl: open composer
    Ctrl->>Ext: onInit read registry (construct once)
    Ext-)Store: constructor prime
    Store->>Drive: POST /auth/token_exchange
    Drive-->>Store: session cached access + refresh + client id/secret

    alt Native mobile
        User->>Ctrl: tap attach then Drive
    else Web desktop
        User->>Ctrl: tap Drive toolbar button
    end

    Ctrl->>Store: obtain
    Store-->>Ctrl: cached access_token
    Ctrl->>Drive: POST /intents Bearer
    Drive-->>Ctrl: intent URL, iframe loads

    opt Second composer or second tap, same account
        Store-->>Ctrl: cache hit, no token_exchange
    end

    opt POST /intents Expired token / Invalid token / 401
        Ctrl->>Store: recoverAfterUnauthorized used access token
        Note over Store: one refresh grant, or exchange if refresh cannot run
        Ctrl->>Drive: POST /intents once more
    end
```

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Token session and store](./phase-01-token-session-and-store.md) | Pending |
| 2 | [Wire obtain and 401 retry](./phase-02-wire-obtain-and-401-retry.md) | Pending |
| 3 | [Prime at composer open](./phase-03-prime-at-composer-open.md) | Pending |
| 4 | [Tests](./phase-04-tests.md) | Pending |
| 5 | [Record the decision in ADR 0106](./phase-05-record-the-decision-in-adr-0106.md) | Pending |

## Success criteria

- [ ] Second picker open (same account) issues **no** `token_exchange`.
- [ ] First picker open after composer open issues **no** exchange at tap time (prime already did it), including native mobile.
- [ ] Two composers open: still **one** cached session object (account-scoped).
- [ ] N concurrent `obtain()` / `prime()` while the cache is empty issue **one** `token_exchange`.
- [ ] Closing composer A does not drop the session used by composer B.
- [ ] 401 / Expired / Invalid on `POST /intents` calls `recoverAfterUnauthorized` and retries **once**. Extra composers join the same refresh (or exchange). Each retries their own `/intents`.
- [ ] Recover with a live refresh grant issues **no** `token_exchange`.
- [ ] Recover with no refresh credentials, or a failed grant, issues **one** `token_exchange`.
- [ ] Seed change (OIDC token or platform URL) forces a new exchange.
- [ ] Cached session is reused until Drive rejects it. **No TTL / `expiresAt` / `expires_in`.**
- [ ] First `ComposerController.onInit` constructs the plugin and primes (native included, no attach menu).
- [ ] Second composer `onInit` issues **zero** extra `token_exchange`.
- [ ] Composer open while `workplaceUri` is null, then uri becomes non-null: one `prime` / exchange before tap.
- [ ] No warmup widget / `onComposerOpened` on the plugin interface.
- [ ] `fvm flutter test` green in `workplace/` and touched `lib/` tests.

## Out of scope

- Dio interceptor / dropping `accessToken` from `createIntent`.
- AppToken `GET /?refreshToken` (cookie session). We are an OAuth client from `token_exchange`.
- Persisting the Drive session across process death.
- Re-prime timer / JWT `exp` decode / `expires_in` guess.
- `force` flags or generation counters to pair two composers' `/intents` retries.
- Download path (signed `downloadLink`, not this token).

## Dependencies

Competing alternative (do not merge both):
`plans/260826-1717-GH-4728-workplace-token-exchange-interceptor-cache`

No `blockedBy` / `blocks`: they are mutually exclusive, not sequential.

## Unresolved questions

None that block this workaround.

### Resolved: `expires_in` — do not use it

cozy-stack `AccessTokenReponse` has no `expires_in`. Do not invent `expiresAt` or
a 5 min TTL. Cache until Drive returns Expired/Invalid (cozy-client `fetchJSON`).

### Resolved: refresh grant

`token_exchange` mints a normal OAuth client. Refresh is
`POST /auth/access_token` with `grant_type=refresh_token` + `client_id` +
`client_secret` ([OAuthClient.refreshToken](https://github.com/linagora/cozy-client/blob/master/packages/cozy-stack-client/src/OAuthClient.js)).
Not `GET /?refreshToken` (AppToken / cookie). Not a second `token_exchange` unless
the grant cannot run.
