# Use Case Matrix

**Parent**: [Cross-Controller Communication Strategy](./plan.md)

---

## Communication Patterns by Use Case

| Scenario | Pattern | Repository | Example |
|----------|---------|------------|---------|
| Multiple controllers need same data | Repository + Stream | State Repository | Selected mailbox, current user |
| Notify controllers of action | Event Stream | Data Repository | Email sent, draft saved |
| Simple boolean/counter state | ValueNotifier | Service | Network online/offline |
| Real-time JMAP updates | Repository + Stream | Data Repository | New emails, mailbox changes |
| Cross-feature communication | Shared Repository | State Repository | Search → Email list |
| Transient notifications | Event Stream | Data Repository | Toast messages |
| Persistent UI state | Repository + Stream | State Repository | Filter settings, sort order |
| One-time commands | Use Case | Domain Layer | Send email, delete mailbox |

---

## Detailed Use Cases

### Use Case 1: Selected Mailbox (Shared State)

**Scenario**: User selects mailbox in sidebar, email list updates

**Controllers Involved**:
- `MailboxListController` (selects)
- `EmailListController` (reacts)
- `MailboxHeaderController` (reacts)

**Pattern**: Repository + Stream

**Implementation**:
```dart
// State repository
class MailboxStateRepository {
  final _selectedMailbox = BehaviorSubject<Mailbox?>();
  Stream<Mailbox?> get selectedMailboxStream => _selectedMailbox.stream;

  void selectMailbox(Mailbox? mailbox) => _selectedMailbox.add(mailbox);
}

// MailboxListController (producer)
class MailboxListController {
  final MailboxStateRepository _state;

  void onMailboxTap(Mailbox mailbox) {
    _state.selectMailbox(mailbox);
  }
}

// EmailListController (consumer)
class EmailListController {
  final MailboxStateRepository _state;

  @override
  void onInit() {
    _state.selectedMailboxStream.listen((mailbox) {
      if (mailbox != null) loadEmails(mailbox);
    });
  }
}
```

---

### Use Case 2: Email Sent Notification (Event)

**Scenario**: Composer sends email, email list refreshes

**Controllers Involved**:
- `ComposerController` (emits event)
- `EmailListController` (reacts)
- `DraftListController` (reacts)

**Pattern**: Event Stream

**Implementation**:
```dart
// Event classes
abstract class EmailEvent {}
class EmailSentEvent extends EmailEvent {
  final Email email;
  EmailSentEvent(this.email);
}

// Repository exposes events
class EmailRepository {
  final _events = StreamController<EmailEvent>.broadcast();
  Stream<EmailEvent> get events => _events.stream;

  Future<void> sendEmail(Email email) async {
    // Send...
    _events.add(EmailSentEvent(email));
  }
}

// ComposerController (producer)
class ComposerController {
  final EmailRepository _emailRepo;

  Future<void> sendEmail() async {
    await _emailRepo.sendEmail(email);
    // Event emitted automatically
  }
}

// EmailListController (consumer)
class EmailListController {
  @override
  void onInit() {
    _emailRepo.events.listen((event) {
      if (event is EmailSentEvent) {
        refreshList();
      }
    });
  }
}
```

---

### Use Case 3: Network Status (Simple State)

**Scenario**: Network goes offline, all controllers show offline UI

**Controllers Involved**:
- All controllers (react to status)

**Pattern**: ValueNotifier

**Implementation**:
```dart
class NetworkStatusService {
  final isOnline = ValueNotifier<bool>(true);

  void setOnlineStatus(bool online) {
    isOnline.value = online;
  }
}

// Any controller
Widget buildUI() {
  return ValueListenableBuilder<bool>(
    valueListenable: networkService.isOnline,
    builder: (context, isOnline, child) {
      if (!isOnline) return OfflineIndicator();
      return NormalUI();
    },
  );
}
```

---

### Use Case 4: Real-Time JMAP Updates (Stream)

**Scenario**: JMAP server pushes new email, email list updates

**Controllers Involved**:
- `EmailListController` (reacts)
- `UnreadCountController` (reacts)

**Pattern**: Repository + Stream

**Implementation**:
```dart
class EmailRepository {
  final _newEmails = StreamController<Email>.broadcast();
  Stream<Email> get newEmailStream => _newEmails.stream;

  void _onJMAPPush(Email email) {
    _newEmails.add(email);
  }
}

// EmailListController
class EmailListController {
  @override
  void onInit() {
    _emailRepo.newEmailStream.listen((email) {
      _prependEmail(email); // Add to list
    });
  }
}

// UnreadCountController
class UnreadCountController {
  @override
  void onInit() {
    _emailRepo.newEmailStream.listen((email) {
      if (!email.isRead) _incrementUnreadCount();
    });
  }
}
```

---

### Use Case 5: Search to Email List (Cross-Feature)

**Scenario**: User searches, results shown in email list

**Controllers Involved**:
- `SearchController` (produces query)
- `EmailListController` (consumes query)

**Pattern**: Shared Repository

**Implementation**:
```dart
class SearchStateRepository {
  final _searchQuery = BehaviorSubject<String?>();
  Stream<String?> get searchQueryStream => _searchQuery.stream;

  void setSearchQuery(String? query) => _searchQuery.add(query);
}

// SearchController
class SearchController {
  void onSearchSubmit(String query) {
    _searchState.setSearchQuery(query);
  }
}

// EmailListController
class EmailListController {
  @override
  void onInit() {
    _searchState.searchQueryStream.listen((query) {
      if (query != null) _searchEmails(query);
    });
  }
}
```

---

## Anti-Pattern Examples

### ❌ Anti-Pattern 1: Direct Controller Call

```dart
// BAD
class ControllerA {
  void doAction() {
    Get.find<ControllerB>().updateUI(); // Tight coupling!
  }
}
```

**Problems**:
- Hidden dependency
- Hard to test
- Order-dependent

**Fix**: Use repository + stream (see Use Case 1)

---

### ❌ Anti-Pattern 2: Global Event Bus

```dart
// BAD
eventBus.fire('email_sent', email); // String key, no type safety
```

**Problems**:
- No compile-time safety
- Hidden dependencies
- Memory leaks

**Fix**: Use typed event stream (see Use Case 2)

---

### ❌ Anti-Pattern 3: Static Global State

```dart
// BAD
class GlobalState {
  static Mailbox? selectedMailbox;
}
```

**Problems**:
- Hard to test
- No reactivity
- Race conditions

**Fix**: Use state repository (see Use Case 1)

---

## Pattern Selection Guide

### Choose Repository + Stream when:
- Multiple controllers need same data
- Data changes over time
- Need reactivity (auto-updates)
- Complex state (objects, lists)

### Choose Event Stream when:
- Notify actions (not state)
- Transient events
- Multiple event types
- Type safety important

### Choose ValueNotifier when:
- Simple single value
- Boolean, int, string, enum
- UI-only reactivity
- Minimal overhead needed

### Avoid:
- Controller-to-controller direct calls
- Global event bus
- Static global state
- String-based events
