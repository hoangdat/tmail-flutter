# Migration Roadmap

**Parent**: [Controller Refactoring Plan](./plan.md)

---

## 12-Week Phased Migration

### Phase 1: Foundation (Weeks 1-2)

**Goal**: Set up infrastructure without breaking existing code.

#### Week 1: Setup DI & Repositories
- [ ] Install GetIt package
- [ ] Create state repository interfaces
- [ ] Implement MailboxStateRepository
- [ ] Implement EmailStateRepository
- [ ] Implement ComposerStateRepository
- [ ] Setup GetIt registration in main.dart
- [ ] Add linter rules (cancel_subscriptions, close_sinks)

#### Week 2: Base Controllers
- [ ] Refactor BaseController (remove Get.find())
- [ ] Create BaseListController template
- [ ] Create BaseFormController template
- [ ] Document repository patterns
- [ ] Update code-standards.md

**Deliverables**: Working DI container, 3 state repositories, updated base controllers

---

### Phase 2: Split Large Controllers (Weeks 3-5)

**Goal**: Break monolithic controllers into focused units.

#### Week 3: ComposerController Split
- [ ] Extract ComposerStateRepository (shared state)
- [ ] Create AttachmentController (150 lines)
- [ ] Create RecipientController (120 lines)
- [ ] Create EditorController (180 lines)
- [ ] Create DraftController (100 lines)
- [ ] Refactor ComposerController to core (180 lines)
- [ ] Update composer bindings
- [ ] Tests green

#### Week 4: MailboxDashBoardController Split
- [ ] Extract NavigationStateRepository
- [ ] Create NavigationController (150 lines)
- [ ] Create SelectionController (100 lines)
- [ ] Create FilterController (120 lines)
- [ ] Create SyncController (150 lines)
- [ ] Update dashboard bindings
- [ ] Tests green

#### Week 5: MailboxController & ThreadController Split
- [ ] Split MailboxController → Tree/Actions/Sync (3 controllers)
- [ ] Split ThreadController → List/Search/Selection (3 controllers)
- [ ] Update all bindings
- [ ] Integration tests
- [ ] Tests green

**Deliverables**: 14 focused controllers (all <200 lines), 6 state repositories

---

### Phase 3: Migrate Communication (Weeks 6-8)

**Goal**: Replace Get.find() with constructor injection, remove direct controller access.

#### Week 6: Map Dependencies
- [ ] Audit all Get.find() calls (create dependency map)
- [ ] Document circular dependencies
- [ ] Create migration plan per controller
- [ ] Prioritize controllers (least → most deps)

#### Week 7-8: Incremental Migration
Priority order:
1. [ ] QuotasController (simple)
2. [ ] ContactController
3. [ ] SearchController
4. [ ] IdentityCreatorController
5. [ ] MailboxCreatorController
6. [ ] DownloadController
7. [ ] FCM/WebSocket controllers
8. [ ] NavigationController
9. [ ] SelectionController
10. [ ] FilterController
11. [ ] EmailListController
12. [ ] MailboxTreeController
13. [ ] AttachmentController
14. [ ] RecipientController

Per controller:
- [ ] Replace Get.find() with constructor params
- [ ] Update GetIt registration
- [ ] Update GetX bindings
- [ ] Tests green

**Deliverables**: Zero Get.find() in controllers, explicit dependency graph

---

### Phase 4: Repository Communication (Weeks 9-10)

**Goal**: All cross-controller communication via repositories + streams.

#### Week 9: Implement Streams
- [ ] Add streams to MailboxStateRepository
- [ ] Add streams to EmailStateRepository
- [ ] Add streams to NavigationStateRepository
- [ ] Add streams to ComposerStateRepository
- [ ] Document stream patterns

#### Week 10: Migrate Controllers to Streams
- [ ] Replace ever() with StreamSubscription
- [ ] Replace direct property access with stream listeners
- [ ] Add stream disposal in onClose()
- [ ] Verify no memory leaks (DevTools)
- [ ] Tests green

**Deliverables**: All state changes via streams, zero direct controller coupling

---

### Phase 5: Testing & Validation (Weeks 11-12)

**Goal**: Comprehensive testing, performance validation.

#### Week 11: Unit & Integration Tests
- [ ] Unit tests for all repositories (>80% coverage)
- [ ] Unit tests for all controllers (>80% coverage)
- [ ] Integration tests for state flows
- [ ] Memory leak tests (stream disposal)
- [ ] Verify all tests green

#### Week 12: Performance & Documentation
- [ ] Benchmark app performance (before/after)
- [ ] Profile memory usage
- [ ] Optimize stream usage if needed
- [ ] Update documentation (code-standards.md, architecture.md)
- [ ] Code review & team training
- [ ] Final regression testing

**Deliverables**: 80%+ test coverage, performance validated, docs complete

---

## Migration Checklist Per Controller

### Pre-Migration
- [ ] Read controller code, understand responsibilities
- [ ] Map dependencies (what does it need?)
- [ ] Map dependents (who needs it?)
- [ ] Identify shared state
- [ ] Write tests for existing behavior

### Migration
- [ ] Extract shared state to repository
- [ ] Split if >200 lines (apply SPR)
- [ ] Replace Get.find() with constructor injection
- [ ] Add stream subscriptions for state changes
- [ ] Remove direct controller access
- [ ] Update GetIt registration
- [ ] Update GetX bindings

### Post-Migration
- [ ] Tests still green
- [ ] No memory leaks (DevTools check)
- [ ] No performance regression
- [ ] Code review approved
- [ ] Documentation updated

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking functionality | Comprehensive tests before migration |
| Merge conflicts | Migrate one controller at a time |
| Performance degradation | Benchmark before/after each phase |
| Memory leaks | Linter rules + DevTools profiling |
| Team confusion | Documentation + code reviews |
| Rollback needed | Feature flags for new patterns |

---

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Avg controller size | 750 lines | <200 lines |
| Get.find() calls | 1199+ | <50 |
| Circular dependencies | 10+ | 0 |
| Test coverage | ~40% | >80% |
| Controllers >1500 lines | 4 | 0 |
| Direct controller coupling | 20+ | 0 |
| Build time | Baseline | <10% increase |
