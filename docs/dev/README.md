# Developer Documentation

> Architecture, implementation guides, design documents

---

## General

| Document | Description |
|----------|-------------|
| [Architecture Overview](./architecture-overview.md) | Layered architecture, protocol isolation, data flow |
| [File Index](./file-index.md) | Key files quick reference |
| [Testing Guide](./testing.md) | Lua + tree-sitter grammar testing |
| [Refactoring Plan](./refactoring-plan.md) | F1–F8 architecture debt, phased remediation plan |
| [Protocol Split Design](./protocol-split-design.md) | HTTP ↔ SQL repo split proposal |
| [Archived Docs](./archived/README.md) | Outdated design documents |

## HTTP

| Document | Description |
|----------|-------------|
| [TDD Guide](./http/tdd-guide.md) | HTTP TDD workflow and test patterns |
| [Formatter Design](./http/format-design.md) | tree-sitter formatter (✅ implemented) |
| [JSON Response UX](./http/json-response-ux.md) | JSON folding and jq exploration |
| [OpenAPI/Swagger/Postman Import](./http/openapi-import-plan.md) | TDD import feature plan (18 steps) |
| [HTTP History Design](./http/http-history.md) | Request history UI design |
| [Block Index Proposal](./http/block-index-proposal.md) | Structured buffer index proposal |

## SQL

## Build

```bash
tests/run.sh         # Run Lua tests
```

---

## Documentation Conventions

- New features: add design docs under `dev/<protocol>/`
- User syntax references go under `user/<protocol>/`
- Keep cross-references up to date
- English preferred for all documentation

---

*Developer documentation - Last updated: 2026-07-07*