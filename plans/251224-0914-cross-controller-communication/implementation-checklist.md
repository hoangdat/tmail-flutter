# Implementation Checklist

**Parent**: [Cross-Controller Communication Strategy](./plan.md)

---

## Phase 3: Architecture (Weeks 1-5)

### Week 1: Foundation

- [ ] Create `lib/core/state/` directory
- [ ] Create `MailboxStateRepository`:
  - [ ] `selectedMailboxStream` (BehaviorSubject)
  - [ ] `selectMailbox(Mailbox)` method
  - [ ] `dispose()` method
- [ ] Create `UserStateRepository`:
  - [ ] `currentUserStream` (BehaviorSubject)
  - [ ] `setCurrentUser(User)` method
  - [ ] `dispose()` method
- [ ] Create `EmailStateRepository`:
  - [ ] `selectedEmailStream` (BehaviorSubject)
  - [ ] `selectEmail(Email)` method
  - [ ] `dispose()` method
- [ ] Write repository unit tests:
  - [ ] Stream emission tests
  - [ ] Multiple subscriber tests
  - [ ] Disposal tests

### Week 1-2: Email Feature (Pilot)

- [ ] Refactor `MailboxListController`:
  - [ ] Inject `MailboxStateRepository` (Get.find for now)
  - [ ] Replace direct controller calls with `selectMailbox()`
  - [ ] Update tests (validate green)
- [ ] Refactor `EmailListController`:
  - [ ] Inject `MailboxStateRepository`
  - [ ] Subscribe to `selectedMailboxStream`
  - [ ] Cancel subscription in `onClose()`
  - [ ] Update tests (validate green)
- [ ] Add integration test:
  - [ ] Select mailbox → email list updates
  - [ ] Validate cross-controller reactivity

### Week 2-3: Mailbox Feature

- [ ] Refactor `MailboxController`:
  - [ ] Subscribe to `selectedMailboxStream`
  - [ ] Update UI on mailbox changes
- [ ] Update `MailboxHeaderController`:
  - [ ] Subscribe to `selectedMailboxStream`
  - [ ] Update header when mailbox selected
- [ ] Run all mailbox tests (validate green)

### Week 3: Composer Feature

- [ ] Create event stream in `EmailRepository`:
  - [ ] `EmailSentEvent`, `DraftSavedEvent` classes
  - [ ] `events` broadcast stream
  - [ ] Emit events on actions
- [ ] Refactor `ComposerController`:
  - [ ] Use `EmailRepository` events
  - [ ] Remove direct controller calls
- [ ] Refactor listeners:
  - [ ] `EmailListController` subscribes to events
  - [ ] `DraftListController` subscribes to events
- [ ] Run composer tests (validate green)

### Week 4: Thread Feature

- [ ] Apply repository pattern to thread feature
- [ ] Subscribe to relevant state streams
- [ ] Run thread tests (validate green)

### Week 4-5: Search Feature

- [ ] Create `SearchStateRepository`:
  - [ ] `searchQueryStream`
  - [ ] `searchFiltersStream`
- [ ] Refactor `SearchController` to use repository
- [ ] Refactor `EmailListController` to react to search
- [ ] Run search tests (validate green)

### Week 5: Validation

- [ ] Run ALL tests (entire test suite)
- [ ] Measure test coverage (target 70%)
- [ ] Document patterns in `code-standards.md`
- [ ] Create migration guide for remaining features

---

## Phase 4: DI Migration (Weeks 1-6)

### Week 1: GetIt Infrastructure

- [ ] Add `get_it: ^7.6.0` to `pubspec.yaml`
- [ ] Create `lib/core/di/injection_container.dart`
- [ ] Create `setupDI()` function
- [ ] Initialize GetIt in `main.dart`
- [ ] Register state repositories as singletons:
  - [ ] `MailboxStateRepository`
  - [ ] `UserStateRepository`
  - [ ] `EmailStateRepository`
  - [ ] `SearchStateRepository`
- [ ] Write DI container tests

### Week 2-3: Email Feature Migration

- [ ] Create `lib/core/di/modules/email_module.dart`
- [ ] Migrate `EmailListController`:
  - [ ] Add constructor parameters (repositories)
  - [ ] Remove `Get.find()` calls
  - [ ] Register factory in GetIt
- [ ] Update `EmailListController` tests:
  - [ ] Use constructor injection
  - [ ] Measure mock reduction (track improvement)
