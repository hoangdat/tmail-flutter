# Controller Split - Quick Reference

**Date**: 2024-12-24

---

## App-Level State (Singleton Repositories)

### What Is It?
State shared across entire app, lives from app start to app close.

### Examples
- `MailboxStateRepository` - Selected mailbox, mailbox list, filters
- `EmailStateRepository` - Email list, selected email, sort order
- `UserStateRepository` - Current user, account settings
- `NetworkService` - Online/offline status

### Role
- **Own** canonical state (single source of truth)
- **Expose** streams for state changes
- **Persist** across navigation
- **NO UI knowledge**

### Code Example
```dart
class MailboxStateRepository {
  // State (app-lifetime)
  final selectedMailbox = Rxn<Mailbox>();
  final mailboxList = <Mailbox>[].obs;

  // Stream (broadcast to all controllers)
  final _controller = StreamController<Mailbox?>.broadcast();
  Stream<Mailbox?> get selectedMailboxStream => _controller.stream;

  // Mutations
  void selectMailbox(Mailbox? m) {
    selectedMailbox.value = m;
    _controller.add(m); // Notify all listeners
  }

  void dispose() => _controller.close();
}
```

### Binding
```dart
class AppBinding extends Bindings {
  @override
  void dependencies() {
    // permanent: true → lives entire app
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

// main.dart
void main() {
  runApp(GetMaterialApp(
    initialBinding: AppBinding(), // Init once
    home: HomeView(),
  ));
}
```

---

## Feature-Level State (Scoped Repositories)

### What Is It?
State for specific feature, lives only while feature screen open.

### Examples
- `ComposerStateRepository` - Draft email, recipients, attachments
- `SearchStateRepository` - Search query, filters, results
- `SettingsStateRepository` - Temporary settings changes

### Role
- **Own** feature-specific state
- **Share** state between feature controllers
- **Disposed** when feature screen closed
- **Shorter lifetime** than app-level

### Code Example
```dart
class ComposerStateRepository {
  // Feature state (lives while composer open)
  final recipients = <EmailAddress>[].obs;
  final attachments = <Attachment>[].obs;
  final subject = ''.obs;
  final body = ''.obs;

  void dispose() {
    // Cleanup when composer closed
  }
}
```

### Binding
```dart
class ComposerBinding extends Bindings {
  @override
  void dependencies() {
    // NO permanent flag → disposed when route closed
    Get.put<ComposerStateRepository>(ComposerStateRepository());

    // Feature controllers
    Get.lazyPut(() => ComposerController(Get.find()));
    Get.lazyPut(() => RecipientController(Get.find()));
    Get.lazyPut(() => AttachmentController(Get.find()));
  }
}

// Route
GetPage(
  name: '/compose',
  page: () => ComposerScreen(),
  binding: ComposerBinding(), // Created when route opened
);

// When user closes composer → binding disposed → all controllers & repository cleaned up
```

---

## Controllers (Route-Scoped)

### What Is It?
Manage UI logic for specific screen/widget.

### Role
- **Handle** UI events (tap, scroll, input)
- **Subscribe** to repository streams
- **Update** UI state (loading, error, etc.)
- **Call** use cases
- **<200 lines** max

### Code Example
```dart
class EmailListController extends GetxController {
  // Dependencies (injected)
  final EmailStateRepository _emailState;
  final MailboxStateRepository _mailboxState;

  EmailListController(this._emailState, this._mailboxState);

  // UI state (controller-scoped, dies when controller disposed)
  final isLoading = false.obs;
  final scrollController = ScrollController();

  late StreamSubscription _mailboxSub;
  late StreamSubscription _emailSub;

  @override
  void onInit() {
    super.onInit();

    // Subscribe to app-level state
    _mailboxSub = _mailboxState.selectedMailboxStream.listen((mailbox) {
      if (mailbox != null) _loadEmails(mailbox);
    });

    _emailSub = _emailState.emailsStream.listen((emails) {
      update(); // Rebuild UI
    });
  }

  void _loadEmails(Mailbox mailbox) async {
    isLoading.value = true;
    // Call use case...
    isLoading.value = false;
  }

  @override
  void onClose() {
    // CRITICAL: Cleanup
    _mailboxSub.cancel();
    _emailSub.cancel();
    scrollController.dispose();
    super.onClose();
  }
}
```

### Binding
```dart
class EmailListBinding extends Bindings {
  @override
  void dependencies() {
    // Controller created, auto-disposed when route closed
    Get.lazyPut(() => EmailListController(
      Get.find<EmailStateRepository>(), // From AppBinding
      Get.find<MailboxStateRepository>(), // From AppBinding
    ));
  }
}
```

