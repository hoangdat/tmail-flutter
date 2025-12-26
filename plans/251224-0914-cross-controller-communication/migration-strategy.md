# Migration Strategy

**Parent**: [Cross-Controller Communication Strategy](./plan.md)

---

## Overview

Phased migration aligned with architecture refactoring Phases 3-4:
- **Phase 3**: Introduce repositories with streams (Weeks 1-5)
- **Phase 4**: Migrate to GetIt DI (Weeks 1-6)

---

## Phase 3: Architecture (Introduce Repositories with Streams)

**Goal**: Establish repository pattern as communication layer

### Step 1: Create State Repositories (Week 1)

**Actions**:
1. Create `MailboxStateRepository`:
   ```dart
   class MailboxStateRepository {
     final _selectedMailbox = BehaviorSubject<Mailbox?>();
     Stream<Mailbox?> get selectedMailboxStream => _selectedMailbox.stream;
     Mailbox? get selectedMailbox => _selectedMailbox.value;

     void selectMailbox(Mailbox? mailbox) => _selectedMailbox.add(mailbox);
     void dispose() => _selectedMailbox.close();
   }
   ```

2. Create `UserStateRepository`:
   ```dart
   class UserStateRepository {
     final _currentUser = BehaviorSubject<User?>();
     Stream<User?> get currentUserStream => _currentUser.stream;
     User? get currentUser => _currentUser.value;

     void setCurrentUser(User? user) => _currentUser.add(user);
     void dispose() => _currentUser.close();
   }
   ```

3. Create `EmailStateRepository`:
   ```dart
   class EmailStateRepository {
     final _selectedEmail = BehaviorSubject<Email?>();
     Stream<Email?> get selectedEmailStream => _selectedEmail.stream;

     void selectEmail(Email? email) => _selectedEmail.add(email);
     void dispose() => _selectedEmail.close();
   }
   ```

**Test Validation**:
- Write repository stream emission tests
- Verify multiple subscriptions work
- Test disposal (no memory leaks)

### Step 2: Refactor Email Feature (Week 1-2, Pilot)

**BEFORE (GetX service locator - hidden coupling)**:
```dart
class MailboxListController extends GetxController {
  void selectMailbox(Mailbox mailbox) {
    // Hidden coupling - EmailListController must exist
    final emailController = Get.find<EmailListController>();
    emailController.loadEmails(mailbox); // Direct call!
  }
}

class EmailListController extends GetxController {
  void loadEmails(Mailbox mailbox) {
    // Called directly by MailboxListController
  }
}
```

**AFTER (Repository + Stream - explicit, decoupled)**:
```dart
class MailboxListController extends GetxController {
  final MailboxStateRepository _mailboxState;

  MailboxListController(this._mailboxState); // Still uses Get.find in Phase 3

  void selectMailbox(Mailbox mailbox) {
    _mailboxState.selectMailbox(mailbox); // Update repository
    // EmailListController auto-notified via stream (no coupling)
  }
}

class EmailListController extends GetxController {
  final MailboxStateRepository _mailboxState;
  late StreamSubscription _sub;

  EmailListController(this._mailboxState);

  @override
  void onInit() {
    super.onInit();
    _sub = _mailboxState.selectedMailboxStream.listen((mailbox) {
      if (mailbox != null) loadEmails(mailbox);
    });
  }

  @override
  void onClose() {
    _sub.cancel();
    super.onClose();
  }

  void loadEmails(Mailbox mailbox) {
    // React to stream
  }
}
```

**Test Validation**:
- Existing email tests pass (behavior unchanged)
- New stream subscription tests pass
- Integration test: selecting mailbox updates email list

### Step 3: Expand to 5 Features (Weeks 2-5)

Apply repository + stream pattern to:
- Mailbox feature (Week 2-3)
- Composer feature (Week 3)
- Thread feature (Week 4)
- Search feature (Week 4-5)

Each feature:
1. Identify shared state
2. Create/use state repository
3. Refactor controllers to subscribe to streams
4. Run tests (validate green)

---

## Phase 4: State Management (Migrate to GetIt DI)

**Goal**: Replace GetX service locator with explicit DI

### Step 1: Setup GetIt Infrastructure (Week 1)

**Actions**:
1. Add dependency:
   ```yaml
   dependencies:
     get_it: ^7.6.0
   ```