- [ ] Migrate `EmailDetailController`:
  - [ ] Constructor injection
  - [ ] Remove Get.find()
  - [ ] Update tests
- [ ] Run all email tests (validate green)
- [ ] Measure test setup improvement

### Week 3: Mailbox Feature Migration

- [ ] Create `lib/core/di/modules/mailbox_module.dart`
- [ ] Migrate controllers:
  - [ ] `MailboxListController`
  - [ ] `MailboxController`
  - [ ] `MailboxHeaderController`
- [ ] Remove `Get.find()` from all mailbox controllers
- [ ] Update tests (constructor mocks)
- [ ] Run mailbox tests (validate green)

### Week 3-4: Composer Feature Migration

- [ ] Create `lib/core/di/modules/composer_module.dart`
- [ ] Migrate `ComposerController`:
  - [ ] Constructor inject `EmailRepository`, `DraftRepository`
  - [ ] Remove Get.find() (10+ instances)
  - [ ] Update tests
- [ ] Migrate sub-controllers:
  - [ ] `AttachmentController`
  - [ ] `RecipientController`
- [ ] Run composer tests (validate green)

### Week 4-5: Thread & Search Migration

- [ ] Create `lib/core/di/modules/thread_module.dart`
- [ ] Migrate `ThreadController`
- [ ] Create `lib/core/di/modules/search_module.dart`
- [ ] Migrate `SearchController`, `SearchEmailController`
- [ ] Update tests for both features
- [ ] Run tests (validate green)

### Week 5-6: Cleanup & Validation

- [ ] Run `grep -r "Get.find" lib/` to find remaining calls
- [ ] Refactor remaining service locator calls
- [ ] Deprecate old GetX bindings:
  - [ ] `@deprecated` annotations
  - [ ] Migration warnings
- [ ] Delete GetX binding files:
  - [ ] `mailbox_dashboard_bindings.dart` (238 bindings)
  - [ ] `composer_bindings.dart` (149 bindings)
  - [ ] Other binding files
- [ ] Run ALL tests (final validation)
- [ ] Integration smoke tests on all platforms
- [ ] Measure final test coverage (target 75%)

### Week 6: Documentation

- [ ] Update `code-standards.md`:
  - [ ] DI patterns section
  - [ ] Module registration guidelines
  - [ ] Testing with DI examples
- [ ] Document GetX usage going forward:
  - [ ] What stays: Obx, GetBuilder (reactive UI)
  - [ ] What's gone: Get.find/put (service locator)
- [ ] Create migration guide for remaining 28 features
- [ ] Add examples to documentation

---

## CI/CD Integration

### Pre-Commit Hooks

- [ ] Add lint check: No `Get.find()` in new files
- [ ] Add lint check: All StreamControllers have `dispose()`
- [ ] Add lint check: All controllers cancel subscriptions

### CI Pipeline

- [ ] Run all unit tests
- [ ] Run integration tests
- [ ] Measure code coverage (fail if <70% Phase 3, <75% Phase 4)
- [ ] Run memory leak detection tests
- [ ] Generate coverage report

---

## Success Validation

### Phase 3 Complete

- [ ] 5 features using repository + stream pattern
- [ ] Zero controller-to-controller direct calls (grep check)
- [ ] All tests green (CI passing)
- [ ] Test coverage ≥70%
- [ ] No memory leaks (leak tests pass)
- [ ] Documentation updated

### Phase 4 Complete

- [ ] Zero `Get.find()` in migrated features (grep check)
- [ ] Test setup reduced 50-70% (measured)
- [ ] All tests green (CI passing)
- [ ] Test coverage ≥75%
- [ ] GetX bindings removed (files deleted)
- [ ] Migration guide complete

---

## Rollback Checkpoints

### After Email Feature (Phase 3 Week 2)

- [ ] Email feature works with repository pattern
- [ ] Tests green
- [ ] If issues: rollback email changes, keep foundation

### After Email Migration (Phase 4 Week 3)

- [ ] Email feature works with GetIt DI
- [ ] Tests simpler (fewer mocks)
- [ ] If issues: rollback to GetX, keep repositories

### Before Deleting Bindings (Phase 4 Week 5)

- [ ] ALL features migrated
- [ ] Zero Get.find() in migrated code
- [ ] All tests green
- [ ] If issues: keep bindings, debug before deletion
