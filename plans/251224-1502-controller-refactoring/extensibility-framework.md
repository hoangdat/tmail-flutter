# Extensibility Framework (Open-Closed Principle)

**Parent**: [Controller Refactoring Plan](./plan.md)

---

## Open-Closed Principle

**Definition**: Software entities should be open for extension, closed for modification.

**Goal**: Add new features without changing existing controller code.

---

## Strategies for Extensibility

### 1. Strategy Pattern for Use Cases

**Problem**: Adding new email actions requires modifying controller.

**Solution**: Abstract email actions into strategies.

```dart
// Abstract strategy
abstract class EmailActionStrategy {
  Future<Either<Failure, Success>> execute(Email email);
}

// Concrete strategies
class MarkAsReadStrategy implements EmailActionStrategy {
  final MarkAsReadUseCase _useCase;

  @override
  Future<Either<Failure, Success>> execute(Email email) {
    return _useCase.execute(email.id);
  }
}

class ArchiveEmailStrategy implements EmailActionStrategy {
  final ArchiveEmailUseCase _useCase;

  @override
  Future<Either<Failure, Success>> execute(Email email) {
    return _useCase.execute(email.id);
  }
}

// Controller delegates to strategies
class EmailListController {
  final Map<EmailAction, EmailActionStrategy> _strategies;

  EmailListController(this._strategies);

  void handleEmailAction(EmailAction action, Email email) {
    final strategy = _strategies[action];
    if (strategy != null) {
      strategy.execute(email);
    }
  }
}

// Adding new action = new strategy class (no controller modification)
class SpamEmailStrategy implements EmailActionStrategy { ... }

// Register in DI
getIt.registerFactory<EmailListController>(
  () => EmailListController({
    EmailAction.markRead: MarkAsReadStrategy(getIt()),
    EmailAction.archive: ArchiveEmailStrategy(getIt()),
    EmailAction.spam: SpamEmailStrategy(getIt()), // New action
  }),
);
```

### 2. Observer Pattern for State Changes

**Problem**: Adding new features that need to react to state changes.

**Solution**: Use streams/observers.

```dart
// Repository emits events
class EmailStateRepository {
  final _eventsController = StreamController<EmailEvent>.broadcast();
  Stream<EmailEvent> get events => _eventsController.stream;

  void markAsRead(EmailId id) {
    // ... logic
    _eventsController.add(EmailMarkedReadEvent(id));
  }
}

// Existing feature listens
class EmailListController {
  @override
  void onInit() {
    _emailState.events.listen((event) {
      if (event is EmailMarkedReadEvent) _updateUI(event);
    });
  }
}

// NEW feature listens (no modification to existing code)
class NotificationController {
  @override
  void onInit() {
    _emailState.events.listen((event) {
      if (event is EmailMarkedReadEvent) _dismissNotification(event);
    });
  }
}
```

### 3. Plugin/Extension Architecture

**Problem**: Adding platform-specific features.

**Solution**: Abstract platform behavior.

```dart
// Abstract interface
abstract class PlatformExtension {
  Future<void> handleDeepLink(String url);
  Future<void> showNotification(Email email);
}

// Web implementation
class WebPlatformExtension implements PlatformExtension {
  @override
  Future<void> handleDeepLink(String url) {
    html.window.location.href = url;
  }

  @override
  Future<void> showNotification(Email email) {
    // Web notification API
  }
}

// Mobile implementation
class MobilePlatformExtension implements PlatformExtension {
  @override
  Future<void> handleDeepLink(String url) {
    // Native deep link
  }

  @override
  Future<void> showNotification(Email email) {
    // Firebase notification
  }
}

// Controller uses abstraction
class EmailDetailController {
  final PlatformExtension _platform;

  EmailDetailController(this._platform);

  void shareEmail(Email email) {
    _platform.handleDeepLink('mailto:${email.from}');
  }
}

// DI registers correct implementation
getIt.registerSingleton<PlatformExtension>(
  kIsWeb ? WebPlatformExtension() : MobilePlatformExtension(),
);
```

### 4. Middleware Pattern for Cross-Cutting Concerns

**Problem**: Adding logging, analytics, auth checks to all use cases.

**Solution**: Use case middleware.

