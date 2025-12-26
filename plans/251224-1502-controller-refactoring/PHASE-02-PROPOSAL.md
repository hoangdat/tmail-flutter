# Phase 2: Controller Architecture Refactoring - Project Proposal

**Project**: tmail-flutter v0.23.0
**Date**: 2024-12-24
**Phase**: 2 - Controller Splitting & Repository Pattern
**Status**: Proposal for Review
**Audience**: Project Manager, Technical Leads

---

## Executive Summary

**Problem**: Current architecture has centralized "god object" controller managing multiple concerns, causing tight coupling, difficult testing, and scalability issues.

**Solution**: Introduce Repository Pattern with clear separation between app-level state, feature-level state, and UI controllers.

**Impact**:
- ✅ Reduced coupling between features
- ✅ Easier to add new features without breaking existing code
- ✅ Improved testability (70% reduction in test setup complexity)
- ✅ Better memory management
- ✅ SOLID principles compliance

**Timeline**: 3 weeks (Weeks 3-5 of 12-week plan)

---

## WHAT: The Proposed Architecture

### Current Architecture (Problematic)

```
┌─────────────────────────────────────────────────┐
│     MailboxDashBoardController (2000+ lines)    │
│                                                  │
│  Contains EVERYTHING:                           │
│  • Selected mailbox                             │
│  • Email list                                   │
│  • Selected emails                              │
│  • Search state                                 │
│  • Navigation routes                            │
│  • Filter options                               │
│  • 40+ properties                               │
│                                                  │
│  Accessed by ALL controllers via Get.find()    │
│  → Tight coupling, circular dependencies       │
└─────────────────────────────────────────────────┘
```

**Problem**: Single controller becomes bottleneck, change ripples everywhere.

---

### Proposed Architecture (Layered)

```
┌──────────────────────────────────────────────────────────┐
│               APP-LEVEL STATE                             │
│  ┌────────────────────────────────────────────────────┐  │
│  │  State Repositories (Singletons)                   │  │
│  │  • MailboxStateRepository                          │  │
│  │  • EmailStateRepository                            │  │
│  │  • UserStateRepository                             │  │
│  │                                                     │  │
│  │  Role: Own canonical state, expose streams         │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
                          ↓ (streams)
┌──────────────────────────────────────────────────────────┐
│             FEATURE-LEVEL STATE                           │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Feature Repositories (Scoped)                     │  │
│  │  • ComposerStateRepository                         │  │
│  │  • SearchStateRepository                           │  │
│  │                                                     │  │
│  │  Role: Manage feature-specific state               │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
                          ↓ (streams)
┌──────────────────────────────────────────────────────────┐
│                UI CONTROLLERS                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │Mailbox   │  │EmailList │  │Composer  │              │
│  │Tree      │  │Controller│  │Controller│              │
│  │Controller│  │          │  │          │              │
│  │          │  │          │  │          │              │
│  │<200 lines│  │<200 lines│  │<200 lines│              │
│  └──────────┘  └──────────┘  └──────────┘              │
│                                                           │
│  Role: Handle UI events, subscribe to streams            │
└──────────────────────────────────────────────────────────┘
```

**Benefit**: Clear separation, loose coupling, independent features.

---

## WHY: Problems Solved

### Problem 1: Centralized Controller (God Object)

**Current Issue**:
- `MailboxDashBoardController` has 2000+ lines
- Manages 7+ different concerns
- Every feature depends on it
- Change in one feature affects all others

**Solution**:
- Break into specialized state repositories
- Each repository owns one domain (mailbox, email, user)
- Controllers subscribe only to what they need

**Impact**: Changes isolated to specific domain.

---

### Problem 2: Tight Coupling & Circular Dependencies

**Current Issue**:
```
MailboxController → Get.find<MailboxDashBoardController>()
ThreadController → Get.find<MailboxDashBoardController>()
ComposerController → Get.find<MailboxDashBoardController>()

Result: Circular dependencies, hard to test
```

**Solution**:
```
Controllers → Subscribe to repositories
Repositories → Broadcast streams
No controller knows about other controllers
```

**Impact**: Zero circular dependencies, easy to mock/test.

---

### Problem 3: Unclear State Ownership

**Current Issue**:
- Who owns `selectedMailbox`? Dashboard? Mailbox controller?
- Multiple controllers mutate same state
- Race conditions possible

**Solution**:
- Clear ownership: `MailboxStateRepository` owns mailbox state
- Only repository can mutate state
- Controllers read-only via streams

**Impact**: Single source of truth, predictable state.

---

### Problem 4: Difficult to Add Features (SOLID Violation)

**Current Issue**:
- Adding email feature requires modifying `MailboxDashBoardController`
- Violates Open-Closed Principle (closed for modification)
- Risk of breaking existing features

**Solution**:
- New features create new repository + controllers
- Existing code unchanged
- Subscribe to existing streams if needed

**Impact**: Add features without touching existing code.

