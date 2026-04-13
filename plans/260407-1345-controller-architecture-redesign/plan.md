# Plan: Controller Architecture Redesign

**Date:** 2026-04-07  
**Status:** Planning  
**Branch:** architecture  

## Objective

Redesign the controller architecture to:
1. Eliminate the God Object (`MailboxDashBoardController`)
2. Apply SOLID principles so new features don't bloat existing controllers
3. Define clear data exchange patterns between controllers/features/screens

## Phases

| # | Phase | Status | File |
|---|-------|--------|------|
| 1 | Architecture Explanation (Current vs Target) | Done | `phase-01-architecture-explanation.md` |

## Key Decisions

- Incremental migration, not a rewrite
- Keep GetX as DI/state management framework (no framework change)
- Introduce **mediator/event bus** for inter-controller communication
- Introduce **shared state providers** for cross-cutting state
