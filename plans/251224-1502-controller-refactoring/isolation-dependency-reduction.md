# Isolation & Dependency Reduction

**Parent**: [Controller Refactoring Plan](./plan.md)

---

## Breaking Circular Dependencies

### Current Circular Dependency Graph

```
MailboxController
    ↓ Get.find<MailboxDashBoardController>()
MailboxDashBoardController
    ↑ accessed by MailboxController
    ↓ Get.find<ThreadController>()
ThreadController
    ↑ writes to MailboxDashBoardController
    ↓ Get.find<ComposerController>()
ComposerController
    ↑ accesses MailboxDashBoardController
```

**Result**: Impossible to instantiate in isolation, testing nightmare

---

## Solution: Repository-Mediated Communication

### Target Architecture (Zero Circular Deps)

```
Controllers (all independent)
    ↓ inject
State Repositories (singletons)
    ↓ inject
Use Cases
    ↓ inject
Data Repositories
```

**No controller knows about any other controller**

---

## Migration Strategy

### Step 1: Identify Shared State

**Current** (MailboxDashBoardController as God Object):
```dart
class MailboxDashBoardController {
  final selectedMailbox = Rxn<Mailbox>();
  final emailsInCurrentMailbox = <Email>[].obs;
  final listEmailSelected = <Email>[].obs;
  final filterOption = FilterOption.all.obs;
  // 40+ more properties accessed by other controllers
}
```

**Target** (Extract to repositories):
```dart
class MailboxStateRepository {
  final selectedMailbox = Rxn<Mailbox>();
  final _controller = StreamController<Mailbox?>.broadcast();
  Stream<Mailbox?> get stream => _controller.stream;
}

class EmailStateRepository {
  final emails = <Email>[].obs;
  final selectedEmails = <Email>[].obs;
  final filter = FilterOption.all.obs;
}
```

### Step 2: Replace Get.find() with Constructor Injection

**Before** (Hidden dependencies):
```dart
class MailboxController {
  // Hidden dependency discovered at runtime
  final dashboard = Get.find<MailboxDashBoardController>();

  void selectMailbox(Mailbox m) {
    dashboard.setSelectedMailbox(m); // Tight coupling
  }
}
```

**After** (Explicit dependencies):
```dart
class MailboxController {
  final MailboxStateRepository _mailboxState;

  // Dependency visible in constructor
  MailboxController(this._mailboxState);

  void selectMailbox(Mailbox m) {
    _mailboxState.selectMailbox(m); // Loose coupling
  }
}
```

### Step 3: Remove Direct Controller Access

**Before**:
```dart
class ThreadController {
  void loadEmails() {
    final dashboard = Get.find<MailboxDashBoardController>();
    dashboard.emailsInCurrentMailbox.clear();
    dashboard.emailsInCurrentMailbox.addAll(newEmails);
  }
}
```

**After**:
```dart
class ThreadController {
  final EmailStateRepository _emailState;

  ThreadController(this._emailState);

  void loadEmails() {
    _emailState.setEmails(newEmails); // Repository owns state
  }
}
```

---

## Dependency Injection with GetIt

### Setup

```dart
final getIt = GetIt.instance;

void setupDI() {
  // Register repositories (singletons)
  getIt.registerSingleton<MailboxStateRepository>(MailboxStateRepository());
  getIt.registerSingleton<EmailStateRepository>(EmailStateRepository());

  // Register use cases
  getIt.registerSingleton<GetEmailsUseCase>(
    GetEmailsUseCase(getIt<EmailRepository>(), getIt<EmailStateRepository>()),
  );

  // Register controllers (factories - new instance per route)
  getIt.registerFactory<MailboxController>(
    () => MailboxController(getIt<MailboxStateRepository>()),
  );
  getIt.registerFactory<ThreadController>(
    () => ThreadController(getIt<EmailStateRepository>()),
  );
}
```

### GetX Binding Integration

```dart
class MailboxBinding extends Bindings {
  @override
  void dependencies() {
    // Get controllers from GetIt
    Get.put<MailboxController>(getIt<MailboxController>());
  }
}
```

---

## Reducing Get.find() Calls

### Current State
- **1199+ Get.find() calls** across codebase
- **20+ controllers** directly access other controllers
- **15 Get.find()** in BaseController alone

### Target State
- **Zero Get.find() in controllers** (except bootstrap)
- **All dependencies** constructor-injected
- **Clear dependency graph** via GetIt registration

### Migration Plan

#### Phase 1: Extract Base Dependencies
```dart
// Before (BaseController)
class BaseController {
  final appToast = Get.find<AppToast>();
  final imagePaths = Get.find<ImagePaths>();
  final responsiveUtils = Get.find<ResponsiveUtils>();
  // 12 more...
}

// After (Constructor injection)
class BaseController {
  final AppToast appToast;
  final ImagePaths imagePaths;
  final ResponsiveUtils responsiveUtils;

  BaseController({
    required this.appToast,
    required this.imagePaths,
    required this.responsiveUtils,
  });
}

// GetIt registration
getIt.registerFactory<BaseController>(
  () => BaseController(
    appToast: getIt<AppToast>(),
    imagePaths: getIt<ImagePaths>(),
    responsiveUtils: getIt<ResponsiveUtils>(),
  ),
);
```

#### Phase 2: Migrate Controllers One-by-One
Priority order (least dependencies → most dependencies):
1. QuotasController (simple, few deps)
2. ContactController
3. SearchController
4. MailboxController
5. ThreadController
6. ComposerController (most complex)

---

## Isolation Checklist

For each controller:
- [ ] No Get.find() calls (all constructor-injected)
- [ ] No direct controller access (via repositories)
- [ ] No circular dependencies
- [ ] No shared mutable state (use repositories)
- [ ] Can be instantiated in tests with mocks
- [ ] Dependencies visible in constructor signature

---

## Testing Isolated Controllers

**Before** (Untestable):
```dart
test('MailboxController selects mailbox', () {
  // Can't test - requires entire GetX registry
  Get.put(MailboxDashBoardController(...)); // 30+ dependencies
  Get.put(ThreadController(...)); // Another 20+ dependencies
  Get.put(SearchController(...));
  // ... recursive nightmare

  final controller = MailboxController();
  // Test...
});
```

**After** (Testable):
```dart
test('MailboxController selects mailbox', () {
  // Mock only direct dependencies
  final mockState = MockMailboxStateRepository();

  final controller = MailboxController(mockState);
  controller.selectMailbox(testMailbox);

  verify(mockState.selectMailbox(testMailbox)).called(1);
});
```

---

## Dependency Inversion

### Before (Concrete Dependencies)
```dart
class ThreadController {
  final EmailRepository _repo; // Concrete class

  void load() => _repo.getEmails(); // Tightly coupled
}
```

### After (Abstract Dependencies)
```dart
abstract class IEmailRepository {
  Stream<List<Email>> getEmails(MailboxId id);
}

class ThreadController {
  final IEmailRepository _repo; // Interface

  ThreadController(this._repo); // Any implementation works
}

// Easy to swap implementations
class EmailRepositoryMock implements IEmailRepository { ... }
class EmailRepositoryFake implements IEmailRepository { ... }
```

---

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Get.find() calls | 1199+ | <50 (bootstrap only) |
| Circular dependencies | 10+ | 0 |
| Controllers accessing controllers | 20+ | 0 |
| Avg constructor params | 2 | 5-8 (explicit) |
| Test setup complexity | High (mock 30+ deps) | Low (mock 3-5 deps) |
| Build time | Baseline | <10% increase |
