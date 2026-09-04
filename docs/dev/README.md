# Developer Documentation

> File-driven HTTP request executor (Lua + curl)

| Document | Description |
|----------|-------------|
| [Architecture Overview](./architecture-overview.md) | Layers, request lifecycle, dependency graph |
| [File Index](./file-index.md) | Quick reference for every source file |
| [Testing Guide](./testing.md) | How to run tests (tree-sitter + Lua + contract) |
| [Code Review 2026-08-13](./code-review-2026-08-13.md) | Full review report (29 findings + doc drift) |
| [Review Todo](./code-review-todo.md) | Fix tracking checklist (all done) |
| [Code Review 2026-09-05](./code-review-2026-09-05.md) | Quality audit: DRY / responsibilities / coverage / conventions |
| [Error Patterns](./error-patterns-review.md) | Recurring bug patterns and antidotes |
| [Refactoring Plan](./refactoring-plan.md) | R1–R7 refactoring roadmap |
| [Rust Retirement](./rust-retirement-plan.md) | Rust CLI removal log (all phases done) |
| [GUI Harness Design](./gui-harness-design.md) | Test harness for GUI-coupled modules |

## HTTP Protocol

| Document | Description |
|----------|-------------|
| [TDD Guide](./tdd-guide.md) | TDD workflow and test patterns |
| [Block Index Proposal](./block-index-proposal.md) | Structured buffer index for completion |
| [JSON Response UX](./json-response-ux.md) | JSON folding and jq filter experience |
| [HTTP History Design](./http-history.md) | Request history UI and persistence |
| [Tree-sitter Migration](./treesitter-migration.md) | Tree-sitter as single parse authority |
| [Multi-Protocol Design](./multi-protocol-design.md) | GraphQL / gRPC / WebSocket via executor abstraction (design only) |

## Archived

| Document | Description |
|----------|-------------|
| [Prompt Enhance Plan](./archived/PROMPT_ENHANCE_PLAN.md) | Structured prompt options design (implemented) |
| [Variable Resolver](./archived/variable-resolver.md) | Rust-era variable resolver design (superseded) |

---

*Developer documentation — Last updated: 2026-09-05*