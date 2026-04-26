# Migration Checklist (Step 3 output)

> Generated: 2026-04-27  
> Branch: `feat/update-migrate-db-JFL`  
> All 5 migrations applied. Prisma Client regenerated. pgvector 0.8.2 enabled.

---

## Decisions Applied

| # | Topic | Pick |
|---|---|---|
| 1 | Casing convention | PascalCase (Option A) — consistent with existing tables |
| 2 | Schema additions | Full set — all 8 ERD entities |
| 3 | `Position.status` | ENUM `PositionStatus` |
| 4 | `Employee.role` | ENUM `EmployeeRole` |
| 5 | `Interview.result` | ENUM `InterviewResult` |
| 6 | `Position.employmentType` | ENUM `EmploymentType` |
| 7 | `Application.status` | ENUM `ApplicationStatus` |
| 8 | Index set | All from recommendation report §3 |
| 9 | Timestamps | `createdAt`/`updatedAt TIMESTAMPTZ(6)` on all new tables |
| 10 | Soft-delete | None — deferred |
| 11 | pgvector | Extension enabled (`vector 0.8.2`); no columns yet |
| 12 | Migration granularity | Staged — 5 migrations |
| 13 | Prisma access pattern | Module-level `new PrismaClient()` in `domain/models/` |

---

## Migrations Applied

| Migration | Timestamp | Scope |
|---|---|---|
| `init` | 20260426182554 | Candidate, Education, WorkExperience, Resume (pre-existing) |
| `add_ats_core_entities` | 20260426221733 | 8 new tables + FKs + CHECK constraints + timestamps |
| `alter_candidate_phone_address_not_null` | 20260426222506 | `Candidate.phone` + `Candidate.address` → NOT NULL |
| `add_indexes` | 20260426223310 | 17 indexes (FK + composite + unique) |
| `add_enums` | 20260426223656 | 5 enum types, 5 columns converted |
| `enable_pgvector` | 20260426224150 | `CREATE EXTENSION IF NOT EXISTS vector` |

---

## Adjacent-File Sync Checklist

These files were **not modified** during the migration. They must be updated before the new entities are usable end-to-end. Hand this list to a follow-up task or PR.

### Domain Models (`backend/src/domain/models/`)

Use the module-level `new PrismaClient()` pattern, consistent with existing `Candidate.ts`, `Education.ts`, `WorkExperience.ts`, `Resume.ts`.

- [ ] `Company.ts`
- [ ] `Employee.ts`
- [ ] `InterviewFlow.ts`
- [ ] `InterviewType.ts`
- [ ] `InterviewStep.ts`
- [ ] `Position.ts`
- [ ] `Application.ts`
- [ ] `Interview.ts`

### Application Services (`backend/src/application/services/`)

- [ ] Service functions for Company CRUD
- [ ] Service functions for Employee CRUD
- [ ] Service functions for InterviewFlow + InterviewStep + InterviewType CRUD
- [ ] Service functions for Position CRUD
- [ ] Service functions for Application CRUD (status transitions via `ApplicationStatus` enum)
- [ ] Service functions for Interview CRUD (result via `InterviewResult` enum)

### Validators (`backend/src/application/validator.ts`)

- [ ] Add payload validators for each new entity (align lengths, required fields, and enum values with `schema.prisma`)
- [ ] Verify `Candidate` validator enforces `phone` and `address` as required (they are now NOT NULL)

### Controllers (`backend/src/presentation/controllers/`)

- [ ] Controllers for each new entity following the existing barrel-export pattern

### Routes (`backend/src/routes/` or equivalent)

- [ ] Register routes for new controllers; mount before the request-logger middleware (see `project-context.md` on middleware order)

### API Spec (`backend/api-spec.yaml`)

- [ ] Document all new endpoints
- [ ] Add enum schemas for `PositionStatus`, `ApplicationStatus`, `EmployeeRole`, `InterviewResult`, `EmploymentType`
- [ ] Update `Candidate` spec to mark `phone` and `address` as required

### Tests (`backend/src/**/*.test.ts`)

- [ ] Unit tests for each new service (mock Prisma client, follow `candidateService.test.ts` style)
- [ ] Unit tests for each new controller (mock service, follow `candidateController.test.ts` style)
- [ ] Update `Candidate`-related tests if any relied on `phone`/`address` being optional

### Runtime

- [ ] Restart backend — Prisma Client was regenerated; the running process has the old build

---

## Enums Reference

```ts
// Available in @prisma/client after prisma generate

enum PositionStatus    { DRAFT, OPEN, PAUSED, CLOSED, CANCELLED }
enum ApplicationStatus { PENDING, SCREENING, INTERVIEW, OFFER, HIRED, REJECTED, WITHDRAWN }
enum EmployeeRole      { RECRUITER, HIRING_MANAGER, INTERVIEWER, ADMIN }
enum InterviewResult   { PENDING, PASS, FAIL, ON_HOLD }
enum EmploymentType    { FULL_TIME, PART_TIME, CONTRACT, INTERNSHIP, TEMPORARY }
```

---

## Future Migrations (not yet scheduled)

| When | What |
|---|---|
| When semantic search is approved | Add `vector(N)` columns + ivfflat or hnsw index to relevant tables (Candidate resume, Position job description) |
| If soft-delete is needed | Add `deletedAt TIMESTAMPTZ NULL` to Application and/or Interview |
| If multi-region search is needed | Split `Candidate.address` into structured fields |