---

## HOW: Implementation Strategy

### 1. App-Level State Management

**What**: State shared across entire app.

**Examples**:
- Selected mailbox (needed by mailbox list, email list, composer)
- Current user (needed by all features)
- Network status (needed everywhere)

**How It Works**:

```
┌─────────────────────────────────────┐
│   MailboxStateRepository            │
│                                      │
│   State:                            │
│   • selectedMailbox                 │
│   • mailboxList                     │
│                                      │
│   Stream:                           │
│   • selectedMailboxStream           │
│       (broadcasts to all listeners) │
└─────────────────────────────────────┘
           ↓ (stream emits)
    ┌──────┴──────┐
    ↓             ↓
┌─────────┐  ┌──────────┐
│Mailbox  │  │EmailList │
│Tree     │  │Controller│
│         │  │          │
│Listens  │  │Listens   │
│& updates│  │& loads   │
│highlight│  │emails    │
└─────────┘  └──────────┘
```

**Lifecycle**: Lives entire app (singleton).

**Key Benefit**: Single source of truth, automatic sync across features.

---

### 2. Feature-Level State Management

**What**: State specific to one feature module.

**Examples**:
- Composer draft (recipients, subject, body, attachments)
- Search filters (query, date range, sender)

**How It Works**:

```
┌──────────────────────────────────────┐
│   ComposerStateRepository            │
│   (Lives only while composer open)   │
│                                       │
│   State:                             │
│   • recipients                       │
│   • attachments                      │
│   • subject                          │
│   • body                             │
└──────────────────────────────────────┘
           ↓ (shared by)
    ┌──────┴──────┬──────────┐
    ↓             ↓          ↓
┌─────────┐  ┌─────────┐ ┌─────────┐
│Composer │  │Recipient│ │Attach   │
│Ctrl     │  │Ctrl     │ │Ctrl     │
└─────────┘  └─────────┘ └─────────┘
```

**Lifecycle**: Created when feature opens, disposed when feature closes.

**Key Benefit**: Isolated feature state, no pollution of app-level state.

---

### 3. UI Rebuild Mechanism

**Challenge**: How does UI know when to update?

**Solution**: Reactive streams + Rx observables.

**How It Works**:

```
User Action
    ↓
Controller updates state
    ↓
Repository emits stream event
    ↓
UI widgets listening to stream
    ↓
UI rebuilds automatically
```

**Code Example** (Conceptual):

```dart
// Repository emits
repository.selectMailbox(inbox);
→ selectedMailboxStream.add(inbox)

// Controller listens
controller.onInit() {
  repository.selectedMailboxStream.listen((mailbox) {
    // UI rebuilds automatically
  });
}

// UI wraps in reactive widget
Obx(() => Text(controller.mailbox.name))
→ Rebuilds when mailbox changes
```

**Key Benefit**: Declarative UI, no manual refresh calls.

---

### 4. Feature-to-Feature Communication

**Scenario**: User clicks mailbox → Should show emails for that mailbox.

**Current Approach** (Problematic):
```
MailboxController → Get.find<EmailListController>().loadEmails()
Problem: Direct coupling, hard to test
```

**New Approach** (Repository Pattern):

```
Step 1: User clicks "Inbox" in MailboxTree
    ↓
Step 2: MailboxTreeController updates repository
    mailboxState.selectMailbox(inbox)
    ↓
Step 3: Repository broadcasts event
    selectedMailboxStream.add(inbox)
    ↓
Step 4: EmailListController listening
    mailboxState.selectedMailboxStream.listen((mailbox) {
      loadEmails(mailbox); // Reacts automatically
    })
    ↓
Step 5: UI rebuilds with new emails
```

