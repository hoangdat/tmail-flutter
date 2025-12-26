# Cross-Controller Communication Strategy

**Project**: tmail-flutter v0.23.0
**Date**: 2025-12-24
**Status**: Planning
**Parent Plan**: [Architecture Refactoring](../251222-0906-architecture-refactoring/plan.md)

---

## Context

User raised valid concerns about event bus pattern for cross-controller communication:
- Hidden dependencies - hard to trace what triggers what
- No compile-time safety - typos in event names fail at runtime
- Memory leaks - forgetting to unsubscribe is common
- Debugging nightmare - event chains impossible to follow
- Testing complexity - hard to mock and verify event flows
- No clear data flow - state changes feel "magical"

Current architecture (59 controllers) uses GetX service locator (2173+ Get.find calls), creating similar problems. Need communication pattern that works with our phased refactoring (Phases 1-4) and provides:
- Explicit dependencies (compile-time safe)
- Clear data flow (traceable)
- Easy testing (mockable)
- Scales to 50+ controllers

**Research**: [Cross-Controller Communication Patterns](../251222-0906-architecture-refactoring/reports/251224-cross-controller-communication.md)

---

## Executive Summary

**Recommendation: Repository Pattern + Streams + GetIt DI**

Instead of event buses or direct controller-to-controller communication, use:
1. **Repository as single source of truth** - owns data, emits streams
2. **Controllers subscribe to repository streams** - reactive updates
3. **GetIt DI** for explicit dependency injection
4. **No controller-to-controller coupling** - all communication via shared services

**Why this works for Tmail**:
- Aligns with existing Repository/Interactor pattern (39 repositories)
- Fits phased refactoring (Phase 3: architecture, Phase 4: DI)
- Explicit dependencies → testable, debuggable, type-safe
- Scales to 50+ controllers without coupling
- Production-proven pattern (2024-2025 Flutter standard)

---

## Documentation Structure

This plan is modularized into focused documents:

1. **[Architecture Overview](./architecture-overview.md)** - Layered communication flow, key principles
2. **[Communication Patterns](./communication-patterns.md)** - Pattern 1 (Shared State), Pattern 2 (Events), Pattern 3 (ValueNotifier)
3. **[Migration Strategy](./migration-strategy.md)** - Phase 3 & 4 implementation steps
4. **[Use Case Matrix](./use-case-matrix.md)** - Scenarios, patterns, anti-patterns
5. **[Testing Strategy](./testing-strategy.md)** - Repository, controller, integration testing
6. **[Memory Management](./memory-management.md)** - Stream cleanup, disposal patterns
7. **[Implementation Checklist](./implementation-checklist.md)** - Phase-by-phase tasks

---

## Quick Reference

### Decision Matrix

| Need | Use Pattern | Document |
|------|-------------|----------|
| Multiple controllers need same data | Repository + Stream | [Pattern 1](./communication-patterns.md#pattern-1-shared-state) |
| Notify controllers of action | Event Stream | [Pattern 2](./communication-patterns.md#pattern-2-event-notification) |
| Simple boolean/counter state | ValueNotifier | [Pattern 3](./communication-patterns.md#pattern-3-valuenotifier) |
| Cross-controller communication | Shared Repository | [Architecture](./architecture-overview.md) |

### Migration Timeline

- **Phase 3 (Weeks 1-5)**: Introduce repositories with streams
- **Phase 4 (Weeks 1-6)**: Migrate to GetIt DI

See [Migration Strategy](./migration-strategy.md) for detailed steps.

---

## Success Criteria

- [ ] Zero controller-to-controller direct calls
- [ ] All cross-controller communication via repositories
- [ ] Repositories expose streams for state changes
- [ ] Controllers declare dependencies in constructor (GetIt)
- [ ] Test setup reduced 50-70% (fewer mocks needed)
- [ ] All tests green (behavior unchanged)
- [ ] Memory leak tests pass (streams properly closed)
- [ ] Documentation complete (code-standards.md)

---

## Risk Assessment

**Low Risks** (Tests mitigate):
- Behavioral changes: Tests validate equivalence
- Memory leaks: Tests + linter catch unclosed streams
- Performance: Streams lightweight, broadcast efficient

**Medium Risks**:
- Large-scale refactoring: Mitigate via incremental migration
- Learning curve: Mitigate via examples + documentation

---

## Next Steps

1. **Review with architecture team** - validate approach
2. **Start Phase 3** - implement repositories with streams
3. **Pilot with email feature** - validate pattern works
4. **Expand to 5 features** - mailbox, composer, thread, search
5. **Continue to Phase 4** - migrate to GetIt DI

---

## Unresolved Questions

1. Should we use BehaviorSubject (RxDart) for "latest value" semantics?
2. Performance impact of 50+ broadcast streams?
3. State hydration on app restart strategy?
4. Offline-first sync with JMAP via repository streams?
5. Cross-feature state coordination (e.g., composer + email list)?
