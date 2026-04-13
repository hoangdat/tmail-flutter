# PoC: EmailActionQueue + EventBus + CancellationToken

**Branch:** architecture  
**Date:** 2026-04-08  
**Status:** Complete

## Goal

Unified email action execution with lifecycle flexibility:
- **EmailAction** — typed, self-contained action classes
- **EmailActionQueue** — single `GetxService` (app lifecycle) executes all actions
- **CancellationToken** — controller-scoped; cancels callbacks, NOT the HTTP call
- **AppEventBus** — decouples result propagation; always fires regardless of token
- Old mixin `markAsEmailRead` stays **untouched** (backward compat)

## Architecture Shape

```
Controller.markEmailRead(email)
  └─ EmailActionQueue.submit(MarkAsReadAction(...), token?, onSuccess?)
       └─ action.execute(session, accountId)  ← returns Stream<Either>
            └─ .listen() in queue (app lifecycle, survives controller disposal)
                 ├─ always → AppEventBus.fire(domain state)
                 └─ if !token.isCancelled → onSuccess/onFailure callback

AppEventBus (broadcast)
  ├─ EmailListStateProvider.on<MarkAsEmailReadSuccess>()  ← updates list UI
  └─ Any controller.on<X>() for screen-specific reactions
```

### Lifecycle Flexibility (same API, one parameter difference)

```dart
// Background (survives controller disposal) — no token
_actionQueue.submit(MarkAsReadAction(...));

// Screen-scoped (callbacks cancelled on controller close) — with token
_actionQueue.submit(MarkAsReadAction(...),
  token: _cancelToken,
  onSuccess: (_) => _showSnackbar(),
);
```

## Key Components

| Component | Type | Lifecycle | Responsibility |
|-----------|------|-----------|----------------|
| `EmailAction` | Abstract class | Per-call | Encapsulates stream creation |
| `EmailActionQueue` | GetxService | App | Executes actions, fires bus, respects tokens |
| `CancellationToken` | Plain class | Controller | Prevents callbacks after controller dispose |
| `AppEventBus` | GetxService | App | Typed broadcast event delivery |
| `EmailListStateProvider` | GetxService | App | Subscribes to bus, updates email list UI |

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | [AppEventBus](phase-01-app-event-bus.md) | Done |
| 2 | [EmailAction + EmailActionQueue + CancellationToken](phase-02-email-action-queue.md) | Done |
| 3 | [Wire EmailListStateProvider to EventBus](phase-03-wire-provider.md) | Done |
| 4 | [Migrate controllers to use ActionQueue](phase-04-migrate-controllers.md) | Done |
| 5 | [OCP: Bus Handlers + Pure State Store](../260413-1706-ocp-eventbus-state-propagation/plan.md) | In Progress |

## Key Constraints

- Domain layer (`MarkAsEmailReadInteractor`, `EmailFlagService`) → **do not modify**
- New path is additive — controllers opt in by using `EmailActionQueue`
- `EmailFlagActionHandler` → **removed** (replaced by queue + token)
- `EmailServiceRegistry` → **removed** (interactors used directly via `Get.find`)

## Architecture Evolution (Phase 5)

- `EmailListStateProvider` → pure state store, zero bus knowledge
- Each event type has its own `BusHandler` (e.g., `MarkAsReadBusHandler`, `GetAllEmailBusHandler`)
- Controllers subscribe to bus only for UI reactions (scroll, toast, selection sync)
- See [OCP plan](../260413-1706-ocp-eventbus-state-propagation/plan.md) for details
