# Nested Views Pattern - View on View with Multiple Controllers

**Parent**: [Controller Refactoring Plan](./plan.md)

---

## The Confusion Clarified

**Question**: When we separate controllers, how do nested views (view inside view) work?

**Answer**: Each widget can have its own controller, OR multiple widgets share one controller, OR nested widgets access parent controller via Get.find(). Let me show you all patterns.

---

## Pattern 1: Nested Views, Each With Own Controller

### Scenario: Composer Screen with Attachment Panel

```
ComposerScreen (ComposerController)
    ├─ RecipientField (RecipientController)
    ├─ SubjectField (ComposerController - same)
    ├─ EditorArea (EditorController)
    └─ AttachmentPanel (AttachmentController)
```

### Implementation

```dart
// Parent View
class ComposerScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetBuilder<ComposerController>(
      builder: (controller) => Scaffold(
        appBar: AppBar(title: Text('New Email')),
        body: Column(
          children: [
            RecipientField(),        // ← Has RecipientController
            SubjectField(),          // ← Uses ComposerController
            Expanded(child: EditorArea()),  // ← Has EditorController
            AttachmentPanel(),       // ← Has AttachmentController
          ],
        ),
      ),
    );
  }
}

// Child View 1 - Own Controller
class RecipientField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Gets RecipientController from binding
    return GetBuilder<RecipientController>(
      builder: (controller) => TextField(
        onChanged: controller.onRecipientChanged,
        decoration: InputDecoration(
          hintText: 'To',
          suffixIcon: Obx(() => controller.isSearching.value
              ? CircularProgressIndicator()
              : Icon(Icons.search),
          ),
        ),
      ),
    );
  }
}

// Child View 2 - Own Controller
class AttachmentPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Gets AttachmentController from binding
    return GetBuilder<AttachmentController>(
      builder: (controller) => Container(
        height: 120,
        child: Obx(() => ListView.builder(
          itemCount: controller.attachments.length,
          itemBuilder: (_, i) => AttachmentTile(
            controller.attachments[i],
            onRemove: () => controller.removeAttachment(i),
          ),
        )),
      ),
    );
  }
}

// Child View 3 - Shares Parent Controller
class SubjectField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Uses ComposerController (parent)
    final controller = Get.find<ComposerController>();

    return TextField(
      onChanged: controller.onSubjectChanged,
      decoration: InputDecoration(hintText: 'Subject'),
    );
  }
}
```

### Binding Setup

```dart
class ComposerBinding extends Bindings {
  @override
  void dependencies() {
    // Feature-scoped state repository
    Get.put<ComposerStateRepository>(ComposerStateRepository());

    // All controllers registered (available to child widgets)
    Get.lazyPut(() => ComposerController(Get.find()));
    Get.lazyPut(() => RecipientController(Get.find()));
    Get.lazyPut(() => EditorController(Get.find()));
    Get.lazyPut(() => AttachmentController(Get.find()));
  }
}
```

### How They Communicate

```dart
// Shared state via repository
class ComposerStateRepository {
  final recipients = <EmailAddress>[].obs;
  final attachments = <Attachment>[].obs;
  final editorContent = ''.obs;
}

// RecipientController updates shared state
class RecipientController extends GetxController {
  final ComposerStateRepository _state;

  void addRecipient(EmailAddress addr) {
    _state.recipients.add(addr); // ✅ Updates shared state
  }
}

// ComposerController reads shared state
class ComposerController extends GetxController {
  final ComposerStateRepository _state;

  void send() {
    final email = Email(
      to: _state.recipients,        // ✅ Reads from repository
      attachments: _state.attachments,
      body: _state.editorContent,
    );
    _sendUseCase.execute(email);
  }
}

// AttachmentController updates shared state
class AttachmentController extends GetxController {
  final ComposerStateRepository _state;

  void addAttachment(File file) async {
    final attachment = await _uploadUseCase.execute(file);
    _state.attachments.add(attachment); // ✅ Updates shared state
  }
}
```

---

## Pattern 2: Parent-Child Controller Access

### Scenario: Email List with Detail Panel (Master-Detail)

```
EmailDashboard (DashboardController)
    ├─ EmailList (EmailListController)
    └─ EmailDetailPanel (EmailDetailController)
```

### Implementation

