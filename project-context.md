---
project_name: 'LTI - Talent Tracking System'
user_name: 'Juanfer Lopez'
date: '2026-04-19'
sections_completed: ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules', 'quality_rules', 'workflow_rules']
existing_patterns_found: 20
status: 'complete'
rule_count: 57
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

### Repo layout
- Monorepo-style folders: `frontend/` (React) + `backend/` (Express API) + root tooling.

### Backend (`backend/`)
- **Runtime**: Node.js
- **Framework**: Express `^4.19.2`
- **Language**: TypeScript `^4.9.5` (CommonJS: `tsconfig.json` uses `"module": "commonjs"`)
- **ORM/DB**: Prisma `^5.13.0` + PostgreSQL (via root `docker-compose.yml`)
- **Tests**: Jest `^29.7.0` + `ts-jest` `^29.2.5`
- **Lint/format**: ESLint `^9.2.0` + Prettier `^3.2.5`
  - Prettier: `singleQuote: true`, `trailingComma: all`
- **Prisma binary targets**: `["native","debian-openssl-3.0.x"]`

### Frontend (`frontend/`)
- **Framework**: React `^18.3.1` (Create React App `react-scripts@5.0.1`)
- **Language**: Mixed JS + TS (files exist in both `.js` and `.tsx`)
- **Routing**: `react-router-dom` `^6.23.1`
- **UI**: Bootstrap `^5.3.3` + `react-bootstrap` `^2.10.2`
- **HTTP client**: code uses `axios` (ensure dependency is present/kept in sync)

### Root tooling (repo root)
- Root has its own `jest` / `ts-jest` / `typescript` versions; avoid mixing them with `backend/` and `frontend/`.
- Rule of thumb: **run installs/tests inside the package you’re changing**.

## Critical Implementation Rules

### Language-Specific Rules

- **TypeScript strict mode is on** (backend + frontend `tsconfig.json`): avoid `any` at boundaries; narrow `unknown` from `catch`.
- **Backend is CommonJS** (`backend/tsconfig.json` `"module": "commonjs"`): don’t add ESM-only syntax/patterns unless you also update build/runtime.
- **Backend build/runtime contract**: `tsc` outputs to `backend/dist/`; production entry is `node dist/index.js` (`npm run build` then `npm start`).
- **Express typing extension**: `Express.Request` includes `prisma: PrismaClient` (middleware attaches it). New routes/controllers should use `req.prisma` rather than creating ad-hoc clients.
- **Prettier conventions (backend)**: `singleQuote: true`, `trailingComma: all`.
- **Frontend is mixed JS + TS**: match the file’s language; if you need typing, migrate `.js` → `.ts/.tsx` instead of sprinkling TS-only constructs into JS.

### Framework-Specific Rules

#### Backend (Express + Prisma)
- **Layering**: keep `routes/` → `presentation/controllers/` → `application/services/` → `domain/models/`; don’t “skip layers” casually when adding endpoints.
- **Single entrypoint per route**: avoid importing service functions through `presentation/controllers/*` barrels; route files should call **controller functions** only (prevents duplicate response shapes and bypassed error handling).
- **Prisma access**: use `req.prisma` (middleware-attached singleton). Don’t create ad-hoc `new PrismaClient()` in handlers/services unless there’s a deliberate architectural change.
- **Middleware order matters**: register cross-cutting middleware (logging, auth, parsers) **before** mounting routers; don’t assume “it’s registered somewhere” is enough.
- **CORS**: current config targets `http://localhost:3000` with credentials; expand origins deliberately (don’t use `*` with credentials).
- **Uploads (`multer`)**:
  - Multipart field name: **`file`**
  - Allowed types: **PDF** + **DOCX**; max **10MB**
  - Destination uses a **relative** path (`../uploads/`): validate behavior when cwd changes (local vs deployed).
- **Docs drift guard**: if request/response shapes change, update `backend/api-spec.yaml` alongside runtime validation (`application/validator.ts`).
- **Prisma errors**: preserve/extend patterns for constraint failures (e.g. email uniqueness / `P2002`) with clear API errors.

#### Frontend (CRA + React)
- **CRA constraints**: stay within CRA defaults unless explicitly migrating tooling; avoid `eject` unless requested.
- **UI stack**: prefer Bootstrap + React-Bootstrap patterns already used in components.
- **HTTP configuration**: API base URL is currently hardcoded to `http://localhost:3010`; centralize if you introduce environments (CRA: `REACT_APP_*`), and keep usage consistent across services.

### Testing Rules

