# Controller Refactoring Architecture Plan

**Project**: tmail-flutter v0.23.0
**Date**: 2024-12-24
**Status**: Planning Phase
**Context**: [Cross-Controller Communication](../251224-0914-cross-controller-communication/plan.md)

---

## Executive Summary

Comprehensive controller refactoring plan addressing:
- **SPR (Single Responsibility Principle)** - Split monolithic controllers
- **Isolation & Dependency Reduction** - Break circular dependencies
- **Cross-Controller Communication** - Repository + Stream pattern
- **Controller Layering** - Clear architectural hierarchy
- **View State Management** - In-memory state strategies
- **UI Reactivity** - Reactive state updates
- **Extensibility** - Open-Closed Principle compliance

**Current State**: 56 controllers, avg 750 lines, 1199+ Get.find() calls, circular dependencies, tight coupling

**Target State**: Layered architecture, explicit DI, repository-mediated communication, testable controllers <200 lines

---

## Documentation Structure

1. **[Controller Layering Architecture](./controller-layering.md)** - Layer definitions, responsibilities, communication flows
2. **[SPR Controller Splitting Strategy](./spr-splitting-strategy.md)** - How to split monolithic controllers
3. **[Isolation & Dependency Reduction](./isolation-dependency-reduction.md)** - Breaking circular deps, explicit DI
4. **[Cross-Controller Communication](./cross-controller-communication.md)** - Repository + Stream patterns
5. **[View State Management](./view-state-management.md)** - In-memory state strategies
6. **[UI Reactivity Mechanisms](./ui-reactivity.md)** - Making UI react to state
7. **[Extensibility Framework](./extensibility-framework.md)** - Open-Closed compliance
8. **[Migration Strategy](./migration-strategy.md)** - Step-by-step refactoring plan
9. **[Implementation Checklist](./implementation-checklist.md)** - Actionable tasks

---

## Current Architecture Analysis

### Pain Points Identified

| Issue | Severity | Impact | Controllers Affected |
|-------|----------|--------|---------------------|
| Circular dependencies | CRITICAL | Testing impossible, tight coupling | 20+ controllers |
| Monolithic controllers | HIGH | Hard to maintain, SRP violation | 4 controllers >1500 lines |
| Service locator overuse | HIGH | Hidden deps, no compile-time safety | 1199+ Get.find() calls |
| Shared mutable state | HIGH | Race conditions, unclear ownership | MailboxDashBoardController |
| Direct controller coupling | CRITICAL | Feature envy, inappropriate intimacy | MailboxController ↔ Dashboard ↔ Thread |

### Critical Controllers

| Controller | Lines | Responsibilities | Issues |
|-----------|-------|------------------|---------|
| ComposerController | 2370 | Composition, upload, autocomplete, AI, drafts, templates, formatting | 7+ concerns, 30+ deps |
| MailboxDashBoardController | 2000+ | Mailbox state, email list, selection, routes, 6+ integrations | God object, 40+ properties |
| MailboxController | 1561 | Tree, operations, subscription, WebSocket, UI actions | 5+ concerns, circular dep |
| ThreadController | 1547 | Loading, pagination, search, selection, filtering, shortcuts | Shared state mutation |

---

## Target Architecture

### Layered Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ UI Controller│  │ UI Controller│  │ UI Controller│  │
│  │   (View)     │  │   (View)     │  │   (View)     │  │
│  │  <200 lines  │  │  <200 lines  │  │  <200 lines  │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                  │                  │          │
│         └──────────────────┼──────────────────┘          │
└────────────────────────────┼────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────┐
│                  APPLICATION LAYER                       │
│  ┌──────────────────────────────────────────────────┐   │
│  │         State Repository (Single Source)          │   │
│  │  - Owns canonical state                          │   │
│  │  - Exposes Stream<State>                         │   │
│  │  - No UI knowledge                               │   │
│  │  - Singleton lifecycle                           │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────┐
│                    DOMAIN LAYER                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Use Cases   │  │  Use Cases   │  │  Use Cases   │  │
│  │ (Interactor) │  │ (Interactor) │  │ (Interactor) │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                  │                  │          │
│         └──────────────────┼──────────────────┘          │
└────────────────────────────┼────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────┐
│                     DATA LAYER                           │
│  ┌──────────────┐       ┌──────────────┐               │
│  │ Data Repo    │       │ Local Cache  │               │
│  │ (JMAP API)   │       │   (Hive)     │               │
│  └──────────────┘       └──────────────┘               │
└─────────────────────────────────────────────────────────┘
```

### Communication Flow

```
User Action
    ↓
