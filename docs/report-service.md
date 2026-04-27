# Reports Service Guide

> Generated: 2026-04-28
> Branch: `feat/update-migrate-db-JFL`
> Skill: `db-tune-and-report` — Step 7 (final)
>
> **This is a GUIDE, not an implementation.**
> Do not add code under `backend/src/` as part of this PR.
> Open a follow-up task referencing this file and `docs/common-report-queries.sql`.

---

## Overview

This document describes how to expose the five ATS report queries as typed methods on a future `ReportsService`. Each report uses CTEs and/or window functions that Prisma's relational query API (`findMany`, `groupBy`) cannot express. The recommended implementation approach for all five is **Prisma TypedSQL**.

All SQL is in `docs/common-report-queries.sql`. Row counts and EXPLAIN plans were validated against a 1,000-application seed (Step 4). R4 was optimized in Step 5 (query rewrite + partial index).

---

## Prisma TypedSQL Setup (required for all 5 reports)

TypedSQL is a Prisma 5.19+ preview feature that generates TypeScript types from raw `.sql` files placed under `backend/prisma/sql/`.

### 1. Enable the preview feature

In `backend/prisma/schema.prisma`, add `"typedSql"` to `previewFeatures`:

```prisma
generator client {
  provider        = "prisma-client-js"
  previewFeatures = ["postgresqlExtensions", "typedSql"]   // add "typedSql"
  binaryTargets   = ["native", "debian-openssl-3.0.x"]
}
```

### 2. Place SQL files

```
backend/prisma/sql/
  r1PipelineFunnel.sql
  r2RecruiterLeaderboard.sql
  r3TimeToHire.sql
  r4StalledApplications.sql
  r5CandidateQuality.sql
```

Copy each query verbatim from `docs/common-report-queries.sql` (section references below). Replace `$1`, `$2` placeholders with named parameters using Prisma TypedSQL syntax: `-- @param {Int} $1:lookbackDays`.

### 3. Generate types

```bash
cd backend
npx prisma generate
```

This produces typed functions under `@prisma/client/sql` (e.g. `r1PipelineFunnel`).

> **Windows DLL lock warning:** stop `ts-node-dev` before running `prisma generate` — the running process holds the Prisma client DLL open and will cause a file-in-use error.

### 4. Call from service

```typescript
import { r1PipelineFunnel } from '@prisma/client/sql';

const rows = await prisma.$queryRawTyped(r1PipelineFunnel());
```

### Fallback (if TypedSQL is blocked)

If a team member is on Prisma < 5.19, use `$queryRaw` with a manually-written row interface:

```typescript
const rows = await prisma.$queryRaw<R1PipelineFunnelRow[]>`
  WITH status_order ...
`;
```

---

## R1 — Pipeline Funnel by Position

**SQL reference:** `docs/common-report-queries.sql` lines 11–71
**TypedSQL file:** `backend/prisma/sql/r1PipelineFunnel.sql`

### Purpose

Shows the stage-by-stage conversion ratio for every position. Recruiters and hiring managers use this to identify at which funnel stage (PENDING → SCREENING → INTERVIEW → OFFER → HIRED) candidates drop out, and to compare pipeline health across positions.

### Inputs

| Param | Type | Validation |
|---|---|---|
| *(none)* | — | Returns all positions with ≥ 1 application. Filter by `position_id` at the application layer if needed. |

### Output row shape

```typescript
interface R1PipelineFunnelRow {
  position_id:              number;
  position_title:           string;
  company_name:             string;
  status_name:              string;   // PENDING | SCREENING | INTERVIEW | OFFER | HIRED
  stage_order:              number;   // 1–5
  applications_in_stage:   bigint;
  prev_stage_count:         bigint | null;   // null at stage 1 (no prior stage)
  conversion_pct_from_prev: number | null;   // null at stage 1
}
```

### Prisma approach

**→ Use TypedSQL.** The query uses `LAG() OVER (PARTITION BY position_id ORDER BY stage_order)` and a VALUES CTE for stage ordering — both unsupported by Prisma's relational API.

### Caching

No materialized view. At production scale this aggregates the entire Application table. Recommended: 10-minute server-side cache keyed by `{ reportId: 'R1' }`, invalidated on application status change events.

### AuthZ

| Role | Access |
|---|---|
| ADMIN | All positions |
| HIRING_MANAGER | Positions belonging to their company only — add `WHERE p."companyId" = $companyId` |
| RECRUITER | Same scope as HIRING_MANAGER |

### Observability

```typescript
logger.info({ reportId: 'R1', paramsHash: null, durationMs, rowCount, cached });
```

---

## R2 — Recruiter Activity Leaderboard

**SQL reference:** `docs/common-report-queries.sql` lines 72–125
**TypedSQL file:** `backend/prisma/sql/r2RecruiterLeaderboard.sql`

### Purpose

Ranks active employees by interviews conducted and hires assisted within a configurable lookback window, partitioned per company. Used by HR admins and hiring managers to surface high-performing interviewers and detect workload imbalances.

### Inputs

