---
project_name: 'LTI - Talent Tracking System'
user_name: 'Juanfer Lopez'
date: '2026-04-26'
sections_completed: ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules', 'quality_rules', 'workflow_rules']
existing_patterns_found: 24
status: 'complete'
rule_count: 56
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

### Repo Layout

- Monorepo-style folders: `frontend/` for the React app, `backend/` for the Express API, and light root tooling.
- Root `package.json` has Prisma schema routing (`backend/prisma/schema.prisma`) and Jest/TypeScript dev dependencies. Do not treat root tooling as the package standard for backend or frontend changes.

### Backend (`backend/`)

- Runtime: Node.js.
- Framework: Express `^4.19.2`.
- Language: TypeScript `^4.9.5`; `backend/tsconfig.json` uses `"module": "commonjs"`, `"target": "es5"`, `"strict": true`, and `"outDir": "./dist"`.
- ORM/DB: Prisma CLI/client `^5.13.0` plus PostgreSQL from root `docker-compose.yml`.
- Database container: `pgvector/pgvector:pg18`, container name `lti-db`, host port from `${DB_PORT}`.
- Tests: Jest `^29.7.0` with `ts-jest` `^29.2.5`; local config exists at `backend/jest.config.js`.
- Lint/format: ESLint `^9.2.0` and Prettier `^3.2.5`; backend `.prettierrc` uses `singleQuote: true` and `trailingComma: all`.
- Prisma binary targets: `["native", "debian-openssl-3.0.x"]`.

### Frontend (`frontend/`)

- Framework: React `^18.3.1` with Create React App `react-scripts@5.0.1`.
- Language: mixed JS and TS; `allowJs: true`, `strict: true`, `isolatedModules: true`, `jsx: "react-jsx"`.
- Routing: `react-router-dom` `^6.23.1`.
- UI: Bootstrap `^5.3.3`, React-Bootstrap `^2.10.2`, React Bootstrap Icons `^1.11.4`, and `react-datepicker` `^6.9.0`.
- HTTP calls currently use both native `fetch` and `axios`. `frontend/src/services/candidateService.js` imports `axios`, but `frontend/package.json` does not declare `axios`; fix the dependency or remove the unused service before relying on it.

## Critical Implementation Rules

### Language-Specific Rules

- Backend TypeScript strict mode is enabled. Avoid spreading `any`; narrow `unknown` in catches and add local types at API boundaries when touching code.
- Backend is CommonJS. Do not introduce ESM-only runtime patterns unless the build/runtime contract is intentionally changed.
- Backend build/runtime contract: `npm run build` emits `backend/dist/`; `npm start` runs `node dist/index.js`.
- Frontend is mixed JS/TS. Match the file's language. If adding typed React code, prefer `.tsx`; do not add TypeScript syntax to existing `.js` files.
- Several source comments and UI strings contain mojibake from broken encoding. When editing touched files, preserve intended Spanish text and save as UTF-8.
- Current backend code still uses some `any` in domain/service layers. Do not expand this pattern; tighten types only in the area being changed to avoid a broad refactor.

### Framework-Specific Rules

#### Backend: Express + Prisma

- The app exports `app` from `backend/src/index.ts`, but it also calls `app.listen(...)` in the same file. Importing `app` in integration tests can start the server unless this is refactored.
- `Express.Request` is extended with `prisma`, and middleware attaches a singleton client, but current domain models (`Candidate`, `Education`, `WorkExperience`, `Resume`) also create module-level `new PrismaClient()` instances. Do not add a third Prisma access style; either follow the existing model pattern locally or perform an explicit refactor.
- Current `/candidates` route calls the service function `addCandidate` via a controller barrel export, not `addCandidateController`. Controller tests cover response shapes that are not currently wired to the route. If changing route behavior, update route, controller tests, and API docs together.
- Middleware order matters: JSON parsing, Prisma attachment, and CORS are mounted before routes. The request logging middleware is currently mounted after `/candidates` and `/upload`, so it does not log those route hits.
- CORS is fixed to `http://localhost:3000` with credentials. Do not use `*` with credentials; add explicit origins if needed.
- Uploads use Multer with multipart field name `file`, allow only PDF and DOCX MIME types, and limit size to 10MB.
- Upload destination is a relative path (`../uploads/`). Verify behavior whenever the process working directory, Docker setup, or deployment layout changes.
- Candidate creation is not transactional: candidate, education, work experience, and resume rows are saved in separate calls. If changing multi-table persistence, consider a Prisma transaction.
- Prisma unique email errors are mapped from `P2002` to a user-facing duplicate email error. Preserve clear API errors when adding constraints.

#### Frontend: CRA + React

