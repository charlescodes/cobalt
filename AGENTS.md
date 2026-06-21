# Agent Guide

This is the entrypoint for AI agents and contributors working on COBALT, a Godot 4.4 3D isometric RPG prototype. Keep this file operational and short; durable project knowledge belongs in the documents below.

## Read by Task

- Read `ARCHITECTURE.md` before design or code changes. It defines the current system, ownership boundaries, accepted decisions, and forbidden patterns.
- Read `ROADMAP.md` for planning, prioritization, terminology, deferred features, and open product questions.
- Read `CHANGELOG.md` when historical context or previously completed work matters.

Do not require every document for every task. Inspect the relevant code and tests after reading the applicable source of truth.

## Working Rules

- Follow the boundaries in `ARCHITECTURE.md`; do not introduce roadmap ideas as implemented architecture.
- Keep authored state in resources, durable rules in focused processors, and runtime coordination in scene nodes.
- Preserve unrelated worktree changes and keep first-pass or V1 work narrowly scoped.
- Add or update focused tests in the same change as code behavior.
- Update `ARCHITECTURE.md` only when current architecture, ownership, or durable constraints change.
- Update `ROADMAP.md` only when priorities, planned scope, terminology, or open questions change.
- Update `CHANGELOG.md` for notable completed outcomes, not every implementation step.

## Validation

Run focused tests while working, then run both commands before finishing code changes:

```bash
./scripts/run-tests.sh
./scripts/check.sh
```
