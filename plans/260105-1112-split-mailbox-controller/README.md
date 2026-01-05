# Mailbox Controller Refactoring Plan

**Created**: 2026-01-05
**Current File Size**: 1561 lines
**Target**: <200 lines using Repository Pattern
**Approach**: Value-oriented, zero breaking changes

---

## Quick Summary

Split `MailboxController` (1561 lines) into **5 repositories + thin controller** using incremental, testable migrations. Every phase is deployable.

### What You Get

- ✅ Controller reduced to ~150 lines
- ✅ Clear state ownership (repositories)
- ✅ Loose coupling (no more `Get.find<Dashboard>()` in repositories)
- ✅ Easy testing (mock repositories)
- ✅ **Zero functional breakage**

---

## Architecture

### Before (Current - Problematic)
```dart
MailboxController (1561 lines)
├── State management
├── CRUD operations
├── WebSocket sync
├── Email count tracking
├── Navigation
└── Tight coupling to MailboxDashBoardController
```

### After (Target - Clean)
```dart
MailboxStateRepository (~200 lines) - Owns mailbox state
MailboxCrudRepository (~250 lines) - CRUD operations
MailboxSyncRepository (~180 lines) - Real-time sync
MailboxCountRepository (~150 lines) - Email counts
MailboxNavigationRepository (~200 lines) - Navigation

MailboxController (~150 lines) - Thin coordinator
```

---

## Implementation Phases

| Phase | Duration | What Happens | Tests |
|-------|----------|--------------|-------|
| **1. Foundation** | 2 days | Create repository files + interfaces | ✅ Green |
| **2. State Extraction** | 3 days | Move state to repository | ✅ Green |
| **3. CRUD Extraction** | 3 days | Move create/rename/delete to repository | ✅ Green |
| **4. WebSocket Sync** | 2 days | Move real-time sync to repository | ✅ Green |
| **5. Count Management** | 2 days | Move email counts to repository | ✅ Green |
| **6. Navigation** | 2 days | Move navigation logic to repository | ✅ Green |
| **7. Cleanup** | 1 day | Final polish, remove old code | ✅ Green |
| **Total** | **15 days** | **Controller <200 lines** | **All Green** |

---

## Key Principles

### 1. Zero Breaking Changes
- All tests stay green
- Same public API
- Features work identically
- Deploy after any phase

### 2. Strangler Fig Pattern
- Old and new code coexist during migration
- Gradually replace old with new
- Remove old code only at the end

### 3. Value-Oriented
- Every commit is shippable
- No "big bang" refactoring
- Incremental, testable, reversible

---

## Detailed Phase Documents

- **[repository-pattern-plan.md](./repository-pattern-plan.md)** - Complete architecture overview
- **[phase-01-foundation.md](./phase-01-foundation.md)** - Create repository infrastructure
- **[phase-02-state-extraction.md](./phase-02-state-extraction.md)** - Move state to repository

Additional phases (3-7) follow same pattern. Each phase:
1. Define what to extract
2. Create/update repository
3. Update controller to delegate
4. Verify tests green
5. Deploy

---

## Getting Started

### Step 1: Review Plans
```bash
# Read the detailed architecture
cat repository-pattern-plan.md

# Review Phase 1
cat phase-01-foundation.md
```

### Step 2: Create Branch
```bash
git checkout -b feat/mailbox-repository-pattern
```

### Step 3: Start Phase 1
```bash
# Follow phase-01-foundation.md
mkdir -p lib/features/mailbox/domain/repository
# ... create files
```

### Step 4: After Each Phase
```bash
# Run tests
flutter test

# Expected: All green ✅

# Deploy to staging (optional but recommended)
# Verify manually
# Merge if confident
```

---

## Success Metrics

### Code Quality
- [x] MailboxController <200 lines
- [x] Each repository <250 lines
- [x] Zero `Get.find<MailboxDashBoardController>()` in repositories
- [x] Clear state ownership

### Functional Quality
- [x] All existing tests pass
- [x] No new bugs introduced
- [x] Same behavior as before
- [x] Performance maintained

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking functionality | Tests green after each phase |
| Performance issues | Profile before/after, maintain <16ms frames |
| Complex dependencies | Clear repository interfaces, DI via GetX |
| Team learning curve | Detailed docs, code examples, PR reviews |

---

## File Structure

```
plans/260105-1112-split-mailbox-controller/
├── README.md (this file)
├── repository-pattern-plan.md (complete architecture)
├── phase-01-foundation.md (create repositories)
├── phase-02-state-extraction.md (move state)
└── [Additional phase docs to be created as needed]
```

---

## Next Steps

1. **Read** `repository-pattern-plan.md` for complete architecture
2. **Review** Phase 1 plan
3. **Get approval** from team/PM
4. **Start implementation** following Phase 1
5. **Deploy incrementally** after each phase

---

## Questions?

- Architecture questions: See `repository-pattern-plan.md`
- Phase 1 details: See `phase-01-foundation.md`
- Phase 2 details: See `phase-02-state-extraction.md`

**Status**: ✅ Plan complete, ready for implementation

**Estimated Effort**: 15 days (3 weeks)

**Risk Level**: Low (incremental, testable, reversible)
