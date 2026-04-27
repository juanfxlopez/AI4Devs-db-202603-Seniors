# Step 4 Report — Report Queries, 1000-row Seed & Validation

> Generated: 2026-04-28
> Branch: `feat/update-migrate-db-JFL`
> Skill: `db-tune-and-report` — Step 4

---

## Deliverables

| File | Description |
|---|---|
| `docs/common-report-queries.sql` | 5 ATS report queries using CTEs + window functions |
| `backend/prisma/seed.test.ts` | Guarded, deterministic seed script (~1000 applications) |

---

## 1. Report Queries — `docs/common-report-queries.sql`

Five high-value recruiter/manager reports. Each uses CTEs (one per logical step) and window functions.

| ID | Report | Window Function(s) | Params |
|---|---|---|---|
| R1 | Pipeline Funnel by Position | `LAG() OVER (PARTITION BY position_id ORDER BY stage_order)` | none |
| R2 | Recruiter Activity Leaderboard | `ROW_NUMBER() OVER (PARTITION BY companyId ORDER BY interviews_conducted DESC)` | `$1` = lookback_days, `$2` = top_k |
| R3 | Time-to-Hire by Position / Company | `PERCENTILE_CONT(0.5/0.9) WITHIN GROUP (ORDER BY days_to_hire)` | none |
| R4 | Stalled Applications | `ROW_NUMBER() OVER (PARTITION BY position_id ORDER BY last_touch ASC)` | `$1` = stall_threshold_days |
| R5 | Candidate Quality by Education | `DENSE_RANK() OVER (ORDER BY p75_score DESC, avg_score DESC)` | none |

### Report Design Notes

**R1 — Pipeline Funnel:** A `status_order` VALUES CTE defines the linear funnel (PENDING → SCREENING → INTERVIEW → OFFER → HIRED). Terminal states (REJECTED, WITHDRAWN) are intentionally excluded — they are not part of the conversion funnel. `LAG()` computes stage-to-stage drop-off; `NULLIF(prev_stage_count, 0)` prevents division-by-zero at the top of the funnel.

**R2 — Recruiter Leaderboard:** Uses `ROW_NUMBER() OVER (PARTITION BY companyId ...)` to rank interviewers within each company without the `LIMIT-per-group` antipattern. The `Run Condition` optimization in PostgreSQL 14+ allows the planner to prune window rows early when `rank_in_company <= $2` is detected.

**R3 — Time-to-Hire:** Uses `PERCENTILE_CONT(0.5)` and `PERCENTILE_CONT(0.9)` as ordered-set aggregates (not window functions) inside a `GROUP BY` — these are valid PostgreSQL aggregate extensions. Days are measured from `applicationDate` to the `MIN(interviewDate)` of the hired application (first contact, not final decision, as an SLA-friendly proxy).

**R4 — Stalled Applications:** `COALESCE(last_interview_date, application_date::timestamptz)` computes the last-touch timestamp for applications with no interviews yet. `ROW_NUMBER() OVER (PARTITION BY position_id ORDER BY last_touch ASC)` identifies the most neglected application per position. The idle threshold filter (`idle_duration > $1 * INTERVAL '1 day'`) is applied after the window because it references the computed column.

**R5 — Candidate Quality:** Two-tier aggregation: first compute `AVG(score)` per candidate (`candidate_avg` CTE), then aggregate per institution with `PERCENTILE_CONT(0.75)`. This avoids the Simpson's paradox that would arise from computing the average across all interviews directly. `DENSE_RANK()` produces a stable ranking with no gaps on ties.

---

## 2. Seed Script — `backend/prisma/seed.test.ts`

### Design

| Property | Value |
|---|---|
| RNG seed | `faker.seed(20260427)` — deterministic, stable across reruns |
| Safety guard | `ALLOW_DESTRUCTIVE_SEED=true` required at runtime |
| Host guard | DATABASE_URL must contain `lti-db` or `localhost` |
| Truncate strategy | `TRUNCATE … RESTART IDENTITY CASCADE` before every run |
| FK insertion order | Company → InterviewType → InterviewFlow+Steps → Position → Employee → Candidate+Education → Application → Interview |

### Entity Counts

| Entity | Count | Notes |
|---|---|---|
| Company | 8 | |
| InterviewType | 5 | Shared across all flows |
| InterviewFlow | 30 | One per Position (required by `@unique` constraint) |
| InterviewStep | 100 | 3–4 steps per flow (3 patterns, cycled) |
| Position | 30 | 24 OPEN, 3 PAUSED, 3 CLOSED |
| Employee | 96 | 12 per company; roles biased toward INTERVIEWER |
| Candidate | 500 | |
| Education | 750 | 1–2 per candidate; 18-institution pool (for R5) |
| Application | 1,000 | Status-biased distribution (see below) |
| Interview | 728 | 0–3 per application; biased by application status |

