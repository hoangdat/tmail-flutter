# UI Reactivity Mechanisms

**Parent**: [Controller Refactoring Plan](./plan.md)

---

## Making UI React to State Changes

### Reactive Patterns in GetX

#### 1. Obx() - Reactive Widget Builder

```dart
class EmailListController extends GetxController {
  final emails = <Email>[].obs; // Observable list
  final isLoading = false.obs;
}

// UI automatically rebuilds when emails changes
Obx(() {
  if (controller.isLoading.value) {
    return CircularProgressIndicator();
  }
  return ListView.builder(
    itemCount: controller.emails.length,
    itemBuilder: (context, index) => EmailTile(controller.emails[index]),
  );
});
```

#### 2. GetBuilder - Explicit Rebuild

```dart
class EmailDetailController extends GetxController {
  Email? email;

  void loadEmail(EmailId id) async {
    email = await _useCase.execute(id);
    update(); // Trigger rebuild
  }
}

GetBuilder<EmailDetailController>(
  builder: (controller) {
    if (controller.email == null) return LoadingWidget();
    return EmailDetailWidget(controller.email!);
  },
);
```

#### 3. StreamBuilder - Direct Stream Subscription

```dart
class MailboxStateRepository {
  final _controller = StreamController<Mailbox?>.broadcast();
  Stream<Mailbox?> get selectedMailboxStream => _controller.stream;
}

StreamBuilder<Mailbox?>(
  stream: mailboxState.selectedMailboxStream,
  builder: (context, snapshot) {
    if (!snapshot.hasData) return SizedBox.shrink();
    return MailboxHeader(snapshot.data!);
  },
);
```

#### 4. ValueListenableBuilder - Simple Values

```dart
class NetworkService {
  final isOnline = ValueNotifier<bool>(true);
}

ValueListenableBuilder<bool>(
  valueListenable: networkService.isOnline,
  builder: (context, isOnline, child) {
    if (!isOnline) return OfflineBanner();
    return child!;
  },
  child: EmailList(),
);
```

---

## Reactivity Best Practices

### ✅ DO: Granular Reactive Widgets

```dart
// Good - only rebuilds email count
class EmailCountWidget extends StatelessWidget {
  final EmailStateRepository state;

  @override
  Widget build(BuildContext context) {
    return Obx(() => Text('${state.emails.length} emails'));
  }
}

// Good - only rebuilds when loading changes
class LoadingIndicator extends StatelessWidget {
  final EmailListController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.isLoading.value) return SizedBox.shrink();
      return CircularProgressIndicator();
    });
  }
}
```

### ❌ DON'T: Coarse Reactive Widgets

```dart
// Bad - rebuilds entire screen on any state change
Obx(() {
  return Scaffold(
    appBar: AppBar(title: Text(controller.title.value)),
    body: Column(
      children: [
        EmailList(controller.emails), // Rebuilds unnecessarily
        LoadingIndicator(controller.isLoading.value),
        ErrorBanner(controller.error.value),
      ],
    ),
  );
});
```

---

## Cross-Controller UI Reactivity

### Scenario: Email List Reacts to Mailbox Selection

```dart
// Repository emits mailbox changes
class MailboxStateRepository {
  final _selectedController = StreamController<Mailbox?>.broadcast();
  Stream<Mailbox?> get selectedMailboxStream => _selectedController.stream;

  void selectMailbox(Mailbox m) {
    _selectedController.add(m);
  }
}

// EmailListController reacts
class EmailListController {
  final MailboxStateRepository _mailboxState;
  late StreamSubscription _sub;

  final emails = <Email>[].obs;

  @override
  void onInit() {
    _sub = _mailboxState.selectedMailboxStream.listen((mailbox) {
      if (mailbox != null) _loadEmails(mailbox);
    });
  }

  Future<void> _loadEmails(Mailbox mailbox) async {
    emails.value = await _useCase.execute(mailbox.id);
  }

  @override
  void onClose() {
    _sub.cancel();
  }
}

// UI reacts to emails changes
Obx(() {
  return ListView.builder(
    itemCount: controller.emails.length,
    itemBuilder: (_, i) => EmailTile(controller.emails[i]),
  );
});
```

