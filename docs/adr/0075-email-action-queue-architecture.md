# 0075 - Email Action Queue Architecture

## Status
In Progress

## Context
The existing `consumeState` + mixin pattern (`EmailActionController`) couples controllers tightly to interactors and domain state routing. Each controller handles success/failure/done via overrides of `handleSuccessViewState`/`handleFailureViewState`/`onDone`, making controllers fat and hard to maintain. Adding a new action requires modifying multiple switch-case blocks across controllers.

## Decision
Introduce a layered architecture that decouples action execution, state management, and UI reactions:

### Core Components

| Component | Type | Lifecycle | Location |
|-----------|------|-----------|----------|
| `EmailAction` | Abstract class | Per-call | `lib/features/email/presentation/action/email_action.dart` |
| `EmailActionQueue` | GetxService | App | `lib/features/email/presentation/action/email_action_queue.dart` |
| `CancellationToken` | Plain class | Controller | `lib/features/email/presentation/action/cancellation_token.dart` |
| `AppEventBus` | GetxService | App | `lib/features/base/event_bus/app_event_bus.dart` |
| `SessionStateProvider` | GetxService | App | `lib/features/base/state/session_state_provider.dart` |
| `MailboxStateProvider` | GetxService | App | `lib/features/base/state/mailbox_state_provider.dart` |
| `EmailListStateProvider` | GetxService | App | `lib/features/base/state/email_list_state_provider.dart` |

### State Providers

- **SessionStateProvider** - holds `Session` + `AccountId`, set after login, read by `EmailActionQueue`
- **MailboxStateProvider** - holds `mapMailboxById` + `selectedMailbox`, synced from `MailboxDashBoardController`
- **EmailListStateProvider** - holds `emailsInCurrentMailbox`, `listResultSearch`, `currentEmailState`, listens to bus for flag updates

### Architecture Flow

```
Controller.getAllEmailAction()              <- thin, just submits
  |
  v
EmailActionQueue.submit(action, token)
  |
  v
GetEmailsInMailboxAction.execute()
  |-- interactor.execute()                  <- raw JMAP fetch
  |-- _syncSuccess()                        <- syncs via MailboxStateProvider + SearchController
  |
  v
EmailActionQueue fires result on AppEventBus
  |
  +-- ThreadController._onGetAllEmailSuccess()   <- scroll, selection, load-more (UI only)
  +-- ThreadController._onGetAllEmailFailure()   <- error UI
  +-- EmailListStateProvider (bus listener)       <- stores email list, updates flags
```

### CancellationToken Pattern

```dart
// Screen-scoped: callbacks skipped on controller close, HTTP still completes
_actionQueue.submit(action, token: _cancelToken);

// Background: survives controller disposal
_actionQueue.submit(action);
```

### Action Classes

Each action is a self-contained class that:
1. Receives interactor + state providers as constructor params
2. Executes the interactor in `execute(session, accountId)`
3. Does common post-processing (e.g., `syncPresentationEmail`) using providers
4. Returns processed `Stream<Either<Failure, Success>>`

Example: `GetEmailsInMailboxAction` reads `MailboxStateProvider` for `mapMailboxById`/`selectedMailbox` and `SearchController` for search state to sync presentation emails before the result hits the bus.

### Key Design Principles

- **Action -> reads Provider**: one-way, no coupling. Action is short-lived, reads state snapshot.
- **Provider does NOT depend on Provider**: no circular deps.
- **Bus decouples producers from consumers**: queue fires events, any listener reacts.
- **Controller stays thin**: only submits actions and handles UI-specific bus reactions.
- **Old mixin paths untouched**: `EmailActionController` mixin and `consumeState` still work for non-migrated actions.

## Consequences

### Positive
- Controllers become thin — `getAllEmailAction()` is a simple submit call
- Adding new actions = new action class + bus listener, no switch-case modifications
- Common logic lives in actions close to the data, not duplicated across controllers
- Background execution possible by omitting CancellationToken
- Testable — actions and providers are independent units

### Negative
- More files (action classes, providers, event bus)
- Two parallel patterns during migration (old `consumeState` + new queue)
- Bus listeners need cleanup in `onClose()`

## Migration Path
Actions migrate one at a time. Old `consumeState` paths remain until fully replaced. Current migrations:
- `getAllEmailAction` - Done (ThreadController)
- `markAsEmailRead` / `markAsReadMultiple` - Done (mark-as-read actions via bus)
- Other actions (loadMore, search, refresh, getEmailById) - Todo
