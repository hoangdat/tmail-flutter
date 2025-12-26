# GetX Scoped Binding Strategy

**Parent**: [Controller Refactoring Plan](./plan.md)

---

## Why GetX Bindings Over GetIt

**GetX Bindings Advantages**:
- Scoped lifecycle (auto-dispose when route closed)
- Built-in dependency management
- Lazy initialization
- No boilerplate DI setup
- Works seamlessly with GetX routing

**Strategy**: Use GetX bindings for dependency injection, repositories for state management.

---

## GetX Binding Architecture

### Binding Types

#### 1. Singleton Bindings (App Lifetime)
For state repositories shared across entire app.

```dart
class AppBinding extends Bindings {
  @override
  void dependencies() {
    // Singletons - live entire app lifetime
    Get.put<MailboxStateRepository>(MailboxStateRepository(), permanent: true);
    Get.put<EmailStateRepository>(EmailStateRepository(), permanent: true);
    Get.put<NetworkService>(NetworkService(), permanent: true);

    // Data repositories (also singletons)
    Get.put<EmailRepository>(EmailRepository(), permanent: true);
    Get.put<MailboxRepository>(MailboxRepository(), permanent: true);
  }
}

// In main.dart
void main() {
  runApp(GetMaterialApp(
    initialBinding: AppBinding(), // Initialize app-level dependencies
    home: HomeView(),
  ));
}
```

#### 2. Scoped Bindings (Route Lifetime)
For controllers that should be created/destroyed with routes.

```dart
class EmailListBinding extends Bindings {
  @override
  void dependencies() {
    // Lazy - created when first accessed, destroyed when route closed
    Get.lazyPut<EmailListController>(
      () => EmailListController(
        Get.find<EmailStateRepository>(), // Inject singleton repository
        Get.find<MailboxStateRepository>(),
      ),
    );
  }
}

// Route definition
GetPage(
  name: '/emails',
  page: () => EmailListView(),
  binding: EmailListBinding(), // Scoped to this route
);
```

#### 3. Feature Bindings (Feature Module Lifetime)
For controllers in feature modules (e.g., composer).

```dart
class ComposerBinding extends Bindings {
  @override
  void dependencies() {
    // Shared state for composer feature
    Get.put<ComposerStateRepository>(ComposerStateRepository());

    // All composer controllers (destroyed together when composer closed)
    Get.lazyPut(() => ComposerController(Get.find()));
    Get.lazyPut(() => AttachmentController(Get.find()));
    Get.lazyPut(() => RecipientController(Get.find()));
    Get.lazyPut(() => EditorController(Get.find()));
  }
}
```

---

## Dependency Injection Pattern

### Pattern: Constructor Injection via Get.find()

```dart
// Repository (singleton, permanent binding)
class EmailStateRepository {
  final emails = <Email>[].obs;
  final _controller = StreamController<List<Email>>.broadcast();
  Stream<List<Email>> get emailsStream => _controller.stream;

  void setEmails(List<Email> emails) {
    this.emails.value = emails;
    _controller.add(emails);
  }

  void dispose() => _controller.close();
}

// Controller (scoped binding, auto-disposed)
class EmailListController extends GetxController {
  // Dependencies injected via constructor
  final EmailStateRepository _emailState;
  final MailboxStateRepository _mailboxState;

  // Constructor receives dependencies from binding
  EmailListController(this._emailState, this._mailboxState);

  late StreamSubscription _sub;

  @override
  void onInit() {
    super.onInit();
    // Subscribe to mailbox changes
    _sub = _mailboxState.selectedMailboxStream.listen((mailbox) {
      if (mailbox != null) _loadEmails(mailbox);
    });
  }

  void _loadEmails(Mailbox mailbox) {
    // Use repository
    _emailState.setEmails([...]); // Updates all listeners
  }

  @override
  void onClose() {
    _sub.cancel(); // Auto-called when route closed
    super.onClose();
  }
}

// Binding (scoped to route)
class EmailListBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => EmailListController(
      Get.find<EmailStateRepository>(), // Inject from app binding
      Get.find<MailboxStateRepository>(),
    ));
  }
}
```

---

## Scoped Binding Examples

### Example 1: Mailbox Feature

```dart
class MailboxBinding extends Bindings {
  @override
  void dependencies() {
    // Controllers for mailbox screen
    Get.lazyPut(() => MailboxTreeController(
      Get.find<MailboxStateRepository>(),
    ));

    Get.lazyPut(() => MailboxActionsController(
      Get.find<MailboxStateRepository>(),
      Get.find<MailboxRepository>(),
    ));
  }
}

// When user navigates to mailbox screen
Get.to(
  () => MailboxView(),
  binding: MailboxBinding(), // Created
);

// When user navigates away
// → binding.onClose() called
// → controllers disposed automatically
```

### Example 2: Composer Feature (Multiple Controllers)

```dart
class ComposerBinding extends Bindings {
  @override
  void dependencies() {
    // Feature-scoped state (lives with composer screen)
    Get.put<ComposerStateRepository>(ComposerStateRepository());

    // Multiple controllers share ComposerStateRepository
    Get.lazyPut(() => ComposerController(Get.find()));
    Get.lazyPut(() => AttachmentController(Get.find()));
    Get.lazyPut(() => RecipientController(Get.find()));
    Get.lazyPut(() => EditorController(Get.find()));
    Get.lazyPut(() => DraftController(Get.find()));
  }
}

// All 5 controllers + state repository disposed when composer closed
```