**Key Points**:
- ❌ NO direct controller-to-controller calls
- ✅ Communication via repository streams
- ✅ Loose coupling (controllers don't know each other)
- ✅ Easy to test (mock repository)

---

### 5. Feature-to-App Communication

**Scenario**: Composer sends email → Should update app-level email list.

**How It Works**:

```
Step 1: ComposerController sends email
    composer.sendEmail()
    ↓
Step 2: Updates app-level email state
    emailState.addEmail(newEmail)
    ↓
Step 3: Email list listens to app-level stream
    emailState.emailsStream.listen((emails) {
      update(); // Refresh list
    })
    ↓
Step 4: Composer can close (independent)
```

**Key Benefit**: Features interact with app state without knowing each other.

---

### 6. Adding New Features (SOLID Compliance)

**Principle**: Open for extension, closed for modification.

**Scenario**: Add "Archive" feature.

**Current Approach** (Bad):
```
1. Modify MailboxDashBoardController (add archive logic)
2. Modify EmailListController (add archive button handler)
3. Risk: Breaking existing send/delete features
```

**New Approach** (Good):
```
1. Create ArchiveStateRepository (new file, no modifications)
2. Create ArchiveController (new file, no modifications)
3. Subscribe to EmailStateRepository streams
4. Existing code unchanged ✅

// New repository
class ArchiveStateRepository {
  Stream<List<Email>> get archivedEmailsStream;
  void archiveEmail(Email email);
}

// New controller
class ArchiveController {
  @override
  void onInit() {
    // Listen to email state (existing)
    emailState.emailsStream.listen((emails) {
      // Custom logic for archive feature
    });
  }
}
```

**Key Benefit**:
- Add features by creating new files
- Zero modifications to existing code
- No risk of breaking existing functionality
- SOLID principles: Open-Closed ✅

---

## Communication Patterns Summary

### Pattern 1: Feature-to-Feature

```
Feature A Controller
    ↓ (updates)
App-Level Repository
    ↓ (emits stream)
Feature B Controller (listens)
    ↓ (reacts)
UI Updates
```

**Example**: Click mailbox → Load emails

---

### Pattern 2: Feature-to-App

```
Feature Controller
    ↓ (updates)
App-Level Repository
    ↓ (persists/broadcasts)
All Features Listening
    ↓ (sync automatically)
```

**Example**: Send email → All email lists update

---

### Pattern 3: Within-Feature

```
Feature Controller A
    ↓ (updates)
Feature Repository
    ↓ (emits stream)
Feature Controller B (listens)
```

**Example**: Add recipient → Update send button state

---

## SOLID Principles Compliance

### Single Responsibility ✅
- Each controller: One screen/feature
- Each repository: One domain

### Open-Closed ✅
- Add features = New files
- No modifications to existing code

### Liskov Substitution ✅
- Controllers interchangeable via interfaces
- Mock repositories in tests

### Interface Segregation ✅
- Controllers depend only on needed repositories
- No fat interfaces

### Dependency Inversion ✅
- Controllers depend on repository abstractions
- Not concrete implementations

---

## Benefits Summary

| Benefit | Current | After Phase 2 |
|---------|---------|---------------|
| **Coupling** | High (direct controller calls) | Low (via repositories) |
| **Testability** | Hard (30+ mocks) | Easy (3-5 mocks) |
| **Circular Dependencies** | 10+ | 0 |
| **Add New Feature** | Modify existing code | Create new files only |
| **State Ownership** | Unclear | Clear (repositories) |
| **Memory Leaks** | Risk (manual cleanup) | Safe (auto-disposed) |
| **SOLID Compliance** | Violated | Compliant |

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing functionality | High | Comprehensive tests before refactoring |
| Learning curve for team | Medium | Documentation + examples + code reviews |
| Performance (many streams) | Low | Streams lightweight, measured benchmarks |
| Migration effort | Medium | Incremental, 3 weeks planned |

---

## Success Criteria

- [ ] Zero direct controller-to-controller calls
- [ ] All state managed by repositories
- [ ] All tests green (behavior preserved)
- [ ] New feature can be added without modifying existing code
- [ ] Test setup reduced by 70%
- [ ] Code review approved by tech leads

---

## Timeline - Phase 2 (3 Weeks)

### Week 3: Split ComposerController
- Extract `ComposerStateRepository`
- Split into 5 focused controllers (<200 lines each)
- Update bindings
- Tests green

### Week 4: Split MailboxDashBoardController
- Extract app-level repositories (Mailbox, Email, Navigation)
- Split into 4 focused controllers
- Migrate to repository pattern
- Tests green

### Week 5: Split Remaining Large Controllers
- MailboxController → 3 controllers
- ThreadController → 3 controllers
- Integration tests
- Documentation update

---

## Next Steps

1. **Review this proposal** - Gather feedback from PM & tech leads
2. **Approve architecture** - Sign-off on repository pattern
3. **Pilot implementation** - Start with ComposerController (Week 3)
4. **Demo & iterate** - Show working example, adjust if needed
5. **Full rollout** - Complete Weeks 4-5

---

## Questions for Discussion

1. **Timeline**: Is 3 weeks acceptable for Phase 2?
2. **Risks**: Any concerns about migration approach?
3. **Team capacity**: Do we need additional resources?
4. **Priorities**: Should we adjust scope based on business priorities?
5. **Testing**: What level of test coverage is required before proceeding?

---

## Appendix: Key Concepts Glossary

**Repository**: Object that owns state and exposes streams. Acts as single source of truth.

**App-Level State**: State shared across entire app (e.g., current user, selected mailbox).

**Feature-Level State**: State specific to one feature (e.g., composer draft).

**Stream**: Broadcast channel that emits events when state changes. Controllers subscribe to react.

**Reactive UI**: UI that automatically rebuilds when underlying data changes (via Obx/GetBuilder).

**Singleton**: Object that lives entire app lifetime (only one instance).

**Scoped**: Object that lives only while specific screen/feature is active.

**SOLID**: Software design principles ensuring maintainable, extensible code.

---

**Document Owner**: Development Team
**Last Updated**: 2024-12-24
**Status**: Awaiting PM Review