- Stay within CRA conventions unless explicitly migrating tooling. Do not eject casually.
- `frontend/src/App.js` contains the recruiter dashboard routes; `frontend/src/App.tsx` is still CRA boilerplate. Verify which app root is bundled before editing the root component, and avoid maintaining duplicate app entry behavior.
- Prefer existing React-Bootstrap components and Bootstrap layout utilities for UI changes.
- API base URL is hardcoded as `http://localhost:3010` in multiple places. If adding environment config, centralize it and use CRA `REACT_APP_*` variables.
- Upload flow sends `FormData` with field name `file`; backend rejects other field names.
- Form dates are converted to `YYYY-MM-DD` before API submission. Keep this contract aligned with backend validators.

### Testing Rules

- Backend tests exist and run through `backend/jest.config.js` using `ts-jest`.
- Existing backend test files are colocated as `*.test.ts` next to the code under test, e.g. `candidateController.test.ts`, `candidateService.test.ts`, `validator.test.ts`, and `Education.test.ts`.
- Backend tests rely heavily on Jest mocks for services, domain models, and Prisma client. Follow this style for unit tests unless adding a deliberate integration-test layer.
- Run backend tests from `backend/` with `npm test`.
- No frontend test files are currently checked in.
- Frontend `npm test` is currently miswired to `jest --config jest.config.js`, but `frontend/jest.config.js` does not exist. Prefer CRA's `react-scripts test` or add a real Jest config before introducing frontend tests.
- DB integration tests need an isolated test database and reset/migration strategy. Never point automated tests at shared dev/prod data.

### Code Quality & Style Rules

- Format backend code with `backend/.prettierrc`: single quotes and trailing commas.
- Backend ESLint extends Prettier integration. Prefer fixing lint issues instead of disabling rules inline.
- Keep backend code in the current structure: `routes/`, `presentation/controllers/`, `application/services/`, `application/validator.ts`, and `domain/models/`.
- When changing candidate API contracts, update the full set: runtime validation, `backend/api-spec.yaml`, Prisma schema/migrations if persistence changes, and affected tests.
- Watch for existing API-doc drift: `api-spec.yaml` currently does not perfectly match validators/schema for some lengths and phone formats. Do not copy stale docs into new code without checking source of truth.
- Avoid noisy `console.log` in normal request paths. Existing logs are present; do not add more unless they are intentional diagnostics.
- Keep comments useful and current. Several comments are Spanish and some are encoding-damaged; fix comments when editing nearby code.

### Development Workflow Rules

- Run package commands from the package you changed: `backend/` for API work, `frontend/` for UI work.
- Backend scripts:
  - Dev: `npm run dev`
  - Build: `npm run build`
  - Start compiled app: `npm start`
  - Build then start: `npm run start:prod`
  - Prisma generate: `npm run prisma:generate`
  - Tests: `npm test`
- Frontend scripts:
  - Dev: `npm start`
  - Build: `npm run build`
  - Test command needs correction before use (`jest.config.js` is missing).
- Database and Prisma:
  - Start Postgres from repo root: `docker-compose up -d`
  - Run migrations from `backend/`: `npx prisma migrate dev`
  - Run client generation from `backend/`: `npx prisma generate`
  - On Windows, stop running backend/Node processes before regenerating Prisma Client if `query_engine-windows.dll.node` is locked.
- Environment variables:
  - Docker uses `DB_PASSWORD`, `DB_USER`, `DB_NAME`, and `DB_PORT`.
  - Prisma uses `DATABASE_URL` from `backend/.env` when running inside `backend/`.
  - Never commit secrets; keep `.env` and `backend/.env` local-only and consistent with compose.

### Critical Don't-Miss Rules

- Do not assume the controller response contract is the live route contract. Current route and controller code differ for candidate creation.
- Do not introduce more Prisma clients casually. The repo already has both request-attached Prisma and model-level clients; choose deliberately.
- Do not change candidate payload fields in only one layer. Keep frontend form shape, validator, API spec, Prisma schema, service logic, and tests aligned.
- Do not rely on `frontend/src/services/candidateService.js` until the missing `axios` dependency is resolved or the service is converted to `fetch`.
- Do not edit `frontend/src/App.tsx` assuming it controls the current recruiter UI without checking the actual bundled app root.
- Do not run Prisma generate while the compiled backend is running on Windows; the query engine DLL can be locked.
- Do not use frontend `npm test` as-is; fix the missing Jest config or use CRA's default test runner first.
- Do not add upload fields with a different name than `file`; the backend Multer handler uses `upload.single('file')`.
- Do not trust `api-spec.yaml` blindly for validation limits; compare it with `validator.ts` and `schema.prisma` before changing API behavior.

---

## Usage Guidelines

**For AI Agents**

- Read this file before implementing any change.
- Follow the rules as written; if a rule must be violated, document why in the PR/commit.
- Prefer the smallest coherent change that keeps package boundaries and runtime contracts intact.

**For Humans**

- Keep this file lean; delete rules that become obvious or obsolete.
- Update the stack section when dependencies, scripts, or tooling change.
- Revisit whenever repeated AI implementation mistakes appear.

Last Updated: 2026-04-26
