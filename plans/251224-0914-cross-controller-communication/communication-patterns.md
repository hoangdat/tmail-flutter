# Communication Patterns

**Parent**: [Cross-Controller Communication Strategy](./plan.md)

---

## Pattern 1: Shared State (Most Common)

**Use Case**: Multiple controllers need same data (e.g., selected mailbox, current user)

### Implementation

```dart
// Repository (single source of truth)
class MailboxStateRepository {
  final _selectedMailboxController = StreamController<Mailbox?>.broadcast();
  Stream<Mailbox?> get selectedMailboxStream => _selectedMailboxController.stream;

  Mailbox? _selectedMailbox;
  Mailbox? get selectedMailbox => _selectedMailbox;

  void setSelectedMailbox(Mailbox? mailbox) {
    _selectedMailbox = mailbox;
    _selectedMailboxController.add(mailbox);
  }

  void dispose() => _selectedMailboxController.close();
}

// Controller A (selects mailbox)
class MailboxListController extends GetxController {
  final MailboxStateRepository _mailboxState;

  MailboxListController(this._mailboxState); // GetIt injects

  void onMailboxTap(Mailbox mailbox) {
    _mailboxState.setSelectedMailbox(mailbox); // Update repository
  }
}

// Controller B (reacts to selection)
class EmailListController extends GetxController {
  final MailboxStateRepository _mailboxState;
  late StreamSubscription _subscription;

  EmailListController(this._mailboxState);

  @override
  void onInit() {
    super.onInit();
    _subscription = _mailboxState.selectedMailboxStream.listen((mailbox) {
      if (mailbox != null) {
        _loadEmailsForMailbox(mailbox); // React to change
      }
    });
  }

  @override
  void onClose() {
    _subscription.cancel();
    super.onClose();
  }

  void _loadEmailsForMailbox(Mailbox mailbox) {
    // Load emails...
  }
}

// GetIt registration (Phase 4)
void setupDI() {
  getIt.registerSingleton<MailboxStateRepository>(
    MailboxStateRepository(),
  );
  getIt.registerFactory(() => MailboxListController(getIt()));
  getIt.registerFactory(() => EmailListController(getIt()));
}
```

### Advantages

- ✅ Explicit dependency (constructor injection)
- ✅ Type-safe (compile-time checked)
- ✅ Testable (mock repository)
- ✅ Clear data flow (repository → stream → controller)
- ✅ No memory leaks (StreamBuilder auto-unsubscribes)
- ✅ Loose coupling (controllers independent)

### Testing

```dart
test('EmailListController loads emails when mailbox selected', () {
  // Mock repository
  final mockState = MockMailboxStateRepository();
  final mailboxStream = StreamController<Mailbox?>.broadcast();
  when(mockState.selectedMailboxStream).thenAnswer((_) => mailboxStream.stream);

  // Create controller with mock
  final controller = EmailListController(mockState);

  // Emit mailbox
  mailboxStream.add(testMailbox);

  // Verify controller reacted
  expect(controller.emails, isNotEmpty);
});
```

---

## Pattern 2: Event Notification (Action-Based)

**Use Case**: Notify other controllers of actions without sharing state (e.g., email sent, draft saved)

### Implementation

```dart
// Event classes (type-safe)
abstract class EmailEvent {}

class EmailSentEvent extends EmailEvent {
  final Email email;
  EmailSentEvent(this.email);
}

class DraftSavedEvent extends EmailEvent {
  final EmailId draftId;
  DraftSavedEvent(this.draftId);
}

// Repository exposes event stream
class EmailRepository {
  final _eventsController = StreamController<EmailEvent>.broadcast();
  Stream<EmailEvent> get events => _eventsController.stream;

  Future<void> sendEmail(Email email) async {
    // Send email...
    _eventsController.add(EmailSentEvent(email));
  }

  Future<void> saveDraft(EmailId draftId) async {
    // Save draft...
    _eventsController.add(DraftSavedEvent(draftId));
  }

  void dispose() => _eventsController.close();
}

// Controller emits events
class ComposerController extends GetxController {
  final EmailRepository _emailRepository;

  ComposerController(this._emailRepository);

  Future<void> sendEmail(Email email) async {
    await _emailRepository.sendEmail(email);
    // Repository emits EmailSentEvent, listeners auto-notified
  }
}

// Controller listens to events
class EmailListController extends GetxController {
  final EmailRepository _emailRepository;
  late StreamSubscription _subscription;

  @override
  void onInit() {
    super.onInit();
    _subscription = _emailRepository.events.listen((event) {
      if (event is EmailSentEvent) {
        _refreshEmailList(); // React to sent email
      } else if (event is DraftSavedEvent) {
        _markDraftSaved(event.draftId);
      }
    });
  }

  @override
  void onClose() {
    _subscription.cancel();
    super.onClose();
  }

  void _refreshEmailList() {
    // Refresh...
  }

  void _markDraftSaved(EmailId draftId) {
    // Update UI...
  }
}
```

### Advantages