```dart
// Parent View
class EmailDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetBuilder<DashboardController>(
      builder: (dashController) => Row(
        children: [
          // Left: Email List
          Expanded(
            flex: 1,
            child: EmailList(), // ← Has EmailListController
          ),

          // Right: Detail Panel
          Expanded(
            flex: 2,
            child: EmailDetailPanel(), // ← Has EmailDetailController
          ),
        ],
      ),
    );
  }
}

// Child View 1
class EmailList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<EmailListController>();

    return Obx(() => ListView.builder(
      itemCount: controller.emails.length,
      itemBuilder: (_, i) => EmailTile(
        controller.emails[i],
        onTap: () => controller.selectEmail(controller.emails[i]),
      ),
    ));
  }
}

// Child View 2
class EmailDetailPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<EmailDetailController>();

    return Obx(() {
      final email = controller.selectedEmail.value;
      if (email == null) return Center(child: Text('Select an email'));
      return EmailDetailView(email);
    });
  }
}
```

### Communication via Repository

```dart
// Shared state
class EmailStateRepository {
  final selectedEmail = Rxn<Email>();
  final _controller = StreamController<Email?>.broadcast();
  Stream<Email?> get selectedEmailStream => _controller.stream;

  void selectEmail(Email? email) {
    selectedEmail.value = email;
    _controller.add(email);
  }
}

// EmailListController updates selection
class EmailListController extends GetxController {
  final EmailStateRepository _state;

  void selectEmail(Email email) {
    _state.selectEmail(email); // ✅ Updates shared state
  }
}

// EmailDetailController reacts to selection
class EmailDetailController extends GetxController {
  final EmailStateRepository _state;
  late StreamSubscription _sub;

  final selectedEmail = Rxn<Email>();

  @override
  void onInit() {
    // Listen to repository stream
    _sub = _state.selectedEmailStream.listen((email) {
      selectedEmail.value = email; // ✅ Updates local view state
      if (email != null) _loadEmailDetails(email);
    });
  }

  @override
  void onClose() {
    _sub.cancel();
  }
}
```

---

## Pattern 3: Deeply Nested Widgets (Widget Tree)

### Scenario: Email List → Email Tile → Action Buttons

```
EmailListScreen (EmailListController)
    └─ EmailList Widget
        └─ EmailTile Widget (multiple instances)
            └─ EmailActionButtons Widget
```

### Option A: Pass Controller Down (Simple)

```dart
class EmailListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<EmailListController>();

    return Obx(() => ListView.builder(
      itemCount: controller.emails.length,
      itemBuilder: (_, i) => EmailTile(
        email: controller.emails[i],
        controller: controller, // ✅ Pass controller explicitly
      ),
    ));
  }
}

class EmailTile extends StatelessWidget {
  final Email email;
  final EmailListController controller;

  EmailTile({required this.email, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(email.subject),
      trailing: EmailActionButtons(
        email: email,
        controller: controller, // ✅ Pass down again
      ),
    );
  }
}

class EmailActionButtons extends StatelessWidget {
  final Email email;
  final EmailListController controller;

  EmailActionButtons({required this.email, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.delete),
          onPressed: () => controller.deleteEmail(email), // ✅ Use parent controller
        ),
        IconButton(
          icon: Icon(Icons.archive),
          onPressed: () => controller.archiveEmail(email),
        ),
      ],
    );
  }
}
```

### Option B: Get.find() in Child (Convenience)

```dart
class EmailTile extends StatelessWidget {
  final Email email;

  EmailTile({required this.email});

  @override
  Widget build(BuildContext context) {
    // Get parent controller (no need to pass)
    final controller = Get.find<EmailListController>();

    return ListTile(
      title: Text(email.subject),
      trailing: Row(
        children: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () => controller.deleteEmail(email), // ✅ Direct access
          ),
        ],
      ),
    );
  }
}
```

---

## Pattern 4: Tab Views (Multiple Controllers in TabBarView)

### Scenario: Email Dashboard with Tabs

```
DashboardScreen (DashboardController)
    └─ TabBarView
        ├─ EmailListTab (EmailListController)
        ├─ CalendarTab (CalendarController)
        └─ ContactsTab (ContactsController)
```

### Implementation