UI Controller (calls use case)
    ↓
Use Case (business logic)
    ↓
State Repository (updates state, emits stream)
    ↓
Stream<State> (broadcasts)
    ↓
UI Controllers (listen, update view state)
    ↓
UI (rebuilds)
```

---

## Refactoring Strategy Overview

### Phase 1: Foundation (Weeks 1-2)
- Create state repositories (MailboxStateRepo, EmailStateRepo, etc.)
- Introduce GetIt DI container
- Document current dependencies

### Phase 2: Split Controllers (Weeks 3-5)
- Split ComposerController → 5 focused controllers
- Split MailboxDashBoardController → 4 focused controllers
- Extract shared state to repositories

### Phase 3: Migrate Communication (Weeks 6-8)
- Replace Get.find() with constructor injection
- Implement Repository + Stream pattern
- Remove direct controller-to-controller calls

### Phase 4: View State Management (Weeks 9-10)
- Standardize view state patterns
- Implement proper memory management
- Add stream disposal guards

### Phase 5: Testing & Validation (Weeks 11-12)
- Unit tests for all controllers
- Integration tests for state flow
- Memory leak detection
- Performance validation

---

## Success Criteria

- [ ] Zero controller-to-controller direct calls
- [ ] All controllers <200 lines (max 250 for complex UI)
- [ ] All dependencies via constructor injection (zero Get.find() in controllers)
- [ ] All cross-controller communication via repositories
- [ ] All state changes via streams (reactive)
- [ ] 80%+ test coverage for controllers
- [ ] Zero memory leaks (stream disposal verified)
- [ ] All tests green (behavior preserved)
- [ ] Build time <10% increase
- [ ] UI performance maintained (no frame drops)

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Breaking existing functionality | HIGH | Comprehensive test suite before refactoring |
| Large-scale changes | MEDIUM | Incremental migration, feature-by-feature |
| Learning curve (new patterns) | MEDIUM | Documentation, examples, code reviews |
| Performance degradation | LOW | Benchmark before/after, optimize streams |
| Memory leaks (stream mgmt) | MEDIUM | Linter rules, disposal tests |
| Integration failures | MEDIUM | Integration tests for state flows |

---

## Key Principles

### YAGNI (You Aren't Gonna Need It)
- Don't over-engineer abstractions
- Start simple, add complexity only when proven necessary
- No speculative features

### KISS (Keep It Simple, Stupid)
- Prefer simple solutions over clever ones
- Clear naming over abbreviations
- Direct flow over indirect

### DRY (Don't Repeat Yourself)
- Extract common patterns to base classes
- Share repositories, not controller code
- Reusable view state handlers

### SOLID
- **S**ingle Responsibility - One controller, one screen/feature
- **O**pen-Closed - Extend via composition, not modification
- **L**iskov Substitution - Controllers interchangeable via interfaces
- **I**nterface Segregation - Small, focused dependencies
- **D**ependency Inversion - Depend on abstractions (repos), not concretions

---

## Next Steps

1. **Review plan** - Team validation, feedback incorporation
2. **Create detailed docs** - Layer architecture, SPR splitting, etc.
3. **Set up foundation** - GetIt DI, base repositories
4. **Pilot refactoring** - Start with MailboxController (1561 lines)
5. **Validate approach** - Tests green, no regressions
6. **Scale to all controllers** - Feature-by-feature migration

---

## Related Documentation

- [Cross-Controller Communication](../251224-0914-cross-controller-communication/plan.md)
- [Development Rules](../../.claude/workflows/development-rules.md)
- [Code Standards](../../docs/code-standards.md)
- [Architecture Overview](../251224-0914-cross-controller-communication/architecture-overview.md)

---

## Unresolved Questions

1. Should we use BehaviorSubject (RxDart) or StreamController for state streams?
2. How to handle state hydration on app restart?
3. Performance impact of 50+ broadcast streams?
4. Migration strategy for WebSocket state synchronization?
5. Testing strategy for stream-based communication?
6. How to maintain backward compatibility during migration?
7. GetIt vs Riverpod vs Provider for DI?
