# Phase 01: Architecture Explanation — Current vs Target

## Table of Contents

1. [How the Current Architecture Works](#how-the-current-architecture-works)
2. [Target Architecture Overview](#target-architecture)
3. [How to Split Controllers](#how-to-split-controllers)
4. [How to Manage Lifecycle](#how-to-manage-lifecycle)
5. [SOLID Applied](#solid-applied-to-this-architecture)
6. [Migration Strategy](#migration-strategy)

---

## How the Current Architecture Works

### The Hub-and-Spoke Model

`MailboxDashBoardController` is the central nervous system. Every feature controller connects to it.

```
┌──────────────────────────────────────────────────────────────────────┐
│                    MailboxDashBoardController                        │
│                         (GOD OBJECT)                                │
│                                                                      │
│  Reactive Streams (Rxn):                                            │
│  ┌──────────────┐ ┌──────────────┐ ┌───────────────┐               │
│  │dashBoardAction│ │mailboxUIAction│ │emailUIAction  │ ...           │
│  └──────┬───────┘ └──────┬───────┘ └──────┬────────┘               │
│         │                │                │                          │
│  Shared State:                                                       │
│  selectedMailbox, accountId, sessionCurrent, emailsInCurrentMailbox, │
│  mapMailboxById, mapDefaultMailboxIdByRole, listEmailSelected, ...   │
│                                                                      │
│  Business Logic:                                                     │
│  30+ interactors (email CRUD, composer, identity, sort, spam, ...)  │
└──────────────────────────────────────────────────────────────────────┘
         │                │                │
    ┌────▼────┐     ┌────▼────┐     ┌────▼────┐
    │ Mailbox  │     │ Thread  │     │ Single  │   ... 13 controllers
    │Controller│     │Controller│    │ Email   │
    └──────────┘     └──────────┘    │Controller│
                                     └──────────┘
```

### 3 Communication Mechanisms (All Through Dashboard)

#### 1. Direct State Reading (Tight Coupling)
```dart
// ThreadController reads dashboard state directly
AccountId? get _accountId => mailboxDashBoardController.accountId.value;
Session? get _session => mailboxDashBoardController.sessionCurrent;
```
**Problem:** ThreadController cannot exist without dashboard. Testing requires mocking entire dashboard.

#### 2. Reactive Workers via `ever()` (One-Way Event Listening)
```dart
ever(mailboxDashBoardController.dashBoardAction, (action) {
  if (action is RefreshAllEmailAction) { ... }
  if (action is SelectionAllEmailAction) { ... }
  // ... big switch on action types
});
```
**Problem:** Dashboard doesn't know who's listening. Manual `clearDashBoardAction()` is fragile.

#### 3. Direct Method Calls (Upward Coupling)
```dart
mailboxDashBoardController.emailsInCurrentMailbox.clear();
mailboxDashBoardController.updateRefreshAllEmailState(Left(RefreshAllEmailFailure()));
```
**Problem:** Any controller can mutate dashboard state from anywhere — no ownership boundaries.

### Summary of Current Problems

| Problem | SOLID Violation | Impact |
|---------|-----------------|--------|
| Dashboard owns 30+ interactors | **S** (Single Responsibility) | Adding email feature = modifying 3,500-line file |
| Sub-controllers `Get.find<Dashboard>()` | **D** (Dependency Inversion) | Can't test/reuse any controller in isolation |
| All shared state on one class | **I** (Interface Segregation) | ThreadController depends on entire dashboard for just 2 fields |
| New features modify dashboard | **O** (Open/Closed) | Labels, AI Scribe, spam all required editing the God Object |
| BaseController does infrastructure injection | **L** (Liskov Substitution) | Subclasses inherit unused responsibilities |

---

## Target Architecture

### Core Principle: Controllers Own Their Domain, Communicate Through Abstractions

```
┌─────────────────────────────────────────────────────────────┐
│                    Shared State Layer                         │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ SessionState│  │ MailboxState  │  │ EmailListState│       │
│  │ Provider    │  │ Provider     │  │ Provider      │       │
│  └──────┬─────┘  └──────┬───────┘  └──────┬────────┘       │
│   accountId       selectedMailbox    emailsInMailbox         │
│   session         mapMailboxById     selectedEmail           │
└─────────┼────────────────┼────────────────┼─────────────────┘
          │                │                │
          │   ┌────────────┴────────────┐   │
          │   │      App Event Bus       │   │
          │   │   publish() / on<T>()    │   │
          │   └────────────┬────────────┘   │
          │                │                │
     ┌────┴───┐  ┌────────┴──────┐  ┌─────┴────┐  ┌──────────┐
     │Service  │  │  Service      │  │ Service  │  │ Screen   │
     │Registry │  │  Registry     │  │ Registry │  │Controllers│
     │(Email)  │  │  (Composer)   │  │(Download)│  │(route)   │
     └────────┘  └───────────────┘  └──────────┘  └──────────┘
```

### 4 Architectural Layers

| Layer | What | Example |
|---|---|---|
| **State Providers** | Reactive state only. No logic. | `SessionStateProvider`, `MailboxStateProvider` |
| **App Event Bus** | Typed pub/sub for cross-feature communication | `EmailFlagsUpdatedEvent`, `MailboxSelectedEvent` |
| **Service Registries** | Grouped domain services with lifecycle management | `EmailServiceRegistry`, `DownloadServiceRegistry` |
| **Screen/Micro Controllers** | View state for one screen or widget | `ThreadController`, `RichTextWebController` |

---

## How to Split Controllers

### Step 1: Identify Split Axis

**Split by action verb (what it does), not by entity (what it acts on).**

```
✗ BAD: One big "EmailController" that does everything to emails
✓ GOOD: EmailFlagService, EmailMoveService, EmailDeleteService
```

Decision table for where logic belongs:

| Ask yourself | If yes → |
|---|---|
| Does it mutate email state on JMAP server? | Email service (flag/move/delete) |
| Does it transfer bytes to device? | Download service |
| Does it compose/send/save draft? | Composer service |
| Does it manage mailbox tree on server? | Mailbox service |
| Is it view-specific state (scroll, selection)? | Screen controller |
| Is it widget behavior (editor, autocomplete)? | Micro controller |

### Step 2: Start Coarse, Split When Needed

**YAGNI:** Don't pre-split into 20 services. Start with one service per domain.

```
Phase 1 (start here):
  EmailServiceRegistry
  └── EmailActionService (all email ops — ~200 lines)

Phase 2 (when EmailActionService hits ~200 lines or 5+ public methods):
  EmailServiceRegistry
  ├── EmailFlagService    (mark read, star, keywords)
  ├── EmailMoveService    (move single/batch, trash, spam)
  └── EmailDeleteService  (delete permanent, empty trash/spam)

Phase 3 (when new email features are added):
  EmailServiceRegistry
  ├── EmailFlagService
  ├── EmailMoveService
  ├── EmailDeleteService
  ├── EmailRestoreService    (recover deleted messages)
  ├── EmailUnsubscribeService
  └── EmailSnoozeService     (future)
```

**The split threshold: ~200 lines or 5+ public methods.**

### Step 3: Group into Service Registries

Individual services are NOT registered in GetX DI. They live inside a **registry**.

```dart
/// ONE entry in GetX DI. Manages all email-related services.
class EmailServiceRegistry extends GetxService {
  final AppEventBus _eventBus;

  // Lazy — only created when first accessed
  late final flag = EmailFlagService(_eventBus, Get.find(), Get.find());
  late final move = EmailMoveService(_eventBus, Get.find(), Get.find());
  late final delete = EmailDeleteService(_eventBus, Get.find(), Get.find());

  EmailServiceRegistry(this._eventBus);

  @override
  void onClose() {
    // All services cleaned up in one place
    super.onClose();
  }
}
```

Screen controllers access via the registry:

```dart
class SingleEmailController extends BaseController {
  final EmailServiceRegistry _email = Get.find();

  void markAsRead(email)       => _email.flag.markAsRead([email]);
  void moveToTrash(email)      => _email.move.moveToTrash(email);
  void deletePermanently(email) => _email.delete.deletePermanently(email);
}
```

**Adding a new service = one `late final` line in the registry. Zero DI changes.**

### Full Registry Map

Only **5-6 registries** in GetX DI, not 20+ services:

| Registry | Internal Services | Split Threshold |
|---|---|---|
| `EmailServiceRegistry` | flag, move, delete, (restore, unsubscribe later) | Start with 1 `EmailActionService`, split at ~200 LOC |
| `ComposerServiceRegistry` | draft, send, cache | Start with 1 `ComposerService`, split at ~200 LOC |
| `MailboxServiceRegistry` | create, rename, subscribe, clear | Start with 1 `MailboxActionService`, split at ~200 LOC |
| `DownloadServiceRegistry` | attachment, export, preview | Start with 1 `DownloadService`, split at ~200 LOC |
| `NotificationServiceRegistry` | fcm, websocket, local notification | Already separate — just re-home them |

### Feature Service vs Operation Service

| Type | Behavior | Examples |
|---|---|---|
| **Feature Service** | Executes domain logic, result instant/near-instant | EmailFlagService, EmailMoveService |
| **Operation Service** | Manages long-running tasks that **outlive the screen** | DownloadService, SendService |

**Operation Services** own a task queue and publish progress events:

```
User starts download in Email View A → navigates to Email View B

Email View A (disposed)              Email View B (new)
┌────────────┐                       ┌────────────┐
│ "Download"  │ ──── navigates ────► │ subscribes │
└─────┼──────┘                       └─────┼──────┘
      ▼                                    ▼
┌──────────────────────────────────────────────────────┐
│     DownloadService (session-lifetime, survives!)     │
│  activeDownloads: { #1: report.pdf ████░░ 60% }      │
│  → publishes DownloadProgressEvent to EventBus        │
└──────────────────────────────────────────────────────┘
```

A **global overlay widget** reads `activeDownloads` directly — independent of any screen:

```dart
Obx(() {
  final downloads = downloadService.activeDownloads;
  if (downloads.isEmpty) return SizedBox.shrink();
  return DownloadProgressOverlay(tasks: downloads.values.toList());
})
```

### Operation Lifetime Decision Table

| Duration | Owner | Examples |
|---|---|---|
| **Instant** (< 1s) | Screen controller | Toggle star, mark read |
| **Short** (1-5s) | Screen controller + toast on fail | Move to folder |
| **Long** (> 5s, user may navigate) | **Operation Service** (session) | Download, send email, restore deleted, empty trash |
| **Background** (survives app) | **Platform service** (WorkManager) | FCM sync, sending queue |

---

## How to Manage Lifecycle

### Tier Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ BOOT (app start)                                                │
│  ├── AppEventBus              (GetxService, permanent)          │
│  └── NetworkConnectionCtrl    (GetxService, permanent)          │
├─────────────────────────────────────────────────────────────────┤
│ LOGIN (session established)                                     │
│  ├── State Providers          (GetxService, deleted on logout)  │
│  │   ├── SessionStateProvider                                   │
│  │   ├── MailboxStateProvider                                   │
│  │   └── EmailListStateProvider                                 │
│  ├── Service Registries       (GetxService, deleted on logout)  │
│  │   ├── EmailServiceRegistry                                   │
│  │   ├── ComposerServiceRegistry                                │
│  │   ├── MailboxServiceRegistry                                 │
│  │   ├── DownloadServiceRegistry                                │
│  │   └── NotificationServiceRegistry                            │
│  └── DashboardSessionCtrl     (session init, reload)            │
├─────────────────────────────────────────────────────────────────┤
│ ROUTE (screen navigated to)                                     │
│  ├── ThreadController         (Get.lazyPut, auto-disposed)      │
│  ├── MailboxController        (Get.lazyPut, auto-disposed)      │
│  ├── SingleEmailController    (Get.lazyPut, auto-disposed)      │
│  ├── ComposerController       (Get.lazyPut, auto-disposed)      │
│  └── SearchEmailController    (Get.lazyPut, auto-disposed)      │
├─────────────────────────────────────────────────────────────────┤
│ WIDGET (widget built)                                           │
│  ├── RichTextWebController    (Dart-scoped or Get.create)       │
│  ├── RecipientFieldController                                   │
│  └── HoverSubmenuController                                     │
├─────────────────────────────────────────────────────────────────┤
│ LOGOUT (session destroyed)                                      │
│  ├── Delete all Service Registries → onClose() disposes internal│
│  ├── Clear all State Providers → clear() resets reactive fields │
│  └── EventBus stays alive (infra layer, no session state)       │
└─────────────────────────────────────────────────────────────────┘
```

### Lifecycle Initialization

```dart
/// Called once at app boot — in MainBindings
void onAppBoot() {
  Get.put(AppEventBus(), permanent: true);
  Get.put(NetworkConnectionController(...), permanent: true);
}

/// Called once on login success — in DashboardSessionController.handleReloaded()
void onSessionReady(Session session, AccountId accountId) {
  // State Providers
  Get.put(SessionStateProvider()..setSession(session, accountId));
  Get.put(MailboxStateProvider());
  Get.put(EmailListStateProvider());

  // Service Registries
  Get.put(EmailServiceRegistry(Get.find<AppEventBus>()));
  Get.put(ComposerServiceRegistry(Get.find<AppEventBus>()));
  Get.put(DownloadServiceRegistry(Get.find<AppEventBus>()));
  Get.put(MailboxServiceRegistry(Get.find<AppEventBus>()));
  Get.put(NotificationServiceRegistry(Get.find<AppEventBus>()));
}
```

### Lifecycle Cleanup

```dart
/// Called on logout — in LogoutService
Future<void> onLogout() async {
  // 1. Delete registries (onClose disposes all internal services)
  Get.delete<EmailServiceRegistry>();
  Get.delete<ComposerServiceRegistry>();
  Get.delete<DownloadServiceRegistry>();
  Get.delete<MailboxServiceRegistry>();
  Get.delete<NotificationServiceRegistry>();

  // 2. Clear state providers (reset to initial, don't delete — re-used on re-login)
  Get.find<SessionStateProvider>().clear();
  Get.find<MailboxStateProvider>().clear();
  Get.find<EmailListStateProvider>().clear();

  // 3. Clear caches, credentials
  await cachingManager.clearAll();
}
```

### Why Registries Solve the "Too Many Services" Problem

| Concern | Without Registries | With Registries |
|---|---|---|
| DI entries | 20+ `Get.put()` calls | **5-6** `Get.put()` calls |
| Logout cleanup | 20+ `Get.delete()` calls | **5-6** `Get.delete()` → each registry's `onClose()` cleans internal services |
| Adding new service | New `Get.put()` in init + `Get.delete()` in logout | **One `late final` line** in existing registry |
| Service instantiation | All created at login | **Lazy** — only when first accessed |
| Cross-service dependencies | Each independently wired | Registry wires its own children |

---

## Shared State Providers (Detail)

Lightweight `GetxService` that ONLY hold reactive state. No business logic. No interactors.

```dart
class SessionStateProvider extends GetxService {
  final accountId = Rxn<AccountId>();
  final session = Rxn<Session>();
  final ownEmailAddress = ''.obs;

  void setSession(Session s, AccountId id) {
    session.value = s;
    accountId.value = id;
  }

  void clear() {
    session.value = null;
    accountId.value = null;
    ownEmailAddress.value = '';
  }
}

class MailboxStateProvider extends GetxService {
  final selectedMailbox = Rxn<PresentationMailbox>();
  final mapMailboxById = <MailboxId, PresentationMailbox>{}.obs;
  final mapDefaultMailboxIdByRole = <Role, MailboxId>{}.obs;

  void clear() { /* reset all */ }
}

class EmailListStateProvider extends GetxService {
  final emailsInCurrentMailbox = <PresentationEmail>[].obs;
  final selectedEmail = Rxn<PresentationEmail>();
  final listEmailSelected = <PresentationEmail>[].obs;
  final selectMode = SelectMode.INACTIVE.obs;

  void clear() { /* reset all */ }
}
```

---

## App Event Bus (Detail) — CONFIRMED NEEDED

### Why Event Bus Is Required (Not Just State Providers)

The codebase has a **hidden bad event bus** via `_registerObxStreamListener()` in every controller:

```dart
// CURRENT: every sub-controller does this
ever(mailboxDashBoardController.dashBoardAction, (action) {
  if (action is SelectionAllEmailAction) { ... }
  else if (action is FilterMessageAction) { ... }
  else if (action is HandleEmailActionTypeAction) { ... }
  // 10+ type checks
  mailboxDashBoardController.clearDashBoardAction(); // manual cleanup!
});
```

**Problems with current approach:**
1. **Race condition** — first listener to `clearDashBoardAction()` wins, others miss the event
2. **Giant if/else switch** — violates Open/Closed, grows with every new action
3. **Tight coupling** — every controller imports MailboxDashBoardController just to listen
4. **Not data, it's commands** — `SelectionAllEmailAction` is a transient event, not persistent state. Can't model with State Providers or Obx.

**Controllers using this pattern (must be migrated):**
- `ThreadController._registerObxStreamListener()` — listens to `dashBoardAction`, `selectedMailbox`, `searchState`
- `MailboxController._registerObxStreamListener()` — listens to `accountId`, `mailboxUIAction`, `viewState`
- `SingleEmailController._registerObxStreamListener()` — listens to `emailUIAction`, `dashBoardAction`
- `SearchMailboxController._registerObxStreamListener()` — listens to dashboard actions
- `IdentitiesController._registerObxStreamListener()` — listens to dashboard state
- `ManageAccountMenuController._registerObxStreamListener()` — listens to dashboard state

### Two Communication Mechanisms (Clarified)

| Mechanism | For | Example |
|---|---|---|
| **State Provider (Obx)** | Persistent shared data that widgets READ | `emailsInCurrentMailbox`, `session`, `selectedMailbox` |
| **Event Bus (on\<T\>)** | Transient commands/events that trigger BEHAVIOR | `SelectionAllEmailAction`, `RefreshChangeMailboxAction`, `FilterMessageAction` |

**Rule of thumb:** If a widget uses `Obx()` to display it → State Provider. If a controller uses `ever()` to react to it → Event Bus.

### Target: Proper Event Bus

Typed pub/sub replacing `dashBoardAction` / `mailboxUIAction` / `emailUIAction` Rxn streams.

```dart
class AppEventBus extends GetxService {
  final _controller = StreamController<AppEvent>.broadcast();

  void publish(AppEvent event) {
    log('AppEventBus::publish: ${event.runtimeType}');
    _controller.add(event);
  }

  StreamSubscription<T> on<T extends AppEvent>(void Function(T) handler) {
    return _controller.stream.where((e) => e is T).cast<T>().listen(handler);
  }

  @override
  void onClose() {
    _controller.close();
    super.onClose();
  }
}
```

Events are typed, immutable:

```dart
abstract class AppEvent {}

class MailboxSelectedEvent extends AppEvent {
  final PresentationMailbox mailbox;
  MailboxSelectedEvent(this.mailbox);
}

class EmailFlagsUpdatedEvent extends AppEvent {
  final List<EmailId> emailIds;
  final Map<KeywordIdentifier, bool> flags;
  EmailFlagsUpdatedEvent(this.emailIds, this.flags);
}

class EmailMovedEvent extends AppEvent {
  final MoveAction moveAction;
  final PresentationEmail email;
  EmailMovedEvent(this.moveAction, this.email);
}

class DownloadProgressEvent extends AppEvent {
  final String taskId;
  final double progress;
  DownloadProgressEvent(this.taskId, this.progress);
}

class DownloadCompletedEvent extends AppEvent {
  final String taskId;
  final String filePath;
  DownloadCompletedEvent(this.taskId, this.filePath);
}
```

---

## Communication Patterns (Clarified)

Not everything goes through the event bus. Three patterns, each with a clear use case:

| Pattern | When | % of Interactions | Example |
|---|---|---|---|
| **Direct Call** | Controller invokes a service method and gets a stream back | **~70%** | `_email.flag.markAsRead(emails)` |
| **Reactive State (Obx)** | Widget reads shared state that changes over time | **~25%** | `Obx(() => Text(mailboxState.selectedMailbox.value?.name))` |
| **Event Bus** | One action affects multiple unrelated features | **~5%** | `EmailFlagsUpdatedEvent` → thread list + mailbox sidebar + badge |

### When to Use Each

```
Controller needs to DO something        → Direct Call to Service
Widget needs to DISPLAY current state   → Obx on State Provider
Feature needs to NOTIFY others          → Event Bus publish
```

**The event bus is NOT the primary communication mechanism.** It exists only for the ~5% of interactions where multiple unrelated features need to react to the same event (e.g., marking an email read updates the thread list, unread count, AND notification badge simultaneously).

---

## Interactor Integration: The `consumeState()` Pattern

### How Interactors Work Today

The codebase uses a **fire-and-forget stream pattern**, NOT request/response:

```dart
// BaseController (line ~130)
void consumeState(Stream<Either<Failure, Success>> newStateStream) async {
  newStateStream.listen(onData, onError: onError, onDone: onDone);
}

// onData routes to:
void onData(Either<Failure, Success> newState) {
  viewState.value = newState;
  newState.fold(handleFailureViewState, handleSuccessViewState);
}
```

**Key behavior:**
1. Interactor uses `async*` — returns a short-lived stream that emits 1-2 values (Success/Failure) then closes
2. `consumeState()` subscribes via `.listen()` (fire-and-forget, no await)
3. Results arrive asynchronously → routed to `handleSuccessViewState()` or `handleFailureViewState()`
4. `viewState.value` is updated → drives loading/error UI via `Obx()`

**Example interactor (async generator):**
```dart
class MarkAsEmailReadInteractor {
  Stream<Either<Failure, Success>> execute(...) async* {
    try {
      final result = await _emailRepository.markAsRead(...);
      yield Right(MarkAsEmailReadSuccess(result));
    } catch (e) {
      yield Left(MarkAsEmailReadFailure(exception: e));
    }
  }
}
```

### Current Problem: Giant `handleSuccessViewState()` Switch

```dart
// In MailboxDashBoardController today:
@override
void handleSuccessViewState(Success success) {
  if (success is MarkAsEmailReadSuccess) { ... }
  if (success is MoveToMailboxSuccess) { ... }
  if (success is DeleteEmailSuccess) { ... }
  // ... 30+ other success type checks
}
```

**Violates Open/Closed:** Adding a new interactor = adding another `if` branch to this giant switch.

### Target: Service as Pass-Through + Per-Action Callbacks

#### Step 1: Service Is a Thin Pass-Through

The service wraps the interactor but simply returns the stream. No stream sharing, no dual-listen complexity.

```dart
class EmailFlagService {
  final MarkAsEmailReadInteractor _markAsReadInteractor;

  Stream<Either<Failure, Success>> markAsRead(
    Session session, AccountId accountId,
    EmailId emailId, ReadActions action, ...
  ) {
    return _markAsReadInteractor.execute(session, accountId, emailId, action, ...);
  }
}
```

#### Step 2: Evolve `consumeState()` to Accept Per-Action Callbacks

```dart
// NEW BaseController.consumeState() — backward compatible
void consumeState(
  Stream<Either<Failure, Success>> stream, {
  Function(Success)? onSuccess,
  Function(Failure)? onFailure,
}) {
  stream.listen(
    (result) {
      viewState.value = result;  // still drives loading/error UI
      result.fold(
        (failure) => (onFailure ?? handleFailureViewState).call(failure),
        (success) => (onSuccess ?? handleSuccessViewState).call(success),
      );
    },
    onError: onError,
    onDone: onDone,
  );
}
```

**Backward compatible:** Old code using `consumeState(stream)` without callbacks → falls back to `handleSuccessViewState()`. No migration needed until ready.

#### Step 3: Each Call Site Handles Its Own Result

```dart
class ThreadController extends BaseController {
  final EmailServiceRegistry _email = Get.find();
  final AppEventBus _eventBus = Get.find();

  void markAsRead(PresentationEmail email) {
    consumeState(
      _email.flag.markAsRead(session, accountId, email.id, ...),
      onSuccess: _onMarkAsReadSuccess,
    );
  }

  void _onMarkAsReadSuccess(Success success) {
    if (success is MarkAsEmailReadSuccess) {
      _updateLocalEmailState(success);
      // ~5% case: notify others via event bus
      _eventBus.publish(EmailFlagsUpdatedEvent(success.emailIds, success.readAction));
    }
  }

  void moveToTrash(PresentationEmail email) {
    consumeState(
      _email.move.moveToTrash(session, accountId, email, ...),
      onSuccess: _onMoveToTrashSuccess,
    );
  }

  void _onMoveToTrashSuccess(Success success) {
    if (success is MoveToMailboxSuccess) {
      _removeFromList(success);
      _eventBus.publish(EmailMovedEvent(success.moveAction, success.email));
    }
  }

  // NO handleSuccessViewState() override needed!
  // Each action's result is self-contained at the call site.
}
```

### Why This Solves the SOLID Problem

| Principle | Old (`handleSuccessViewState` switch) | New (per-action callback) |
|---|---|---|
| **S — Single Responsibility** | One method handles 30+ success types | Each callback handles exactly 1 type |
| **O — Open/Closed** | Adding action = modify the switch | Adding action = new method + callback. **Zero change to existing code** |
| **I — Interface Segregation** | Controller imports all Success types | Each method imports only its own Success type |
| **D — Dependency Inversion** | Controller depends on concrete interactors | Controller depends on service interface |

### What Changes and What Stays the Same

| Aspect | Current | Target | Changed? |
|---|---|---|---|
| `consumeState()` exists | Yes | Yes (enhanced with optional callbacks) | **Evolved** |
| Interactor returns `Stream<Either>` | Same | Same | **No** |
| `viewState` drives loading UI | Same | Same | **No** |
| `handleSuccessViewState()` giant switch | 30+ checks in dashboard | **Eliminated** — per-action callbacks instead | **Yes** |
| Who executes the interactor | Dashboard (God Object) | Service (via registry) | **Yes** |
| Where result is handled | Central switch | At the call site | **Yes** |
| Cross-feature notification | Direct dashboard mutation | Event bus (~5% of cases) | **Yes** |

### Error Handling

| Scenario | Handler |
|---|---|
| **Route-scoped controller** (screen visible) | `onFailure` callback or default `handleFailureViewState()` — shows toast/snackbar |
| **Operation service** (screen may be disposed, e.g. download) | Service publishes `OperationFailedEvent` → global overlay widget catches it |
| **Urgent exceptions** (network, auth) | `onError` in `consumeState()` → `validateUrgentException()` → redirect to login (unchanged) |

### Migration Path (Incremental)

```
Phase 1: consumeState() with optional callbacks                       ✅ DONE
Phase 2: State Providers + Service Registries                         ✅ DONE
Phase 3: Migrate mark-as-read to mixin via providers + registry       ✅ DONE
Phase 4: Split EmailActionController into domain mixins               ← NEXT
Phase 5: Implement AppEventBus                                        ← NEXT
Phase 6: Replace _registerObxStreamListener with typed event subs     ← KEY STEP
Phase 7: Migrate remaining actions (star, move, delete, compose)
Phase 8: Shrink dashboard — remove migrated interactors + Rxn streams
Phase 9: Clean up BaseController (extract FCM/WS/logout)
```

### Phase 6 Detail: Decoupling _registerObxStreamListener

This is the **key decoupling step** — replacing `ever(dashboard.xxxAction)` with typed event bus subscriptions.

**Current (tightly coupled):**
```dart
// ThreadController
ever(mailboxDashBoardController.dashBoardAction, (action) {
  if (action is SelectionAllEmailAction) { setSelectAllEmailAction(); }
  if (action is FilterMessageAction) { filterMessagesAction(action.option); }
  if (action is HandleEmailActionTypeAction) { pressEmailSelectionAction(...); }
  if (action is StartSearchEmailAction) { _searchEmail(); }
  // ... 10+ more
  mailboxDashBoardController.clearDashBoardAction(); // fragile manual clear
});
```

**Target (decoupled with Event Bus):**
```dart
// ThreadController
@override
void onInit() {
  _subs.add(eventBus.on<SelectionAllEmailEvent>((e) => setSelectAllEmailAction()));
  _subs.add(eventBus.on<FilterMessageEvent>((e) => filterMessagesAction(e.option)));
  _subs.add(eventBus.on<HandleEmailActionTypeEvent>((e) => pressEmailSelectionAction(e.action, e.emails)));
  _subs.add(eventBus.on<StartSearchEmailEvent>((e) => _searchEmail()));
  super.onInit();
}

@override
void onClose() {
  for (final sub in _subs) sub.cancel();
  super.onClose();
}
```

**Migration per controller:**

| Controller | Current `ever()` listeners | Events to extract |
|---|---|---|
| **ThreadController** | `dashBoardAction` (10+ types), `selectedMailbox`, `searchState` | `SelectionAllEmailEvent`, `FilterMessageEvent`, `StartSearchEvent`, etc. |
| **MailboxController** | `accountId`, `mailboxUIAction` (7 types), `viewState` | `SelectMailboxDefaultEvent`, `RefreshMailboxEvent`, `OpenMailboxEvent`, etc. |
| **SingleEmailController** | `emailUIAction`, `dashBoardAction` | `EmailDetailEvent` types |
| **SearchMailboxController** | dashboard actions | Search-specific events |
| **IdentitiesController** | dashboard state | Identity-specific events |

**Each controller gets decoupled independently.** No big-bang migration.

### Mixin Split Strategy (Preventing New God Objects)

**Problem:** If all migrated actions go into one `EmailActionController` mixin, it becomes the new God Object.

**Solution:** Split by domain verb, each mixin `on BaseController`:

```dart
// Each mixin: ~60-100 lines, one domain, one registry
mixin EmailFlagActionMixin on BaseController {
  // markAsEmailRead, markAsReadMultiple, markAsStarEmail, markAsStarMultiple
  // Uses: EmailServiceRegistry.flag
}

mixin EmailMoveActionMixin on BaseController {
  // moveToTrash, moveToMailbox, moveToSpam, unSpam, archiveMessage
  // Uses: EmailServiceRegistry.move (future EmailMoveService)
}

mixin EmailDeleteActionMixin on BaseController {
  // deletePermanently, deleteMultiple, emptyTrash, emptySpam
  // Uses: EmailServiceRegistry.delete (future EmailDeleteService)
}

mixin EmailComposeActionMixin on BaseController {
  // editDraftEmail, editAsNewEmail, openComposer
  // Uses: ComposerServiceRegistry (future)
}
```

**Controllers mix in only what they need (Interface Segregation):**

```dart
class ThreadController extends BaseController
    with EmailFlagActionMixin, EmailMoveActionMixin, EmailDeleteActionMixin { }

class SearchEmailController extends BaseController
    with EmailFlagActionMixin, EmailMoveActionMixin { }

class SingleEmailController extends BaseController
    with AppLoaderMixin { /* own markAsRead impl with extra hook */ }
```

**Split threshold:** ~200 lines or 5+ public methods per mixin.

**YAGNI:** Don't pre-split. Split when the mixin grows past the threshold.

### Current Migration Status

| Action | Service | Mixin | Status |
|---|---|---|---|
| markAsEmailRead | `EmailFlagService` | `EmailActionController` | ✅ Done |
| markAsReadMultiple | `EmailFlagService` | `EmailActionController` | ✅ Done |
| markAsStarEmail | — | — | Next |
| moveToTrash | — | — | Future |
| moveToMailbox | — | — | Future |
| deleteEmailPermanently | — | — | Future |

---

## Concrete Data Flow: "Mark as Read"

### Target Flow
```
1. User taps "mark read" in ThreadView
2. ThreadView → ThreadController.markAsRead(email)
3. ThreadController calls:
     consumeState(
       _email.flag.markAsRead(session, accountId, email.id, ...),
       onSuccess: _onMarkAsReadSuccess,
     )
4. EmailFlagService.markAsRead() → returns interactor.execute() stream
5. Stream emits Right(MarkAsEmailReadSuccess)
6. consumeState() routes to _onMarkAsReadSuccess callback:
   ├── Updates local thread list (immediate UI)
   └── _eventBus.publish(EmailFlagsUpdatedEvent(...))
7. EventBus delivers to other subscribers:
   ├── MailboxController → updates unread count
   └── (future) BadgeController → updates badge
8. No controller knows about any other controller.
```

### Current Flow (for comparison)
```
1. User taps "mark read"
2. ThreadController → mailboxDashBoardController.markAsReadSelectedMultipleEmail(...)
3. Dashboard (3,498 lines) executes interactor, dispatches to Rxn streams
4. ThreadController.ever(dashBoardAction, ...) picks it up, calls clearDashBoardAction()
5. Dashboard is bottleneck for every email operation.
```

---

## SOLID Applied to This Architecture

### S — Single Responsibility
| Before | After |
|---|---|
| Dashboard owns email CRUD + composer + identity + search + labels + AI Scribe + sort + spam + keyboard shortcuts + ... | `EmailServiceRegistry` owns email mutations. `ComposerServiceRegistry` owns composer. `DashboardNavigationController` owns UI routing. Each service ≤ 200 lines. |

### O — Open/Closed
| Before | After |
|---|---|
| Adding Labels required editing `MailboxDashBoardController` | Adding Labels = new `LabelActionService` inside `EmailServiceRegistry` + new `LabelEvent` types. **Zero changes to existing services.** |
| Adding Snooze = another edit to dashboard | Adding Snooze = new `EmailSnoozeService` inside registry + `SnoozeEvent`. One `late final` line in registry. |

### L — Liskov Substitution
| Before | After |
|---|---|
| `BaseController` does FCM/WebSocket injection — subclasses inherit unused code | `BaseController` is minimal (state + error handling). Infrastructure moves to `NotificationServiceRegistry`. |

### I — Interface Segregation
| Before | After |
|---|---|
| ThreadController depends on entire `MailboxDashBoardController` (3,498 lines) | ThreadController depends on `SessionStateProvider` + `MailboxStateProvider` + `EmailServiceRegistry` — three small, focused interfaces |

### D — Dependency Inversion
| Before | After |
|---|---|
| `ThreadController → Get.find<MailboxDashBoardController>()` (concrete God Object) | `ThreadController → Get.find<AppEventBus>()` + `Get.find<EmailServiceRegistry>()` (abstractions) |

---

## Migration Strategy (Incremental, Not Rewrite)

```
Phase 1: Introduce AppEventBus + State Providers alongside existing dashboard
         ↓ Dashboard delegates state to providers, keeps backward compat

Phase 2: Introduce Service Registries (start with EmailServiceRegistry)
         ↓ Dashboard forwards calls to registry, old API still works

Phase 3: Migrate sub-controllers one by one
         ↓ ThreadController reads from providers, calls registry, listens to EventBus
         ↓ Remove its Get.find<MailboxDashBoardController>()

Phase 4: Shrink dashboard to thin DashboardNavigationController
         ↓ Only owns route state and drawer — under 300 lines

Phase 5: Clean up BaseController
         ↓ Extract FCM/WS/autocomplete injection to NotificationServiceRegistry
         ↓ Extract logout to LogoutService
         ↓ BaseController becomes ~150 lines (state + error handling only)
```

Each phase is independently shippable. No big-bang migration.

---

## Visual Summary

### Before (Hub-and-Spoke)
```
       ThreadCtrl ──┐
       MailboxCtrl ──┤
       ComposerCtrl ─┤
       SingleEmail ──┼──► MailboxDashBoardController (3,498 lines)
       SearchCtrl ───┤    - 30+ interactors
       SpamReport ───┤    - 30+ reactive fields
       Upload ───────┤    - all business logic
       Quotas ───────┘    - all shared state
```

### After (Event-Driven + Registries + State Providers)
```
  ┌─────────────┐  ┌────────────┐  ┌──────────────┐
  │ SessionState │  │MailboxState│  │EmailListState │  State Providers
  └──────┬───────┘  └─────┬──────┘  └──────┬───────┘  (read-only)
         │                │                │
  ┌──────┴────────────────┴────────────────┴──────┐
  │               App Event Bus                    │  Pub/Sub
  └──┬────┬────┬────┬────┬────┬────┬─────────────┘
     │    │    │    │    │    │    │
  ┌──┴──┐ │  ┌┴──┐ │  ┌┴──┐ │  ┌─┴──┐
  │Email│ │  │Comp│ │  │Down│ │  │Noti│  Service Registries
  │Svc  │ │  │Svc │ │  │load│ │  │fy  │  (session-lifetime)
  │Reg. │ │  │Reg.│ │  │Reg.│ │  │Reg.│
  └─────┘ │  └────┘ │  └────┘ │  └────┘
          │         │         │
       Thread    Mailbox   SingleEmail   Screen Controllers
       Ctrl      Ctrl      Ctrl          (route-lifetime)
```

---

## Unresolved Questions

1. Should `AppEventBus` use Dart `Stream<AppEvent>` or GetX `Rx`-based approach? Streams are standard Dart; Rx integrates with GetX workers (`ever()`).
2. Should state providers be interfaces (abstract classes) for full DI testability, or is concrete `GetxService` sufficient given the app's test patterns?
3. Priority order for migrating features out of dashboard? Suggestion: EmailServiceRegistry first (most referenced), then Composer, then Navigation.
4. Should micro-controllers use `Get.create` (new instance each time) or manual Dart lifecycle (constructor/dispose)?