### Flow

```
User taps Inbox
    ↓
MailboxListController.selectMailbox(inbox)
    ↓
MailboxStateRepository.selectMailbox(inbox)
    ↓
selectedMailboxStream.add(inbox)
    ↓
EmailListController listening → _loadEmails(inbox)
    ↓
EmailListController.emails.value = [...]
    ↓
Obx(() => ListView) rebuilds with new emails
```

---

## Optimizing Reactivity

### 1. Debounce Frequent Updates

```dart
class SearchController {
  final query = ''.obs;
  Timer? _debounce;

  void onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: 300), () {
      query.value = value; // Only update after 300ms pause
    });
  }
}
```

### 2. Throttle Scroll Updates

```dart
class EmailListController {
  final scrollController = ScrollController();

  @override
  void onInit() {
    scrollController.addListener(_onScroll);
  }

  DateTime? _lastScrollUpdate;

  void _onScroll() {
    final now = DateTime.now();
    if (_lastScrollUpdate != null &&
        now.difference(_lastScrollUpdate!) < Duration(milliseconds: 100)) {
      return; // Skip if within 100ms
    }

    _lastScrollUpdate = now;
    _checkLoadMore(); // Throttled
  }
}
```

### 3. Lazy Stream Transformations

```dart
class EmailStateRepository {
  Stream<List<Email>> get filteredEmailsStream {
    return emailsStream
        .debounceTime(Duration(milliseconds: 300))
        .map((emails) => emails.where((e) => e.isUnread).toList())
        .distinct(); // Only emit if different from previous
  }
}
```

---

## Conditional Reactivity

### Pattern: Listen to State Only When Needed

```dart
class EmailDetailController {
  StreamSubscription? _emailUpdateSub;

  void openEmail(EmailId id) {
    // Start listening when email opened
    _emailUpdateSub = _emailState.emailUpdatesStream
        .where((update) => update.id == id)
        .listen(_onEmailUpdated);
  }

  void closeEmail() {
    // Stop listening when email closed
    _emailUpdateSub?.cancel();
    _emailUpdateSub = null;
  }
}
```

---

## Error Handling in Reactive UI

```dart
class EmailListController {
  final viewState = Rx<ViewState>(ViewState.idle());

  Future<void> load() async {
    viewState.value = ViewState.loading();

    try {
      final emails = await _useCase.execute();
      viewState.value = ViewState.success(emails);
    } catch (e) {
      viewState.value = ViewState.error(e.toString());
    }
  }
}

// UI handles all states
Obx(() {
  return viewState.value.when(
    idle: () => SizedBox.shrink(),
    loading: () => LoadingWidget(),
    success: (emails) => EmailList(emails),
    error: (message) => ErrorWidget(message),
  );
});
```

---

## Testing Reactive UI

```dart
testWidgets('Email list rebuilds when emails change', (tester) async {
  final controller = EmailListController(mockRepo, mockUseCase);

  await tester.pumpWidget(
    MaterialApp(
      home: Obx(() => ListView.builder(
        itemCount: controller.emails.length,
        itemBuilder: (_, i) => Text(controller.emails[i].subject),
      )),
    ),
  );

  // Initially empty
  expect(find.byType(ListView), findsOneWidget);
  expect(find.text('Test Email'), findsNothing);

  // Add emails
  controller.emails.add(Email(subject: 'Test Email'));
  await tester.pump(); // Trigger rebuild

  // UI updated
  expect(find.text('Test Email'), findsOneWidget);
});
```

---

## Summary

| Pattern | Use Case | Rebuild Scope |
|---------|----------|---------------|
| Obx() | Reactive state | Only Obx widget |
| GetBuilder | Manual rebuild | Entire builder |
| StreamBuilder | Direct stream | Only StreamBuilder |
| ValueListenableBuilder | Simple values | Only builder |

**Performance Tips**:
1. Keep Obx() widgets small (rebuild only necessary parts)
2. Use debounce/throttle for frequent updates
3. Cancel subscriptions in onClose()
4. Use distinct() to prevent duplicate rebuilds
5. Avoid nested Obx() (use GetBuilder for outer scope)