| Param | TS type | Validation |
|---|---|---|
| `lookbackDays` | `number` (integer) | Min 1, max 365. Default: 90. |
| `topK` | `number` (integer) | Min 1, max 20. Default: 5. |

```typescript
// Zod example
const schema = z.object({
  lookbackDays: z.number().int().min(1).max(365).default(90),
  topK:         z.number().int().min(1).max(20).default(5),
});
```

### Output row shape

```typescript
interface R2RecruiterLeaderboardRow {
  rank_in_company:       bigint;
  company_name:          string;
  employee_name:         string;
  employee_role:         string;   // RECRUITER | HIRING_MANAGER | INTERVIEWER | ADMIN
  interviews_conducted:  bigint;
  hires_assisted:        bigint;
}
```

### Prisma approach

**→ Use TypedSQL.** The query uses `ROW_NUMBER() OVER (PARTITION BY companyId ORDER BY interviews_conducted DESC)` — no equivalent in Prisma's `groupBy`. The planner applies a `Run Condition` to prune window rows early when `rank_in_company <= topK`.

### Caching

No materialized view. Recommended: cache per `{ lookbackDays, topK }` with a 15-minute TTL — this is a dashboard fixture unlikely to need sub-minute freshness.

### AuthZ

| Role | Access |
|---|---|
| ADMIN | All companies |
| HIRING_MANAGER | Their company only — add `WHERE e."companyId" = $companyId` |
| RECRUITER | Not recommended — leaderboard exposes peer data |

### Observability

```typescript
logger.info({ reportId: 'R2', paramsHash: hash({ lookbackDays, topK }), durationMs, rowCount, cached });
```

---

## R3 — Time-to-Hire by Position / Company

**SQL reference:** `docs/common-report-queries.sql` lines 126–187
**TypedSQL file:** `backend/prisma/sql/r3TimeToHire.sql`

### Purpose

Computes median and p90 days from application submission to first interview for HIRED applications, grouped by position and company. Used by HR leadership to set recruiter SLAs and identify slow-moving pipelines.

### Inputs

| Param | Type | Validation |
|---|---|---|
| *(none)* | — | Returns all positions with ≥ 1 HIRED application. |

### Output row shape

```typescript
interface R3TimeToHireRow {
  position_id:          number;
  position_title:       string;
  company_name:         string;
  hires:                bigint;
  median_days_to_hire:  number | null;   // null if no measurable first-interview date
  p90_days_to_hire:     number | null;
  min_days:             number | null;
  max_days:             number | null;
}
```

> **Note:** "days to hire" is measured from `applicationDate` to the earliest `interviewDate` on the HIRED application — a proxy for time-to-first-contact, not time-to-offer. This is intentional: the schema does not store a discrete hire-decision timestamp. Document this definition in the API response.

### Prisma approach

**→ Use TypedSQL.** The query uses `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_hire)` and `PERCENTILE_CONT(0.9)` — PostgreSQL ordered-set aggregates with no Prisma equivalent.

### Caching

No materialized view. This report is low-frequency (weekly / monthly SLA review). Recommended: 1-hour cache per `{ reportId: 'R3' }` or compute on demand without caching.

### AuthZ

| Role | Access |
|---|---|
| ADMIN | All positions |
| HIRING_MANAGER | Their company only — add `WHERE p."companyId" = $companyId` |
| RECRUITER | Not recommended — aggregate SLA data is management-level |

### Observability

```typescript
logger.info({ reportId: 'R3', paramsHash: null, durationMs, rowCount, cached });
```

---

## R4 — Stalled Applications *(optimized — Step 5, P3)*

**SQL reference:** `docs/common-report-queries.sql` lines 188–263
**TypedSQL file:** `backend/prisma/sql/r4StalledApplications.sql`

### Purpose

Returns active applications (not HIRED / REJECTED / WITHDRAWN) with no interview activity for more than N days. Used daily by recruiters to triage neglected candidates before SLA breach. The `oldest_stall_rank` column identifies the single most-neglected application per position for quick action.

### Optimization note

This report was optimized in Step 5 (P3). The query uses a `LATERAL` subquery and a `pre_filtered` CTE to apply the stall threshold before `ROW_NUMBER()`, reducing window input by 33% at seed scale. A partial index (`Application_active_status_idx`) was added in migration `20260428120000_optimize_r4_stalled_partial_idx` to accelerate the `status NOT IN (…)` filter at production scale (≥10K Application rows).

### Inputs

| Param | TS type | Validation |
|---|---|---|
| `stallThresholdDays` | `number` (integer) | Min 1, max 90. Default: 14. |

```typescript
const schema = z.object({
  stallThresholdDays: z.number().int().min(1).max(90).default(14),
});
```

### Output row shape

```typescript
interface R4StalledApplicationRow {
  application_id:       number;
  position_title:       string;
  candidate_name:       string;
  status_name:          string;   // PENDING | SCREENING | INTERVIEW
  application_date:     Date;
  last_interview_date:  Date | null;   // null = no interview yet
  idle_days:            number;
  oldest_stall_rank:    bigint;   // rank within position (1 = most stalled)
}
```

### Prisma approach

