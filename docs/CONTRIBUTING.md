# Contributing

## Branch naming

`<type>/<scope>-<short-desc>` — e.g. `feat/orders-cancel-flow`, `fix/dispatch-tie-break`, `chore/melos-bump`.

## Commits

Conventional Commits (`feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`). Imperative mood, ≤ 72 chars.

## Pre-PR checklist

- `melos run analyze` — clean.
- `melos run test` — passing (where tests exist).
- `melos run format` — clean.
- If schema changed: `mcp__supabase__get_advisors` returned no new issues.
- Docs updated if behaviour or contracts changed.

## Code rules (enforced or strongly preferred)

- One concern per file, ≤ ~250 lines as a soft cap.
- Feature modules never depend on each other directly — go through `domain` interfaces and shared packages.
- No Supabase imports outside `packages/data`.
- No business logic in widgets — pull out into Riverpod notifiers.
- Migrations: never edit an applied one; add a new one.

## Codegen

After editing `@riverpod` / `@freezed` / repository interfaces:

```powershell
melos run gen
# or to watch:
melos run watch
```
