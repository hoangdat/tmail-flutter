# Controller Refactoring Plan - Quick Start

**Created**: 2024-12-24
**Status**: Planning Phase

---

## 📋 What This Plan Covers

Complete controller architecture refactoring addressing:
- ✅ **SPR** - Split monolithic controllers (<200 lines each)
- ✅ **Isolation** - Break circular dependencies
- ✅ **Communication** - Repository + Stream pattern
- ✅ **Layering** - Clear 4-layer architecture
- ✅ **State Management** - In-memory strategies
- ✅ **Reactivity** - UI reacts to state changes
- ✅ **Extensibility** - Open-Closed Principle

---

## 🎯 Core Approach

### GetX Scoped Bindings + Repository Pattern

```
Controllers (<200 lines)
    ↓ GetX Bindings inject
State Repositories (singletons)
    ↓ Streams broadcast
Controllers listen & react
    ↓ Obx rebuilds
UI updates automatically
```

**No GetIt** - Using GetX bindings for scoped lifecycle management.

---

## 📚 Documentation Structure

| Document | Purpose | Read When |
|----------|---------|-----------|
| **[SUMMARY.md](./SUMMARY.md)** | Quick highlights | Start here |
| [plan.md](./plan.md) | Full plan overview | Need big picture |
| [getx-scoped-binding-strategy.md](./getx-scoped-binding-strategy.md) | GetX DI approach | Implementing DI |
| [controller-layering.md](./controller-layering.md) | 4-layer architecture | Understanding structure |
| [spr-splitting-strategy.md](./spr-splitting-strategy.md) | How to split controllers | Refactoring large controllers |
| [isolation-dependency-reduction.md](./isolation-dependency-reduction.md) | Breaking circular deps | Fixing coupling issues |
| [view-state-management.md](./view-state-management.md) | State in memory | Managing state |
| [ui-reactivity.md](./ui-reactivity.md) | Making UI reactive | Building reactive UI |
| [extensibility-framework.md](./extensibility-framework.md) | Adding features | Extending functionality |
| [migration-roadmap.md](./migration-roadmap.md) | 12-week plan | Executing migration |

---

## 🚀 Quick Start

### 1. Read Summary First
```bash
open plans/251224-1502-controller-refactoring/SUMMARY.md
```

### 2. Understand GetX Binding Strategy
```bash
open plans/251224-1502-controller-refactoring/getx-scoped-binding-strategy.md
```

### 3. Review Migration Roadmap
```bash
open plans/251224-1502-controller-refactoring/migration-roadmap.md
```

---

## 💡 Key Concepts

### Controller Management

**Before**:
- Controllers 750+ lines avg
- Get.find() everywhere (1199+ calls)
- Circular dependencies
- Direct controller-to-controller access

**After**:
- Controllers <200 lines
- Get.find() only in bindings
- Zero circular dependencies
- Communication via repositories

### Example Flow

```dart
// 1. State Repository (app-level, permanent)
class MailboxStateRepository {
  final selectedMailbox = Rxn<Mailbox>();
  Stream<Mailbox?> get stream => _controller.stream;
}

// 2. AppBinding (registers repositories)
class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<MailboxStateRepository>(
      MailboxStateRepository(),
      permanent: true,
    );
  }
}

// 3. Controller (route-level, scoped)
class MailboxController extends GetxController {
  final MailboxStateRepository _state;

  MailboxController(this._state); // Injected by binding

  void select(Mailbox m) => _state.selectMailbox(m);
}

// 4. Route Binding (auto-disposes controller)
class MailboxBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => MailboxController(Get.find()));
  }
}

// 5. Other controllers react
class EmailListController extends GetxController {
  @override
  void onInit() {
    _mailboxState.stream.listen((mailbox) {
      _loadEmails(mailbox);
    });
  }
}
```

---

## 📊 Current vs Target State

| Metric | Current | Target |
|--------|---------|--------|
| Avg controller size | 750 lines | <200 lines |
| Get.find() calls | 1199+ | <50 (bindings only) |
| Circular dependencies | 10+ | 0 |
| Controllers >1500 lines | 4 | 0 |
| Controller-to-controller calls | 20+ | 0 |
| Test coverage | ~40% | >80% |

---

## ⏱️ Timeline

**12-week phased migration**:
- Weeks 1-2: Foundation (repositories, bindings)
- Weeks 3-5: Split controllers (14 focused controllers)
- Weeks 6-8: Migrate communication (GetX bindings)
- Weeks 9-10: Repository streams (reactive)
- Weeks 11-12: Testing & validation

---

## ✅ Success Criteria

- [ ] Zero controller-to-controller direct calls
- [ ] All controllers <200 lines
- [ ] All deps via constructor injection
- [ ] All communication via repositories
- [ ] 80%+ test coverage
- [ ] Zero memory leaks
- [ ] All tests green

---

## 🔗 Related Plans

- [Cross-Controller Communication](../251224-0914-cross-controller-communication/plan.md)
- [Development Rules](../../.claude/workflows/development-rules.md)

---

**Next Step**: Read [SUMMARY.md](./SUMMARY.md) for detailed highlights.