2. Create DI container:
   ```dart
   // lib/core/di/injection_container.dart
   final getIt = GetIt.instance;

   void setupDI() {
     // State repositories (singletons)
     getIt.registerSingleton<MailboxStateRepository>(
       MailboxStateRepository(),
     );

     getIt.registerSingleton<UserStateRepository>(
       UserStateRepository(),
     );

     // Data repositories (singletons)
     getIt.registerSingleton<MailboxRepository>(
       MailboxRepository(getIt<MailboxDataSource>()),
     );

     // Controllers (factories)
     getIt.registerFactory<MailboxListController>(
       () => MailboxListController(
         getIt<MailboxStateRepository>(),
         getIt<MailboxRepository>(),
       ),
     );
   }
   ```

3. Initialize in main.dart:
   ```dart
   void main() {
     setupDI();
     runApp(MyApp());
   }
   ```

### Step 2: Migrate Email Feature (Week 2-3, Pilot)

**BEFORE (GetX Get.find)**:
```dart
class EmailListController extends GetxController {
  late MailboxStateRepository _mailboxState;
  late EmailRepository _emailRepo;

  @override
  void onInit() {
    super.onInit();
    _mailboxState = Get.find<MailboxStateRepository>(); // Hidden!
    _emailRepo = Get.find<EmailRepository>(); // Hidden!
  }
}
```

**AFTER (GetIt constructor injection)**:
```dart
class EmailListController extends GetxController {
  final MailboxStateRepository _mailboxState;
  final EmailRepository _emailRepo;

  // Explicit dependencies
  EmailListController(
    this._mailboxState,
    this._emailRepo,
  );
}

// GetIt registration
getIt.registerFactory(() => EmailListController(
  getIt<MailboxStateRepository>(),
  getIt<EmailRepository>(),
));
```

**Test Improvement**:
```dart
// BEFORE - need 20+ Get.put mocks
test('loads emails', () {
  Get.put<MailboxStateRepository>(mockMailboxState);
  Get.put<EmailRepository>(mockEmailRepo);
  // ... 18 more Get.put()

  final controller = EmailListController();
  // Test...
});

// AFTER - only 2 constructor mocks
test('loads emails', () {
  final controller = EmailListController(
    mockMailboxState, // Explicit!
    mockEmailRepo,    // Explicit!
  );
  // Test...
});
```

### Step 3: Migrate Remaining Features (Weeks 3-6)

- Mailbox feature (Week 3)
- Composer feature (Week 3-4)
- Thread feature (Week 4-5)
- Search feature (Week 5)

Each migration:
1. Update controller constructors (add parameters)
2. Register in GetIt (factories for controllers, singletons for repos)
3. Update tests (constructor mocks)
4. Remove Get.find() calls
5. Run tests (validate green)

### Step 4: Cleanup (Week 6)

1. Grep for remaining Get.find() calls
2. Deprecate old GetX bindings
3. Remove binding files
4. Run ALL tests (final validation)
5. Update documentation

---

## Coexistence Pattern (During Migration)

During migration, GetX and GetIt coexist safely:

```dart
// OLD - Still using GetX bindings (legacy features)
class OldFeatureBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(OldController());
  }
}

// NEW - Using GetIt (migrated features)
void setupDI() {
  getIt.registerFactory(() => NewController(
    getIt<Repository>(),
  ));
}

// Both work simultaneously
final oldController = Get.find<OldController>(); // GetX
final newController = getIt<NewController>();    // GetIt
```

---

## Rollback Strategy

If migration encounters issues:

1. **Feature Flags**: Toggle GetX vs GetIt per feature
   ```dart
   final useGetIt = FeatureFlags.getItMigration;

   final controller = useGetIt
     ? getIt<EmailController>()
     : Get.find<EmailController>();
   ```

2. **Keep Old Bindings**: Don't delete until migration verified
3. **Test Gates**: Tests fail = don't merge
4. **Gradual Rollout**: Migrate 1 feature at a time

---

## Success Metrics

### Phase 3 Success

- [ ] 5 features using repository + stream pattern
- [ ] Zero controller-to-controller direct calls
- [ ] All tests green (behavior unchanged)
- [ ] Test coverage ≥70%

### Phase 4 Success

- [ ] Zero Get.find() in migrated features
- [ ] Test setup reduced 50-70% (fewer mocks)
- [ ] All tests green (behavior unchanged)
- [ ] Test coverage ≥75%