### Example 3: Nested Scopes (Dashboard → Email Detail)

```dart
// Dashboard binding (parent scope)
class DashboardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => NavigationController(Get.find()));
    Get.lazyPut(() => EmailListController(Get.find(), Get.find()));
  }
}

// Email detail binding (child scope)
class EmailDetailBinding extends Bindings {
  @override
  void dependencies() {
    // Only email detail controller (parent scope still alive)
    Get.lazyPut(() => EmailDetailController(
      Get.find<EmailStateRepository>(), // From app binding
      Get.find<EmailRepository>(), // From app binding
    ));
  }
}

// Navigation preserves parent scope
Get.to(
  () => EmailDetailView(),
  binding: EmailDetailBinding(), // Child binding
);
// Dashboard controllers still alive
```

---

## Replacing Get.find() Direct Calls

### Before (Anti-pattern - Service Locator in Controller)

```dart
class MailboxController extends GetxController {
  // Hidden dependency - discovered at runtime
  final dashboard = Get.find<MailboxDashBoardController>();

  void selectMailbox(Mailbox m) {
    dashboard.setSelectedMailbox(m); // Tight coupling
  }
}
```

### After (Pattern - Constructor Injection via Binding)

```dart
class MailboxController extends GetxController {
  // Explicit dependency - visible in constructor
  final MailboxStateRepository _mailboxState;

  MailboxController(this._mailboxState); // Injected by binding

  void selectMailbox(Mailbox m) {
    _mailboxState.selectMailbox(m); // Loose coupling
  }
}

// Binding provides dependencies
class MailboxBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => MailboxController(
      Get.find<MailboxStateRepository>(), // Explicit injection
    ));
  }
}
```

---

## Repository Lifecycle Management

### App-Level Repositories (Permanent)

```dart
class AppBinding extends Bindings {
  @override
  void dependencies() {
    // permanent: true → never disposed
    Get.put<MailboxStateRepository>(
      MailboxStateRepository(),
      permanent: true,
    );

    Get.put<EmailStateRepository>(
      EmailStateRepository(),
      permanent: true,
    );
  }
}
```

### Feature-Level Repositories (Scoped)

```dart
class ComposerBinding extends Bindings {
  @override
  void dependencies() {
    // No permanent flag → disposed when binding removed
    Get.put<ComposerStateRepository>(
      ComposerStateRepository(),
    );
  }

  @override
  void onClose() {
    // Manually dispose if needed
    Get.find<ComposerStateRepository>().dispose();
    super.onClose();
  }
}
```

---

## Testing with GetX Bindings

```dart
testWidgets('EmailListController loads emails', (tester) async {
  // Setup test binding
  Get.testMode = true;

  // Mock repositories
  final mockEmailState = MockEmailStateRepository();
  final mockMailboxState = MockMailboxStateRepository();

  // Inject mocks via binding
  Get.put<EmailStateRepository>(mockEmailState);
  Get.put<MailboxStateRepository>(mockMailboxState);

  // Create controller with mocked dependencies
  final controller = EmailListController(
    Get.find<EmailStateRepository>(),
    Get.find<MailboxStateRepository>(),
  );

  // Test...

  // Cleanup
  Get.reset();
});
```

---

## Migration from Current Architecture

### Step 1: Create Bindings for Each Route

```dart
// Replace direct controller instantiation
// Before:
Get.put(MailboxController());

// After:
class MailboxBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => MailboxController(Get.find()));
  }
}
```

### Step 2: Extract State to Repositories

```dart
// Before: MailboxDashBoardController holds state
class MailboxDashBoardController {
  final selectedMailbox = Rxn<Mailbox>();
  // 40+ properties...
}

// After: State repository
class MailboxStateRepository {
  final selectedMailbox = Rxn<Mailbox>();
  Stream<Mailbox?> get selectedMailboxStream => _controller.stream;
}

// Register in AppBinding
Get.put<MailboxStateRepository>(MailboxStateRepository(), permanent: true);
```

### Step 3: Inject Repositories via Constructor

```dart
// Before:
class ThreadController {
  void load() {
    final dashboard = Get.find<MailboxDashBoardController>();
    dashboard.selectedMailbox; // Direct access
  }
}

// After:
class ThreadController {
  final MailboxStateRepository _mailboxState;

  ThreadController(this._mailboxState); // Injected

  void load() {
    final mailbox = _mailboxState.selectedMailbox; // Via repository
  }
}

// Binding handles injection
class ThreadBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => ThreadController(Get.find()));
  }
}
```

---

## Summary: GetX Binding Best Practices

| Scope | Binding Type | Use Case | Example |
|-------|-------------|----------|---------|
| App | permanent: true | App-wide state | MailboxStateRepository |
| Feature | Get.put() | Feature state | ComposerStateRepository |
| Route | Get.lazyPut() | Screen controller | EmailListController |

**Key Rules**:
1. **App state** → AppBinding with permanent: true
2. **Feature state** → Feature binding with Get.put()
3. **Controllers** → Route binding with Get.lazyPut()
4. **Always** use constructor injection (no Get.find() in controllers)
5. **Always** dispose streams in onClose()
6. **Never** access controllers directly (use repositories)