- **Current state**: there are no test files checked in yet—don’t assume coverage exists; if you add behavior, consider adding the first tests + wiring.
- **Run tests from the correct package**: run from `backend/` when changing API code, and from `frontend/` when changing UI code. Avoid mixing repo-root Jest tooling with package-local dependencies unless the repo standardizes it.
- **Frontend test command hazard**: `frontend/package.json` uses `jest --config jest.config.js` but `frontend/jest.config.js` is missing—prefer CRA’s default (`react-scripts test`) unless you add/standardize a Jest config.
- **Backend Jest/TS wiring**: backend uses Jest + `ts-jest`, but lacks a local `jest.config.*`. If you add `.ts` tests, ensure Jest is configured to transform TS when run from `backend/`.
- **Boundaries**:
  - Unit tests: validators (`backend/src/application/validator.ts`) and pure logic.
  - API tests (if added): hit `app` and assert HTTP contracts; don’t couple to implementation details.
- **DB safety**: integration tests must use an isolated database strategy (e.g., dedicated test DB + reset/migrations). Never run tests against a dev/prod DB by accident.

### Code Quality & Style Rules

- **Format via Prettier (backend)**: follow `backend/.prettierrc` (`singleQuote: true`, `trailingComma: all`). Avoid local formatting exceptions.
- **Lint via ESLint (backend)**: `backend/.eslintrc.js` extends `plugin:prettier/recommended`; prefer fixing lint issues over disabling rules inline.
- **Frontend linting is CRA-managed**: don’t apply backend ESLint/Prettier assumptions to `frontend/` unless you’re explicitly standardizing tooling.
- **TypeScript strictness**: keep `strict: true` clean; don’t introduce `any` for convenience—narrow types at boundaries.
- **Keep layering and placement**: add backend code into the existing layers (`application/`, `domain/`, `presentation/`, `routes/`) rather than inventing new ad-hoc folders.
- **Contract drift guard**: when changing API behavior, update as a set:
  - Runtime validation: `backend/src/application/validator.ts`
  - API docs: `backend/api-spec.yaml`
  - Persistence model: `backend/prisma/schema.prisma` (and migrations if needed)
- **Logging discipline**: no noisy `console.log` in normal request paths; if logging is needed, keep it scoped and intentional.

### Development Workflow Rules

- **Monorepo rule**: always run `npm install` / `npm test` / `npm run build` from the package you changed (`backend/` or `frontend/`). Don’t rely on repo-root tooling unless you’re intentionally changing root scripts.
- **Backend scripts** (`backend/package.json`):
  - Dev: `npm run dev`
  - Build: `npm run build` (outputs to `dist/`)
  - Start: `npm start` (runs `dist/index.js`)
  - Prod-style: `npm run start:prod`
- **Frontend scripts** (`frontend/package.json`):
  - Dev: `npm start`
  - Build: `npm run build`
  - Testing: current `npm test` is miswired (expects `frontend/jest.config.js`); prefer CRA default (`react-scripts test`) unless/until a custom Jest config is added.
- **Database + Prisma**:
  - Start Postgres: `docker-compose up -d`
  - From `backend/`: run migrations `npx prisma migrate dev`
  - Keep Prisma artifacts in sync when models change: `schema.prisma` + migrations + `npx prisma generate`
- **Environment variables**:
  - Docker uses `${DB_PASSWORD}`, `${DB_USER}`, `${DB_NAME}`, `${DB_PORT}`
  - Prisma uses `DATABASE_URL`
  - Never commit secrets; keep `.env`/`backend/.env` local-only and consistent with compose.

### Critical Don’t-Miss Rules

- **One route = one contract**: don’t mix controller-style responses (`{ message, data }`) with raw model responses for the same endpoint—pick one response shape/status pattern per route and stick to it.
- **No per-request Prisma clients**: never create `new PrismaClient()` inside handlers/services; use the singleton attached to `req.prisma`.
- **Uploads can break on cwd changes**: `multer` uses a relative destination (`../uploads/`). If you change runtime cwd (Docker/service), verify upload paths still resolve correctly.
- **Change APIs as a set**: when you change candidate payloads, update together:
  - validation (`backend/src/application/validator.ts`)
  - docs (`backend/api-spec.yaml`)
  - persistence (`backend/prisma/schema.prisma` + migrations)
- **DB test safety**: never point test runs at a shared/dev/prod DB. If you add integration tests, require an isolated test DB + reset strategy.
- **Frontend configuration**: avoid scattering `http://localhost:3010`; if you introduce environment config, centralize base URL and use CRA `REACT_APP_*`.
- **Testing wiring gotcha**: if you add the first frontend tests, fix/standardize the `frontend` test command (currently expects a missing `jest.config.js`).

---

## Usage Guidelines

**For AI Agents**

- Read this file before implementing any change.
- Follow the rules as written; if you need to violate one, document why in the PR/commit.
- When in doubt, prefer the more conservative change (least moving parts, least cross-package churn).

**For Humans**

- Keep this file lean; delete rules that become “obvious”.
- Update the stack section when dependency versions/tooling change.
- Revisit whenever you notice repeated AI mistakes.

Last Updated: 2026-04-19
