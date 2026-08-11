# Learnings

Corrections, insights, and knowledge gaps captured during development.

**Categories**: correction | insight | knowledge_gap | best_practice

---

## [LRN-20260811-001] best_practice

**Logged**: 2026-08-11T00:00:00+08:00
**Priority**: medium
**Status**: promoted
**Area**: docs

### Summary
Treat documentation fixtures as executable conformance examples.

### Details
Examples can silently teach invalid governance syntax even when the implementation test
suite passes. The minimal example must be run through both structural validation and
semantic audit. Required-field arrays use implicit traversal in dotted paths.

### Suggested Action
Keep the example verification in the release checklist and CI-oriented contributor guidance.

### Metadata
- Source: error
- Related Files: AGENTS.md, docs/contract-model.md, examples/minimal
- Tags: examples, contracts, required-fields
- Pattern-Key: docs.example-must-pass-governance
- Recurrence-Count: 1
- First-Seen: 2026-08-11
- Last-Seen: 2026-08-11
- Promoted: AGENTS.md

---