```dart
// Middleware interface
abstract class UseCaseMiddleware {
  Future<Either<Failure, Success>> execute(
    Future<Either<Failure, Success>> Function() useCase,
  );
}

// Logging middleware
class LoggingMiddleware implements UseCaseMiddleware {
  @override
  Future<Either<Failure, Success>> execute(useCase) async {
    log('Use case started');
    final result = await useCase();
    log('Use case completed: $result');
    return result;
  }
}

// Analytics middleware
class AnalyticsMiddleware implements UseCaseMiddleware {
  @override
  Future<Either<Failure, Success>> execute(useCase) async {
    final startTime = DateTime.now();
    final result = await useCase();
    final duration = DateTime.now().difference(startTime);
    analytics.track('use_case_duration', {'ms': duration.inMilliseconds});
    return result;
  }
}

// Composable use case
class MiddlewareUseCase {
  final List<UseCaseMiddleware> _middleware;
  final Future<Either<Failure, Success>> Function() _useCase;

  MiddlewareUseCase(this._middleware, this._useCase);

  Future<Either<Failure, Success>> execute() async {
    var currentUseCase = _useCase;

    for (final middleware in _middleware.reversed) {
      final captured = currentUseCase;
      currentUseCase = () => middleware.execute(captured);
    }

    return currentUseCase();
  }
}

// Usage - adding middleware = no controller changes
final useCase = MiddlewareUseCase(
  [LoggingMiddleware(), AnalyticsMiddleware()],
  () => _sendEmailUseCase.execute(email),
);
```

### 5. Feature Flags for Gradual Rollout

```dart
class FeatureFlag {
  static bool get aiScribeEnabled =>
      _remoteConfig.getBool('ai_scribe_enabled');
}

// Controller checks feature flag
class ComposerController {
  void buildToolbar() {
    final actions = [
      FormatAction(),
      AttachAction(),
    ];

    if (FeatureFlag.aiScribeEnabled) {
      actions.add(AiScribeAction()); // New feature
    }

    return actions;
  }
}
```

---

## Extending Controllers via Composition

### Base + Mixin Pattern

```dart
// Base controller (stable, rarely changes)
class BaseListController<T> extends GetxController {
  final items = <T>[].obs;
  final isLoading = false.obs;

  Future<void> loadItems();
  void onItemTap(T item);
}

// Feature mixins (extend without modifying base)
mixin SelectionMixin<T> on BaseListController<T> {
  final selectedItems = <T>[].obs;

  void toggleSelection(T item) {
    if (selectedItems.contains(item)) {
      selectedItems.remove(item);
    } else {
      selectedItems.add(item);
    }
  }
}

mixin SearchMixin<T> on BaseListController<T> {
  final searchQuery = ''.obs;

  List<T> get filteredItems {
    if (searchQuery.isEmpty) return items;
    return items.where((item) => matches(item, searchQuery.value)).toList();
  }

  bool matches(T item, String query);
}

// Compose features as needed
class EmailListController extends BaseListController<Email>
    with SelectionMixin<Email>, SearchMixin<Email> {

  @override
  bool matches(Email email, String query) {
    return email.subject.contains(query);
  }
}

// Different composition for different screens
class MailboxListController extends BaseListController<Mailbox>
    with SearchMixin<Mailbox> {
  // No selection needed
}
```

---

## Dependency Injection for Flexibility

```dart
// Abstract dependencies
abstract class IEmailRepository {
  Stream<List<Email>> getEmails(MailboxId id);
}

abstract class IEmailCache {
  Future<List<Email>> getCached(MailboxId id);
}

// Controller depends on abstractions
class EmailListController {
  final IEmailRepository _repo;
  final IEmailCache _cache;

  EmailListController(this._repo, this._cache);
}

// Swap implementations without code changes
void setupDI() {
  if (BuildConfig.isDebug) {
    getIt.registerSingleton<IEmailRepository>(MockEmailRepository());
  } else {
    getIt.registerSingleton<IEmailRepository>(JmapEmailRepository());
  }
}
```

---

## Testing Extensibility

```dart
test('Can add new email action without modifying controller', () {
  // Create new strategy
  final newStrategy = CustomEmailStrategy();

  // Inject into controller
  final controller = EmailListController({
    EmailAction.custom: newStrategy,
  });

  // Verify works
  controller.handleEmailAction(EmailAction.custom, testEmail);
  verify(newStrategy.execute(testEmail)).called(1);
});
```

---

## Summary: Adding Features Without Breaking Existing Code

| Scenario | Solution | Example |
|----------|----------|---------|
| New email action | Strategy pattern | Add SnoozeEmailStrategy |
| New state listener | Observer pattern | Add NotificationController |
| Platform-specific | Abstract interface | Add DesktopPlatformExtension |
| Cross-cutting concern | Middleware | Add AuthMiddleware |
| Optional feature | Feature flag | Add AI Scribe toolbar |
| Different behavior | DI swap | Use MockRepository in tests |
| Extend capabilities | Mixin composition | Add DragDropMixin |

**Result**: Controllers stay small, focused, and stable. Extensions happen in new files.