**→ Use TypedSQL.** The query uses `ROW_NUMBER() OVER (PARTITION BY position_id)`, a `LATERAL` subquery for `MAX(interviewDate)`, and a pre-filter CTE — none of which are expressible via Prisma's relational API.

### Caching

No materialized view. This is the recruiter's **daily triage report** — freshness matters. Recommended: 5-minute server-side cache per `{ stallThresholdDays }`, invalidated on Interview or Application write events.

**Future consideration:** if this report is embedded in a dashboard with sub-second refresh requirements, promote to a materialized view refreshed every 5 minutes via a cron job or an after-write trigger on the `Interview` table. Refresh must use `REFRESH MATERIALIZED VIEW CONCURRENTLY` (requires a `UNIQUE INDEX` on the MV). Document ownership before enabling.

### AuthZ

| Role | Access |
|---|---|
| ADMIN | All applications |
| RECRUITER | Applications for positions they manage — add `WHERE e."id" = $employeeId` join via Interview |
| HIRING_MANAGER | Positions belonging to their company |

### Observability

```typescript
logger.info({
  reportId: 'R4',
  paramsHash: hash({ stallThresholdDays }),
  durationMs,
  rowCount,
  cached,
});
```

---

## R5 — Candidate Quality by Education Institution

**SQL reference:** `docs/common-report-queries.sql` lines 264–320
**TypedSQL file:** `backend/prisma/sql/r5CandidateQuality.sql`

### Purpose

Ranks candidate feeder institutions by average and p75 interview scores. Computed using a two-tier aggregation (per-candidate average first, then per-institution) to avoid Simpson's paradox. Used by HR leadership and sourcing teams to identify which universities and programs produce top performers.

### Inputs

| Param | Type | Validation |
|---|---|---|
| *(none)* | — | Returns all institutions with ≥ 1 candidate with a scored interview. |

### Output row shape

```typescript
interface R5CandidateQualityRow {
  quality_rank:           bigint;
  institution:            string;
  candidates_evaluated:   bigint;
  avg_interview_score:    number;   // ROUND(..., 2)
  p75_interview_score:    number;   // ROUND(..., 2)
  total_interviews:       number;
}
```

### Prisma approach

**→ Use TypedSQL.** The query uses `PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY avg_score)` and `DENSE_RANK() OVER (ORDER BY p75_score DESC)` — both unsupported by Prisma's relational API.

### Caching

No materialized view. This is a low-frequency strategic report (weekly / monthly sourcing review). Recommended: 1-hour cache per `{ reportId: 'R5' }` or on-demand computation with no cache.

### AuthZ

| Role | Access |
|---|---|
| ADMIN | All institutions |
| HIRING_MANAGER | Restrict to candidates who applied to their company's positions — add a `WHERE EXISTS (SELECT 1 FROM "Application" a JOIN "Position" p …)` clause |
| RECRUITER | Same as HIRING_MANAGER |

### Observability

```typescript
logger.info({ reportId: 'R5', paramsHash: null, durationMs, rowCount, cached });
```

---

## Shared Observability Contract

All five reports should emit a structured log entry on every execution:

```typescript
interface ReportLogEntry {
  reportId:   'R1' | 'R2' | 'R3' | 'R4' | 'R5';
  paramsHash: string | null;   // stable hash of input params; null if report has no params
  durationMs: number;          // wall-clock time for the DB round-trip
  rowCount:   number;
  cached:     boolean;         // true if served from cache without hitting DB
}
```

Use `paramsHash` (e.g. `crypto.createHash('sha1').update(JSON.stringify(params)).digest('hex').slice(0, 8)`) to correlate repeated calls with the same parameters in your APM tool.

---

## Raw-SQL Partial Index — Maintenance Note

Migration `20260428120000_optimize_r4_stalled_partial_idx` created a partial index that is not visible in `schema.prisma` (Prisma does not support partial index syntax in the schema file). The index is documented via a comment above the `Application` model:

```
// NOTE: a partial index on active statuses exists in raw SQL (not expressible in Prisma schema):
//   "Application_active_status_idx" ON "Application"(status)
//   WHERE status NOT IN ('HIRED','REJECTED','WITHDRAWN')
```

If a future migration drops and recreates the `Application` table, this index must be manually re-applied. Add a check to your migration review checklist.

---

## Follow-up Tasks (do not implement in this PR)

| Task | Depends on | Priority |
|---|---|---|
| Implement `ReportsService` with all 5 TypedSQL methods | This guide + `docs/common-report-queries.sql` | High |
| Enable `typedSql` preview feature in `schema.prisma` | TypedSQL setup section above | High (prerequisite for implementation) |
| Add authZ scoping per role per report (see AuthZ tables above) | Existing auth middleware | High |
| Add 5-minute cache for R4 with Interview/Application write invalidation | R4 implementation | Medium |
| Evaluate R4 materialized view if dashboard sub-second refresh is required | R4 cache monitoring | Low / deferred |
| Contract migration: DROP COLUMN `Candidate.address`, SET NOT NULL on `addressId`, swap `Resume.fileType` to enum | App layer cutover to Address model | Medium |
| Contract migration: DROP COLUMN `Position.companyDescription` | App layer writing `Company.description` | Medium |
