# Migration Recommendation Report (Step 2 output)

> Generated: 2026-04-27  
> Source ERD: `docs/ERD-mermaid.md`  
> Target DB: PostgreSQL 18 (`pgvector/pgvector:pg18`, container `lti-db`)  
> ORM: Prisma ^5.13.0

---

## Live DB Snapshot

| Item | Value |
|---|---|
| Extensions | `plpgsql 1.0` — `vector` NOT enabled |
| User tables | `Candidate`, `Education`, `Resume`, `WorkExperience` |
| Row counts | All 0 (empty) — lock risk = zero for every pending ALTER |
| Applied migrations | `20260426182554_init` (2026-04-26, not rolled back) |
| Indexes | 4× PK + `Candidate_email_key` UNIQUE — no FK indexes |

---

## 1. Gap Analysis

| Op | Object | Source of truth | Recommended change | Risk | Reason |
|---|---|---|---|---|---|
| ADD | 8 new tables (see §6) | ERD | New Prisma models + migration | Low — all new | Entire ATS core missing |
| MODIFY | `Candidate.phone` | ERD + Q1 | `ALTER COLUMN phone SET NOT NULL` | Zero — table empty | Q1: ERD wins over nullable |
| MODIFY | `Candidate.address` | ERD + Q1 | `ALTER COLUMN address SET NOT NULL` | Zero — table empty | Q1: ERD wins over nullable |
| KEEP | `Education`, `WorkExperience`, `Resume` | schema.prisma | No change | n/a | Not in target ERD; business value preserved |
| INDEX | `Education.candidateId`, `WorkExperience.candidateId`, `Resume.candidateId` | Live DB gap | Add btree indexes | Zero | Pre-existing FK columns with no index |

**`schema.prisma` ↔ live DB drift:** None. Init migration applied cleanly; schema and DB are in perfect sync.

**Casing decision:** Option A — PascalCase for all new tables, consistent with existing convention (`Candidate`, `Education`, `WorkExperience`, `Resume`).

---

## 2. Normalization & Modeling

| Field | Type | Recommendation | Enum values |
|---|---|---|---|
| `Position.status` | TEXT → **Prisma enum** | `PositionStatus` | `DRAFT, OPEN, PAUSED, CLOSED, CANCELLED` |
| `Application.status` | TEXT → **Prisma enum** | `ApplicationStatus` | `PENDING, SCREENING, INTERVIEW, OFFER, HIRED, REJECTED, WITHDRAWN` |
| `Employee.role` | TEXT → **Prisma enum** | `EmployeeRole` | `RECRUITER, HIRING_MANAGER, INTERVIEWER, ADMIN` |
| `Interview.result` | TEXT → **Prisma enum** | `InterviewResult` | `PENDING, PASS, FAIL, ON_HOLD` |
| `Position.employmentType` | TEXT → **Prisma enum** | `EmploymentType` | `FULL_TIME, PART_TIME, CONTRACT, INTERNSHIP, TEMPORARY` |
| `Candidate.address` | VARCHAR | Keep single string | No multi-region search in scope |
| `Position.benefits` / `contactInfo` | TEXT | Keep TEXT | No structured query need |

---

## 3. Index Strategy

| Table | Columns | Type | Reason |
|---|---|---|---|
| `Education` | `candidateId` | btree | Pre-existing FK gap |
| `WorkExperience` | `candidateId` | btree | Pre-existing FK gap |
| `Resume` | `candidateId` | btree | Pre-existing FK gap |
| `Employee` | `companyId` | btree | FK join |
| `Position` | `companyId` | btree | FK join |
| `InterviewStep` | `interviewFlowId` | btree | FK join |
| `InterviewStep` | `interviewTypeId` | btree | FK join |
| `InterviewStep` | `(interviewFlowId, orderIndex)` | **UNIQUE btree** | Enforce ordered steps per flow |
| `Employee` | `(email, companyId)` | **UNIQUE btree** | Email unique within a company |
| `Application` | `positionId` | btree | FK join |
| `Application` | `candidateId` | btree | FK join |
| `Application` | `(positionId, status)` | composite btree | Hot recruiter board |
| `Application` | `(candidateId, status)` | composite btree | Candidate dashboard |
| `Interview` | `applicationId` | btree | FK join |
| `Interview` | `interviewStepId` | btree | FK join |
| `Interview` | `employeeId` | btree | FK join |
| `Interview` | `(applicationId, interviewDate)` | composite btree | Pipeline calendar view |
| `Position` | `(companyId, status)` | composite btree | Recruiter listing |