- ✅ Type-safe events (compile-time checking)
- ✅ Pattern matching on event types
- ✅ Clear event sources (repository owns events)
- ✅ Easy testing (mock repository events)
- ✅ Decoupled (controllers don't know about each other)

### Testing

```dart
test('EmailListController refreshes when email sent', () {
  final mockRepo = MockEmailRepository();
  final eventStream = StreamController<EmailEvent>.broadcast();
  when(mockRepo.events).thenAnswer((_) => eventStream.stream);

  final controller = EmailListController(mockRepo);

  // Emit event
  eventStream.add(EmailSentEvent(testEmail));

  // Verify refresh
  verify(controller._refreshEmailList()).called(1);
});
```

---

## Pattern 3: Reactive State with ValueNotifier (Simple State)

**Use Case**: Simple single-value state (boolean flags, counters, strings)

### Implementation

```dart
// Service with ValueNotifier
class NetworkStatusService {
  final isOnline = ValueNotifier<bool>(true);

  void setOnlineStatus(bool online) {
    isOnline.value = online;
  }

  void dispose() => isOnline.dispose();
}

// Controllers listen via ValueListenableBuilder (automatic cleanup)
class EmailController extends GetxController {
  final NetworkStatusService _networkService;

  EmailController(this._networkService);

  Widget buildOfflineIndicator() {
    return ValueListenableBuilder<bool>(
      valueListenable: _networkService.isOnline,
      builder: (context, isOnline, child) {
        if (!isOnline) {
          return Container(
            color: Colors.red,
            child: Text('Offline'),
          );
        }
        return SizedBox.shrink();
      },
    );
  }
}

// GetIt registration
void setupDI() {
  getIt.registerSingleton<NetworkStatusService>(NetworkStatusService());
  getIt.registerFactory(() => EmailController(getIt()));
}
```

### Advantages

- ✅ Simplest pattern for single values
- ✅ No stream overhead
- ✅ ValueListenableBuilder handles subscriptions automatically
- ✅ Built-in Flutter (no packages)
- ✅ Memory-efficient

### When to Use

Use ValueNotifier when:
- Single value state (not collections or complex objects)
- Simple boolean/int/string/enum
- No complex transformations needed
- UI-only reactivity (not business logic)

Use Streams when:
- Multiple values or complex state
- Need stream transformations (debounce, throttle, combine)
- Business logic needs to react (not just UI)
- Async data flow

### Testing

```dart
test('UI shows offline indicator when network offline', () {
  final service = NetworkStatusService();
  final controller = EmailController(service);

  // Set offline
  service.setOnlineStatus(false);

  // Verify UI updated
  expect(service.isOnline.value, false);
  expect(controller.buildOfflineIndicator(), isA<Container>());
});
```

---

## Pattern Comparison

| Pattern | Use Case | Complexity | Type Safety | Memory | Best For |
|---------|----------|------------|-------------|--------|----------|
| Shared State (Stream) | Multiple controllers need same data | Medium | ✅ High | Medium | Selected items, filters, lists |
| Event Notification (Stream) | Action notifications | Medium | ✅ High | Medium | User actions, system events |
| ValueNotifier | Simple single-value state | Low | ✅ High | Low | Flags, counters, enums |
| BehaviorSubject (RxDart) | Stream + latest value | Medium | ✅ High | Medium | State with initial value |

---

## Anti-Patterns to Avoid

### ❌ Controller-to-Controller Direct Calls

```dart
// BAD - tight coupling
class MailboxListController {
  void selectMailbox(Mailbox mailbox) {
    Get.find<EmailListController>().loadEmails(mailbox); // Hidden dependency!
  }
}
```

**Problems**:
- Hidden dependency (not in constructor)
- Tight coupling (MailboxListController knows EmailListController)
- Hard to test (must mock entire Get registry)
- Order-dependent (EmailListController must exist)

### ❌ Global Event Bus

```dart
// BAD - no type safety, hidden dependencies
eventBus.fire('mailbox_selected', mailbox); // String key!
eventBus.on('mailbox_selected').listen(...); // Typo risk!
```

**Problems**:
- No compile-time safety (typos fail at runtime)
- Hidden dependencies (who listens to what?)
- Hard to refactor (string keys scattered)
- Memory leaks (forgotten subscriptions)

### ❌ Static Global State

```dart
// BAD - global mutable state, hard to test
class GlobalState {
  static Mailbox? selectedMailbox; // Global!
}

class MailboxListController {
  void selectMailbox(Mailbox mailbox) {
    GlobalState.selectedMailbox = mailbox; // Who's listening?
  }
}
```

**Problems**:
- Hard to test (global state persists between tests)
- No reactivity (listeners can't know when changed)
- No encapsulation (any code can modify)
- Race conditions (concurrent access)

### ✅ Repository + Stream (Recommended)

```dart
// GOOD - explicit, type-safe, testable
class MailboxStateRepository {
  final _selectedMailbox = BehaviorSubject<Mailbox?>();
  Stream<Mailbox?> get selectedMailbox => _selectedMailbox.stream;

  void selectMailbox(Mailbox? mailbox) => _selectedMailbox.add(mailbox);

  void dispose() => _selectedMailbox.close();
}
```

**Benefits**:
- Explicit dependency (injected in constructor)
- Type-safe (compile-time checked)
- Testable (mock repository)
- Reactive (listeners auto-notified)
- Encapsulated (repository controls state)
