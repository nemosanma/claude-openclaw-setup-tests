# Project: <APP NAME> (copy to ./CLAUDE.md at the repo root)

<One or two sentences: what this app does and who uses it.>

## Stack
- Node.js <version>, TypeScript, <framework e.g. Next.js / Express / Vite>
- Package manager: <npm | pnpm | yarn> (do not mix lockfiles)
- Database: <e.g. Postgres via Prisma> — never run migrations against production

## Commands
- Install: `npm ci`
- Dev server: `npm run dev`
- Type check: `npm run typecheck`
- Lint: `npm run lint`
- Tests: `npm test` (single file: `npm test -- path/to/file.test.ts`)
- Build: `npm run build`

## Definition of done
1. `npm run typecheck && npm run lint && npm test` all pass.
2. New behavior has at least one test.
3. No new `any` types, no disabled lint rules without a comment explaining why.

## Layout
- `src/` application code — `src/lib/` shared helpers, `src/routes/` HTTP handlers
- `tests/` test files mirror `src/` paths
- `scripts/` one-off maintenance scripts (ask before running)

## Conventions
- Named exports only. Files in kebab-case. React components in PascalCase.
- Errors: throw typed errors from `src/lib/errors.ts`; never swallow exceptions.
- Config comes from environment variables loaded in `src/config.ts` — never read `process.env` elsewhere.

## Do not touch
- `.env*`, `infra/`, `migrations/` (ask first), generated files in `src/generated/`.

# Compact instructions
When compacting, keep: failing test names, file paths changed, and open TODOs.