---

## 4. Integrity & Types

| Constraint | Table | Rule |
|---|---|---|
| CHECK | `Position` | `salary_min <= salary_max` (when both non-null) |
| CHECK | `Interview` | `score BETWEEN 0 AND 100` (when non-null) |
| Timestamps | All new tables | `createdAt TIMESTAMPTZ DEFAULT now()`, `updatedAt TIMESTAMPTZ DEFAULT now()` |
| `interviewDate` type | `Interview` | `TIMESTAMPTZ` (multi-timezone confirmed, Q7) |
| `Position.interviewFlowId` | `Position` | `@unique` — 1:1 with `InterviewFlow` confirmed (Q8) |
| Soft-delete | — | Deferred — not adopted in this migration set (Q5) |

---

## 5. pgvector

- Container `pgvector/pgvector:pg18` has the extension available.
- Live DB: `vector` NOT enabled.
- Q4 = YES: enable via `CREATE EXTENSION IF NOT EXISTS vector` in migration 5.
- No `vector(…)` columns added until an embedding feature is explicitly approved.
- Embedding pipeline is **out of scope** for this migration set.
- When adopted: compare `ivfflat` (cheap build, tune `lists`) vs `hnsw` (better recall, costlier build).

---

## 6. Prisma Migration Plan (staged, NOT YET EXECUTED)

All tables empty → lock risk = zero for all operations.

### Migration 1 — `add_ats_core_entities`
**Scope:** CREATE Company, InterviewFlow, InterviewType, Employee, InterviewStep, Position, Application, Interview — plus all FKs, check constraints, and timestamps.  
**Prisma models added:** Company, InterviewFlow, InterviewType, Employee, InterviewStep, Position, Application, Interview.  
**Rollback:** Drop the 8 tables in reverse dependency order: Interview → Application → Position → InterviewStep → Employee → InterviewFlow → InterviewType → Company.  
**Prisma access pattern:** Module-level `new PrismaClient()` in `domain/models/` — consistent with existing Candidate, Education, WorkExperience, Resume models.

### Migration 2 — `alter_candidate_phone_address_not_null`
**Scope:** `ALTER TABLE "Candidate" ALTER COLUMN phone SET NOT NULL; ALTER COLUMN address SET NOT NULL`.  
**Rollback:** `ALTER COLUMN phone DROP NOT NULL; ALTER COLUMN address DROP NOT NULL`.

### Migration 3 — `add_indexes`
**Scope:** All btree, composite, and unique indexes from §3, including pre-existing FK gaps on Education/WorkExperience/Resume.  
**Rollback:** `DROP INDEX` for each — no data loss.

### Migration 4 — `add_enums`
**Scope:** `CREATE TYPE` for PositionStatus, ApplicationStatus, EmployeeRole, InterviewResult, EmploymentType. `ALTER COLUMN … TYPE enum USING …::enum` on affected columns.  
**Rollback:** Forward-only in Prisma. Manual revert: `ALTER COLUMN … TYPE TEXT USING …::text`, then `DROP TYPE`.

### Migration 5 — `enable_pgvector` *(Q4)*
**Scope:** `CREATE EXTENSION IF NOT EXISTS vector`.  
**Rollback:** `DROP EXTENSION vector` (safe — no vector columns yet).

---

## 7. Resolved Decisions

| # | Topic | Decision |
|---|---|---|
| Q1 | Casing | PascalCase (Option A) |
| Q2 | Enum values | Confirmed as proposed |
| Q3 | Migration plan | Staged (5 migrations) |
| Q4 | Timestamps | Yes — createdAt/updatedAt on all new tables |
| Q5 | Soft-delete | No — deferred |
| Q6 | Prisma access pattern | Module-level `new PrismaClient()` |
| Q7 | interviewDate type | TIMESTAMPTZ |
| Q8 | Position↔InterviewFlow 1:1 | Confirmed UNIQUE |