```dart
class DashboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dashController = Get.find<DashboardController>();

    return Scaffold(
      body: TabBarView(
        controller: dashController.tabController,
        children: [
          EmailListTab(),    // ← Has EmailListController
          CalendarTab(),     // ← Has CalendarController
          ContactsTab(),     // ← Has ContactsController
        ],
      ),
    );
  }
}

// Each tab has own controller
class EmailListTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetBuilder<EmailListController>(
      init: Get.find<EmailListController>(), // Get from binding
      builder: (controller) => Obx(() => ListView.builder(
        itemCount: controller.emails.length,
        itemBuilder: (_, i) => EmailTile(controller.emails[i]),
      )),
    );
  }
}

class CalendarTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetBuilder<CalendarController>(
      init: Get.find<CalendarController>(),
      builder: (controller) => Obx(() => CalendarView(controller.events)),
    );
  }
}
```

### Binding Registers All Tab Controllers

```dart
class DashboardBinding extends Bindings {
  @override
  void dependencies() {
    // Dashboard controller
    Get.lazyPut(() => DashboardController());

    // Tab controllers (all available)
    Get.lazyPut(() => EmailListController(Get.find()));
    Get.lazyPut(() => CalendarController(Get.find()));
    Get.lazyPut(() => ContactsController(Get.find()));
  }
}
```

---

## Pattern 5: Modal/Dialog with Own Controller

### Scenario: Email List → Open Composer Dialog

```dart
class EmailListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<EmailListController>();

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showComposerDialog(context),
        child: Icon(Icons.edit),
      ),
      body: EmailList(),
    );
  }

  void _showComposerDialog(BuildContext context) {
    // Create temporary binding for dialog
    Get.dialog(
      ComposerDialog(),
      binding: ComposerDialogBinding(), // ✅ Dialog has own binding
    );
  }
}

// Dialog with own controller
class ComposerDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ComposerController>();

    return Dialog(
      child: Container(
        width: 600,
        height: 400,
        child: Column(
          children: [
            TextField(
              onChanged: controller.onSubjectChanged,
              decoration: InputDecoration(hintText: 'Subject'),
            ),
            Expanded(
              child: TextField(
                onChanged: controller.onBodyChanged,
                maxLines: null,
              ),
            ),
            ElevatedButton(
              onPressed: () {
                controller.send();
                Get.back(); // Close dialog
              },
              child: Text('Send'),
            ),
          ],
        ),
      ),
    );
  }
}

// Temporary binding (auto-disposed when dialog closed)
class ComposerDialogBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<ComposerController>(ComposerController(Get.find()));
  }
}
```

---

## Decision Matrix: Which Pattern to Use?

| Scenario | Pattern | Example |
|----------|---------|---------|
| Nested widgets, different concerns | Each widget has own controller | Composer with Recipient/Editor/Attachment |
| Parent-child relationship | Shared repository + streams | Email list → Detail panel |
| Simple child widgets | Pass controller as parameter | Email tile with action buttons |
| Deep nesting (>3 levels) | Get.find() in child | Action buttons deep in tree |
| Tabs/Pages | Each tab has own controller | Dashboard with Email/Calendar/Contacts |
| Modals/Dialogs | Dialog has own binding | Composer dialog |

---

## Common Mistake: Controller Coupling

### ❌ WRONG - Child Directly Calls Parent Controller

```dart
class AttachmentPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final parentController = Get.find<ComposerController>();

    return IconButton(
      onPressed: () {
        // ❌ Tight coupling to parent controller
        parentController.addAttachment();
      },
    );
  }
}
```

### ✅ RIGHT - Child Updates Shared Repository

```dart
class AttachmentPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AttachmentController>();

    return IconButton(
      onPressed: () {
        // ✅ Updates shared repository
        controller.addAttachment();
      },
    );
  }
}

// AttachmentController
class AttachmentController extends GetxController {
  final ComposerStateRepository _state;

  void addAttachment() {
    _state.attachments.add(...); // ✅ Repository update
  }
}

// ComposerController reacts automatically
class ComposerController extends GetxController {
  @override
  void onInit() {
    // Listen to attachment changes
    ever(_state.attachments, (_) {
      update(); // Rebuild UI if needed
    });
  }
}
```

---

## Summary: View Management Rules

1. **Each widget CAN have own controller** (registered in binding)
2. **Nested widgets access controllers via** `Get.find<ControllerType>()`
3. **Controllers communicate via** shared repository (not direct calls)
4. **Simple widgets** can share parent controller (pass as parameter)
5. **Complex nested features** should have own controller + repository
6. **Dialogs/Modals** can have temporary bindings (auto-disposed)

**Key**: Widgets are just UI. Controllers manage logic. Repositories manage state. All connected via GetX bindings.