---

## Communication Patterns

### 1. Controller → App-Level State

```dart
class MailboxTreeController {
  final MailboxStateRepository _state; // App-level

  void onMailboxTap(Mailbox m) {
    _state.selectMailbox(m); // Update app state
  }
}
```

### 2. App-Level State → Controllers

```dart
class EmailListController {
  @override
  void onInit() {
    // Listen to app-level stream
    _mailboxState.selectedMailboxStream.listen((mailbox) {
      _loadEmails(mailbox); // React to change
    });
  }
}
```

### 3. Controller → Feature-Level State

```dart
class RecipientController {
  final ComposerStateRepository _state; // Feature-level

  void addRecipient(EmailAddress addr) {
    _state.recipients.add(addr); // Update feature state
  }
}
```

### 4. Feature-Level State → Controllers

```dart
class ComposerController {
  final ComposerStateRepository _state;

  @override
  void onInit() {
    // React to feature state changes
    ever(_state.recipients, (_) {
      _updateSendButtonState();
    });
  }
}
```

### 5. Controller → Controller (NEVER DIRECT!)

❌ **WRONG**:
```dart
class MailboxController {
  void select(Mailbox m) {
    Get.find<EmailListController>().loadEmails(m); // NO!
  }
}
```

✅ **RIGHT**:
```dart
class MailboxController {
  final MailboxStateRepository _state;

  void select(Mailbox m) {
    _state.selectMailbox(m); // Via repository
  }
}

class EmailListController {
  @override
  void onInit() {
    _state.selectedMailboxStream.listen((m) {
      loadEmails(m); // Reacts automatically
    });
  }
}
```

---

## UI State Management

### Who Manages UI State?

| State Type | Managed By | Scope | Example |
|------------|-----------|-------|---------|
| **App State** | App-level repository | App lifetime | selectedMailbox, user |
| **Feature State** | Feature repository | Feature lifetime | composer draft |
| **UI State** | Controller | Controller lifetime | isLoading, scrollOffset |

### UI State Example

```dart
class EmailListController {
  // UI state (only this controller cares)
  final isLoading = false.obs;
  final showFab = true.obs;
  final selectedItems = <Email>[].obs;
  final scrollController = ScrollController();

  // NOT shared, dies when controller disposed
}
```

---

## Rebuilding UI with Rx

### Pattern 1: Obx (Most Common)

```dart
class EmailListView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<EmailListController>();

    // Rebuilds when isLoading changes
    return Obx(() {
      if (controller.isLoading.value) {
        return CircularProgressIndicator();
      }

      return ListView.builder(
        itemCount: controller.emails.length,
        itemBuilder: (_, i) => EmailTile(controller.emails[i]),
      );
    });
  }
}
```

### Pattern 2: GetBuilder

```dart
class EmailListView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetBuilder<EmailListController>(
      builder: (controller) => ListView.builder(
        itemCount: controller.emails.length,
        itemBuilder: (_, i) => EmailTile(controller.emails[i]),
      ),
    );
  }
}
```

### Pattern 3: StreamBuilder (For Repository Streams)

```dart
class EmailCountWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final emailState = Get.find<EmailStateRepository>();

    return StreamBuilder<List<Email>>(
      stream: emailState.emailsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Text('0');
        return Text('${snapshot.data!.length}');
      },
    );
  }
}
```

### When UI Rebuilds

```
User action
    ↓
Controller updates Rx variable (e.g., isLoading.value = true)
    ↓
Obx() detects change
    ↓
Widget rebuilds automatically
```

---

## Binding Levels Summary

### App-Level Binding (AppBinding)

```dart
class AppBinding extends Bindings {
  @override
  void dependencies() {
    // Singletons (permanent: true)
    Get.put<MailboxStateRepository>(MailboxStateRepository(), permanent: true);
    Get.put<EmailStateRepository>(EmailStateRepository(), permanent: true);
    Get.put<NetworkService>(NetworkService(), permanent: true);

    // Data repositories
    Get.put<EmailRepository>(EmailRepository(), permanent: true);
    Get.put<MailboxRepository>(MailboxRepository(), permanent: true);
  }
}

// Initialized once in main.dart
void main() {
  runApp(GetMaterialApp(
    initialBinding: AppBinding(),
    home: HomeView(),
  ));
}
```

**Lifecycle**: App start → App close
**Contains**: App-wide state repositories, services, data repositories

---

### Route-Level Binding (Per Screen)

