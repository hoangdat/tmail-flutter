# Architecture Overview

**Parent**: [Cross-Controller Communication Strategy](./plan.md)

---

## Layered Communication Flow

```
┌─────────────────────────────────────────────────────────┐
│                    UI LAYER                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Controller A │  │ Controller B │  │ Controller C │  │
│  │              │  │              │  │              │  │
│  │ subscribes ↓ │  │ subscribes ↓ │  │ subscribes ↓ │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
                         ↓ (listen to streams)
┌─────────────────────────────────────────────────────────┐
│                 DOMAIN LAYER                             │
│  ┌──────────────────────────────────────────────────┐   │
│  │         Repository (Single Source of Truth)       │   │
│  │                                                    │   │
│  │  - Owns data state                                │   │
│  │  - Exposes Stream<State>                          │   │
│  │  - Handles business logic                         │   │
│  │  - No UI knowledge                                │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                         ↓ (fetches data)
┌─────────────────────────────────────────────────────────┐
│                  DATA LAYER                              │
│  ┌────────────────┐       ┌────────────────┐            │
│  │ Remote API     │       │ Local Cache    │            │
│  │ (JMAP Server)  │       │ (Hive)         │            │
│  └────────────────┘       └────────────────┘            │
└─────────────────────────────────────────────────────────┘
```

---

## Key Principles

### 1. No Controller-to-Controller Communication

**Rule**: Controllers never call each other directly

❌ **Bad - Direct coupling**:
```dart
class MailboxListController {
  void selectMailbox(Mailbox mailbox) {
    final emailController = Get.find<EmailListController>();
    emailController.loadEmails(mailbox); // Tight coupling!
  }
}
```

✅ **Good - Repository mediates**:
```dart
class MailboxListController {
  final MailboxStateRepository _mailboxState;

  void selectMailbox(Mailbox mailbox) {
    _mailboxState.setSelectedMailbox(mailbox); // Update repository
    // EmailListController auto-notified via stream (no coupling)
  }
}
```

**Benefits**:
- Controllers don't know about each other
- Easy to add/remove controllers without breaking others
- Clear dependency graph (controller → repository, not controller → controller)

### 2. Repository as Mediator

**Rule**: Repository owns canonical state and broadcasts changes

```dart
class MailboxStateRepository {
  // Private state
  Mailbox? _selectedMailbox;

  // Public stream (broadcast to multiple listeners)
  final _selectedMailboxController = StreamController<Mailbox?>.broadcast();
  Stream<Mailbox?> get selectedMailboxStream => _selectedMailboxController.stream;

  // Public getter (current value)
  Mailbox? get selectedMailbox => _selectedMailbox;

  // State mutation (broadcasts to all listeners)
  void setSelectedMailbox(Mailbox? mailbox) {
    _selectedMailbox = mailbox;
    _selectedMailboxController.add(mailbox);
  }

  void dispose() => _selectedMailboxController.close();
}
```

**Characteristics**:
- Repository owns state (single source of truth)
- Multiple controllers can subscribe to same stream
- State changes propagate automatically
- No polling or manual refresh needed

### 3. Explicit Dependencies via GetIt

**Rule**: All dependencies declared in constructor, injected by GetIt

❌ **Bad - Hidden dependencies (GetX)**:
```dart
class EmailListController {
  void loadEmails() {
    final repo = Get.find<EmailRepository>(); // Hidden dependency!
    final auth = Get.find<AuthService>(); // Hidden dependency!
    // Can't tell what this controller needs by reading constructor
  }
}
```

✅ **Good - Explicit dependencies (GetIt)**:
```dart
class EmailListController {
  final EmailRepository _emailRepository;
  final MailboxStateRepository _mailboxState;
  final AuthService _authService;

  // Clear what this controller depends on
  EmailListController(
    this._emailRepository,
    this._mailboxState,
    this._authService,
  );
}

// GetIt registration
void setupDI() {
  getIt.registerFactory(() => EmailListController(
    getIt<EmailRepository>(),
    getIt<MailboxStateRepository>(),
    getIt<AuthService>(),
  ));
}
```

**Benefits**:
- Compile-time type safety
- IDE autocomplete for dependencies
- Easy to test (mock in constructor)
- Clear dependency graph

### 4. Unidirectional Data Flow

**Rule**: Data flows in one direction: User → Controller → Use Case → Repository → Stream → Controllers → UI

```
┌──────────────┐
│  User Action │ (tap, swipe, input)
└──────┬───────┘
       ↓
┌──────────────┐
│  Controller  │ (handles UI event)
└──────┬───────┘
       ↓
┌──────────────┐
│   Use Case   │ (business logic)
└──────┬───────┘
       ↓
┌──────────────┐
│  Repository  │ (updates state, emits stream)
└──────┬───────┘
       ↓
┌──────────────┐
│    Stream    │ (broadcasts to subscribers)
└──────┬───────┘
       ↓
┌──────────────┐
│ Controllers  │ (listen, update UI state)
└──────┬───────┘
       ↓
┌──────────────┐
│      UI      │ (rebuilds with new state)
└──────────────┘
```