### Application Status Distribution (weighted)

| Status | Weight | Target | Actual |
|---|---|---|---|
| PENDING | 45% | 450 | ~450 |
| SCREENING | 20% | 200 | ~200 |
| INTERVIEW | 15% | 150 | ~150 |
| OFFER | 5% | 50 | ~50 |
| HIRED | 5% | 50 | ~50 |
| REJECTED | 8% | 80 | ~80 |
| WITHDRAWN | 2% | 20 | ~20 |

### Interview Count per Application Status

| Status | Min Interviews | Max Interviews |
|---|---|---|
| PENDING | 0 | 0 |
| SCREENING | 0 | 1 |
| INTERVIEW | 1 | 3 |
| OFFER | 2 | 3 |
| HIRED | 2 | 3 |
| REJECTED | 0 | 2 |
| WITHDRAWN | 0 | 1 |

Intermediate interview steps always get `result = PASS`; the final step gets `PASS` (HIRED), `FAIL` (REJECTED), or `PENDING` (all others). Scores assigned with 85% probability, range 1–10.

### Run Command

```bash
cd backend
ALLOW_DESTRUCTIVE_SEED=true npx ts-node --transpile-only prisma/seed.test.ts
```

---

## 3. Issues Encountered and Resolutions

### Issue 1 — `@faker-js/faker` v9 incompatible with TypeScript 4.9.5

**Problem:** The project uses TypeScript `^4.9.5` and `ts-node` v9. Installing `@faker-js/faker` latest (v9) failed with cryptic type-definition errors:
```
node_modules/@faker-js/faker/dist/airline-eVQV6kbz.d.ts(3182,13): error TS1139:
Type parameter declaration expected.
```
Faker v9 uses `using` declarations (ES2022 explicit resource management), which requires TypeScript 5.

**Resolution:** Downgraded to `@faker-js/faker@8`:
```bash
npm install --save-dev @faker-js/faker@8
```
Faker v8 is fully compatible with TypeScript 4.x. The v8 API used (`faker.number.int`, `faker.helpers.arrayElement`, `faker.helpers.maybe`, etc.) is stable and unchanged in v8.

---

### Issue 2 — `ts-node` v9 crashes with TypeScript 4.9 on `resolveTypeReferenceDirectives`

**Problem:** `npx ts-node prisma/seed.test.ts` exited with:
```
Error: Debug Failure. False expression: Non-string value passed to
`ts.resolveTypeReferenceDirective`, likely by a wrapping package working
with an outdated `resolveTypeReferenceDirectives` signature.
```
`ts-node` v9 passes type reference directives as objects; TypeScript 4.9 expects strings. This is a known incompatibility in the ts-node@9 / ts@4.9 pairing.

**Resolution:** Used `--transpile-only` flag to skip type resolution entirely:
```bash
ALLOW_DESTRUCTIVE_SEED=true npx ts-node --transpile-only prisma/seed.test.ts
```
Type correctness was already verified by `tsc --noEmit --skipLibCheck` before running. `--transpile-only` is safe because it only skips the type-checking pass, not the transpilation.

---

### Issue 3 — `Position.interviewFlowId` has `@unique` — flows cannot be shared

**Problem:** The seed initially created 3 shared `InterviewFlow` records and assigned them to 30 positions cyclically. The second position creation failed:
```
PrismaClientKnownRequestError: Unique constraint failed on the fields: (`interviewFlowId`)
```
The Prisma schema declares `interviewFlowId Int @unique` on Position, meaning each flow belongs to exactly one position.

**Resolution:** Restructured the seed so each of the 30 positions gets its own dedicated `InterviewFlow` (30 flows total). Three step patterns (Standard 4-step, Fast-Track 3-step, Executive 3-step) are cycled across positions to maintain realistic variety. `stepsByPosition[positionIndex]` replaces the earlier `allSteps[flowIndex]` lookup.

---

### Issue 4 — DATABASE_URL uses `localhost`, not `lti-db` container name

**Problem:** The seed guard checked for `lti-db` in the DATABASE_URL, but the dev `.env` uses `localhost:5439` (port-forwarded from the Docker container):
```
DATABASE_URL="postgresql://LTIdbUser:***@localhost:5439/LTIdb"
```
This would have caused the script to refuse to run even on the correct dev database.