```dart
class EmailListBinding extends Bindings {
  @override
  void dependencies() {
    // Controllers (auto-disposed when route closed)
    Get.lazyPut(() => EmailListController(
      Get.find<EmailStateRepository>(), // From AppBinding
      Get.find<MailboxStateRepository>(), // From AppBinding
    ));
  }
}

// Route definition
GetPage(
  name: '/emails',
  page: () => EmailListView(),
  binding: EmailListBinding(),
);
```

**Lifecycle**: Route open → Route close
**Contains**: Screen controllers

---

### Feature-Level Binding (Per Feature Module)

```dart
class ComposerBinding extends Bindings {
  @override
  void dependencies() {
    // Feature repository (scoped)
    Get.put<ComposerStateRepository>(ComposerStateRepository());

    // Feature controllers
    Get.lazyPut(() => ComposerController(Get.find()));
    Get.lazyPut(() => RecipientController(Get.find()));
    Get.lazyPut(() => AttachmentController(Get.find()));
    Get.lazyPut(() => EditorController(Get.find()));
  }
}

// Route
GetPage(
  name: '/compose',
  page: () => ComposerScreen(),
  binding: ComposerBinding(),
);
```

**Lifecycle**: Feature screen open → Feature screen close
**Contains**: Feature repository + feature controllers

---

## Complete Flow Example

### User Selects Mailbox

```
1. User taps "Inbox" in MailboxTreeView
        ↓
2. MailboxTreeController.onMailboxTap(inbox)
        ↓
3. _mailboxState.selectMailbox(inbox)  [App-level repository]
        ↓
4. selectedMailboxStream.add(inbox)  [Broadcast]
        ↓
5. EmailListController listening → _loadEmails(inbox)
        ↓
6. EmailDetailController listening → _clear()
        ↓
7. UI rebuilds via Obx()
```

**Key**: Controllers never call each other. All via repository streams.

---

## Quick Decision Matrix

| Question | Answer |
|----------|--------|
| State shared across entire app? | **App-level repository** (permanent: true) |
| State for specific feature only? | **Feature repository** (scoped binding) |
| UI state (loading, scroll, etc.)? | **Controller** Rx variables |
| How controllers communicate? | Via **repository streams** (never direct) |
| When to use AppBinding? | **Once** in main.dart for singletons |
| When to use route binding? | **Per screen** for controllers |
| When to use feature binding? | **Per feature module** for feature state + controllers |
| How UI rebuilds? | **Obx()** or **GetBuilder** wraps widget |
| When controller disposed? | When **route closed** (auto by GetX) |
| How to cleanup? | **onClose()** cancel subscriptions, dispose resources |

---

## Cheat Sheet

### Creating App-Level State

```dart
// 1. Create repository
class MyStateRepository {
  final myData = Rxn<Data>();
  final _controller = StreamController<Data?>.broadcast();
  Stream<Data?> get stream => _controller.stream;

  void updateData(Data d) {
    myData.value = d;
    _controller.add(d);
  }
}

// 2. Register in AppBinding
Get.put<MyStateRepository>(MyStateRepository(), permanent: true);

// 3. Inject in controllers
class MyController extends GetxController {
  final MyStateRepository _state;
  MyController(this._state);
}
```

### Creating Feature-Level State

```dart
// 1. Create repository
class FeatureStateRepository {
  final data = <Item>[].obs;
}

// 2. Register in feature binding
class FeatureBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<FeatureStateRepository>(FeatureStateRepository()); // No permanent
    Get.lazyPut(() => FeatureController(Get.find()));
  }
}
```

### Controller Template

```dart
class MyController extends GetxController {
  final MyStateRepository _state;

  MyController(this._state);

  // UI state
  final isLoading = false.obs;

  // Subscriptions
  late StreamSubscription _sub;

  @override
  void onInit() {
    super.onInit();
    _sub = _state.stream.listen(_onStateChanged);
  }

  void _onStateChanged(Data? data) {
    // React to state
  }

  @override
  void onClose() {
    _sub.cancel(); // CRITICAL
    super.onClose();
  }
}
```

---

## Summary

1. **App-level state** = Singletons (permanent: true) in AppBinding
2. **Feature-level state** = Scoped repositories in feature binding
3. **Controllers** = Route-scoped, auto-disposed
4. **Communication** = Via repository streams (NEVER direct controller calls)
5. **UI state** = Controller Rx variables
6. **UI rebuilds** = Obx() wraps reactive widgets
7. **Bindings** = AppBinding (once) + Route/Feature bindings (per screen/feature)

**Rule of thumb**: If state needed by multiple controllers → repository. If UI-only → controller.