**Example Flow - Selecting Mailbox**:
1. User taps "Inbox" in mailbox list
2. `MailboxListController.selectMailbox(inbox)` called
3. Controller calls `SelectMailboxUseCase(inbox)`
4. Use case calls `MailboxStateRepository.setSelectedMailbox(inbox)`
5. Repository emits inbox via `selectedMailboxStream`
6. `EmailListController` listening to stream receives inbox
7. `EmailListController` loads emails for inbox
8. UI rebuilds with new email list

**Benefits**:
- Predictable data flow
- Easy to debug (follow stream from source to destination)
- Clear separation of concerns
- Testable at every layer

---

## State Repository Types

### Shared State Repositories (Singletons)

**Purpose**: Manage cross-cutting state shared by multiple controllers

**Examples**:
- `MailboxStateRepository` - selected mailbox, mailbox list filter
- `UserStateRepository` - current user, account settings
- `EmailStateRepository` - selected email, email list filters
- `SearchStateRepository` - search query, search filters
- `NetworkStateRepository` - online/offline status

**Lifecycle**: App lifetime (registered as singletons in GetIt)

**Pattern**:
```dart
// Register as singleton (shared across app)
getIt.registerSingleton<MailboxStateRepository>(
  MailboxStateRepository(),
);

// Multiple controllers inject same instance
class ControllerA {
  final MailboxStateRepository _state;
  ControllerA(this._state); // Same instance
}

class ControllerB {
  final MailboxStateRepository _state;
  ControllerB(this._state); // Same instance
}
```

### Data Repositories (Singletons)

**Purpose**: Manage data fetching, caching, persistence

**Examples**:
- `MailboxRepository` - CRUD operations for mailboxes
- `EmailRepository` - CRUD operations for emails
- `AccountRepository` - Account management

**Lifecycle**: App lifetime (registered as singletons in GetIt)

**Pattern**:
```dart
class EmailRepository {
  final EmailDataSource _remoteDataSource;
  final EmailCache _localCache;

  EmailRepository(this._remoteDataSource, this._localCache);

  Stream<List<Email>> getEmailsForMailbox(MailboxId id) async* {
    // Emit cached first (offline-first)
    yield await _localCache.getEmails(id);

    // Fetch from server
    final emails = await _remoteDataSource.fetchEmails(id);

    // Update cache
    await _localCache.saveEmails(emails);

    // Emit server data
    yield emails;
  }
}
```

### Controllers (Factories)

**Purpose**: Manage UI state and logic for specific screen/feature

**Lifecycle**: Screen lifetime (registered as factories in GetIt, new instance per route)

**Pattern**:
```dart
// Register as factory (new instance per route)
getIt.registerFactory(() => EmailListController(
  getIt<EmailRepository>(),
  getIt<MailboxStateRepository>(),
));

// Each route gets new instance
final controller1 = getIt<EmailListController>(); // Instance 1
final controller2 = getIt<EmailListController>(); // Instance 2
```

---

## Comparison: GetX vs Repository + Stream

### GetX Service Locator (Current - Problems)

```dart
// Controller A (mailbox list)
class MailboxListController extends GetxController {
  void selectMailbox(Mailbox mailbox) {
    // Hidden coupling to EmailListController
    Get.find<EmailListController>().loadEmails(mailbox);
  }
}

// Controller B (email list)
class EmailListController extends GetxController {
  void loadEmails(Mailbox mailbox) {
    // Called directly by MailboxListController
  }
}
```

**Problems**:
- Hidden dependencies (Get.find not visible in constructor)
- Tight coupling (ControllerA knows about ControllerB)
- Hard to test (must mock entire Get registry)
- Order-dependent (EmailListController must exist when MailboxListController calls it)

### Repository + Stream (Recommended - Solution)

```dart
// Shared repository
class MailboxStateRepository {
  final _selectedMailbox = StreamController<Mailbox?>.broadcast();
  Stream<Mailbox?> get selectedMailboxStream => _selectedMailbox.stream;

  void setSelectedMailbox(Mailbox? mailbox) {
    _selectedMailbox.add(mailbox);
  }
}

// Controller A (mailbox list)
class MailboxListController extends GetxController {
  final MailboxStateRepository _mailboxState;

  MailboxListController(this._mailboxState); // Explicit dependency

  void selectMailbox(Mailbox mailbox) {
    _mailboxState.setSelectedMailbox(mailbox); // Update repository
    // EmailListController auto-notified (no coupling)
  }
}

// Controller B (email list)
class EmailListController extends GetxController {
  final MailboxStateRepository _mailboxState;
  late StreamSubscription _sub;

  EmailListController(this._mailboxState); // Explicit dependency

  @override
  void onInit() {
    _sub = _mailboxState.selectedMailboxStream.listen((mailbox) {
      if (mailbox != null) loadEmails(mailbox); // React to change
    });
  }

  @override
  void onClose() {
    _sub.cancel();
    super.onClose();
  }
}
```

**Benefits**:
- Explicit dependencies (constructor parameters)
- Loose coupling (controllers don't know about each other)
- Easy to test (mock repository in constructor)
- Order-independent (controllers subscribe when ready)
- Type-safe (compile-time checked)