**Resolution:** Updated `ALLOWED_DB_HOSTS` to accept both `lti-db` and `localhost`:
```typescript
const ALLOWED_DB_HOSTS = ['lti-db', 'localhost'];
```
Production databases are never on `localhost`, so this remains a meaningful safety check.

---

## 4. EXPLAIN ANALYZE Results — All 5 Reports

> Seed: 1,000 applications, 728 interviews, 500 candidates, 750 education records.
> Parameters: R2 = 90-day lookback, top 5; R4 = 14-day stall threshold.

| Report | Rows Returned | Execution Time | Planning Time | Buffers Hit | Leading Plan Node |
|---|---|---|---|---|---|
| R1 Pipeline Funnel | 139 | 1.496 ms | 1.948 ms | 33 | WindowAgg (LAG) → Sort → HashAggregate |
| R2 Recruiter Leaderboard | 40 | **1.038 ms** ✅ | 2.285 ms | 51 | WindowAgg + Run Condition prune; Memoize on Company pkey |
| R3 Time-to-Hire | 26 | 1.350 ms | 1.066 ms | 341 | GroupAggregate (PERCENTILE_CONT) + Nested Loop × 153 |
| R4 Stalled Applications | 564 | **3.789 ms** ⚠️ | 2.275 ms | 40 | HashAggregate (169 kB) → WindowAgg → post-window filter |
| R5 Candidate Quality | 18 | 2.636 ms | 1.788 ms | 31 | GroupAggregate (PERCENTILE_CONT) over joined Education rows |

### R3 — High Buffer Hit Note

R3 has the highest buffer count (341 hits) despite a fast execution time. The cause is a Nested Loop joining Company via `Company_pkey` for each of 153 HIRED application rows (153 index lookups × 2 pages each = 306 buffer accesses). This is expected behavior for a small rowset with a high-selectivity join — the planner correctly chooses index scan over hash for 153 rows.

---

## 5. Costliest Report: R4 — Stalled Applications (3.789 ms execution)

### Plan breakdown

```
Sort (564 rows output)                                  ← final ORDER BY
  └── Subquery Scan on stall_calc
        Filter: idle_duration > 14 days                ← removes 277/841 rows
        └── WindowAgg (ROW_NUMBER per position)         ← must process all 841 rows first
              └── Sort (position_id, last_touch)
                    └── Subquery Scan on active_apps
                          └── HashAggregate (841 groups, 169 kB)  ← bottleneck
                                └── Hash Join Application ⟕ Interview
                                      └── Hash Join ⟕ Position
                                            └── Hash Join ⟕ Candidate
```

### Root causes (input to Step 5)

| # | Issue | Plan evidence |
|---|---|---|
| 1 | No index on `Application.status` for the `NOT IN (HIRED, REJECTED, WITHDRAWN)` filter | Seq Scan on Application, 159 rows removed by filter |
| 2 | `idle_duration > 14 days` filter applied **after** WindowAgg | 277 of 841 window rows discarded post-computation; wasted window work |
| 3 | `COALESCE(last_interview_date, application_date::timestamptz)` computed in both the WindowAgg ORDER BY and the WHERE clause | Double evaluation of the same expression |
| 4 | HashAggregate at 169 kB approaches spill threshold under higher load (typical limit is 4 MB per batch, but memory pressure compounds at scale) | `Batches: 1 Memory Usage: 169kB` |

---

## 6. Decisions Log

| # | Decision | Rationale |
|---|---|---|
| D1 | REJECTED and WITHDRAWN excluded from R1 funnel | They are terminal exits, not conversion stages — including them would distort the funnel ratio |
| D2 | R3 measures time to first interview, not time to final decision | First interview date is reliably tracked; final decision timestamp is not stored as a discrete event in the schema |
| D3 | Two-tier aggregation in R5 (per-candidate avg first, then per-institution) | Avoids Simpson's paradox; prevents institutions with many low-interview candidates from skewing the average |
| D4 | 30 InterviewFlows created (one per Position) | `Position.interviewFlowId @unique` constraint; flows are not reusable |
| D5 | `faker.seed(20260427)` | Deterministic reruns; matches the migration date used as the project reference date |

---

## 7. Next Step

**Step 5** — Optimize R4 (Stalled Applications).

Target: reduce execution time from 3.789 ms toward < 1 ms at current scale.
Approach: index on `Application.status` (or a partial index on active statuses), pre-filter before window, eliminate double COALESCE evaluation.
