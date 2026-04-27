# Migration Risk Report — Step 6 (Optimization Migration)

> Generated: 2026-04-28
> Branch: `feat/update-migrate-db-JFL`
> Skill: `db-tune-and-report` — Step 6
> Reviewed by: db-tune-and-report skill (Step 6)

---

## Migration under review

**File:** `backend/prisma/migrations/20260428120000_optimize_r4_stalled_partial_idx/migration.sql`
**Status:** APPLIED ✅ (applied to dev database during Step 5 — this review covers production promotion)
**Phase:** ADDITIVE — one CREATE INDEX, nothing dropped or altered.

---

## Row Counts at Review Time

| Table | Total rows | Active rows (scoped by index) |
|---|---|---|
| Application | 1,000 | 841 (status NOT IN HIRED, REJECTED, WITHDRAWN) |

---

## Index Confirmed Live

```
indexname: Application_active_status_idx
indexdef : CREATE INDEX "Application_active_status_idx"
             ON public."Application" USING btree (status)
             WHERE (status <> ALL (ARRAY[
               'HIRED'::"ApplicationStatus",
               'REJECTED'::"ApplicationStatus",
               'WITHDRAWN'::"ApplicationStatus"
             ]))
size     : 16 kB (dev seed — 841 active rows)
```

---

## Summary

**Verdict: `safe-with-recipe`**

The single DDL operation is additive (no DROP, no ALTER TYPE, no SET NOT NULL, no partitioning). It is safe at dev scale and correct in production — but `CREATE INDEX` without `CONCURRENTLY` acquires a `SHARE` lock that blocks all writes on the `Application` table for the duration of the build. At production row counts (≥100K rows) this lock can last seconds, which is unacceptable for a live ATS where applications are constantly being submitted. The recipe below describes the safe production path.

No materialized view is present; the MV addendum is not applicable.

---

## Findings

| # | Operation | Table | Rows | Short-term Risk | Risk Narrative | Mitigation |
|---|---|---|---|---|---|---|
| 1 | `CREATE INDEX "Application_active_status_idx" … WHERE status NOT IN (…)` | Application | 1,000 dev / unknown prod | **low (dev) / medium (prod at scale)** | Without `CONCURRENTLY`, PostgreSQL takes a `SHARE` lock for the full index build duration. At 1K rows this is sub-millisecond. At 100K rows expect 100ms–2s; at 1M rows expect 2–30s of write blocking on Application. | Use the production recipe below: apply via psql with `CONCURRENTLY`, then resolve in Prisma. |

### Why not just add CONCURRENTLY to the migration file?

`CREATE INDEX CONCURRENTLY` cannot run inside a transaction. Prisma wraps every migration in `BEGIN … COMMIT`, so including `CONCURRENTLY` in a migration file causes Prisma to fail with:

```
ERROR: CREATE INDEX CONCURRENTLY cannot run inside a transaction block
```

The migration file is correct as written. The production-safe path is handled out-of-band (see recipe below).

---

## Production Promotion Recipe

### Option A — Low-traffic maintenance window (simplest)

Apply the Prisma migration normally during a low-traffic window (e.g. off-peak hours). The SHARE lock duration at production scale is typically 100ms–2s per 100K rows. If Application write latency during that window is acceptable, no special steps are needed.

```bash
# From backend/, against the production DATABASE_URL:
npx prisma migrate deploy
```

### Option B — Zero-downtime manual index creation (recommended for high-traffic production)

Build the index out-of-band with `CONCURRENTLY` before Prisma marks the migration as applied. This allows Application writes to continue unblocked throughout the index build.

```sql
-- Step 1: run via psql against the production database (outside any transaction):
CREATE INDEX CONCURRENTLY "Application_active_status_idx"
    ON "Application" ("status")
    WHERE status NOT IN ('HIRED', 'REJECTED', 'WITHDRAWN');

-- Step 2: verify the index is valid (not just created):
SELECT indexname, indisvalid
FROM pg_stat_user_indexes
JOIN pg_index ON indexrelid = (
    SELECT oid FROM pg_class WHERE relname = 'Application_active_status_idx'
)
WHERE relname = 'Application_active_status_idx';
-- Expected: indisvalid = true
```

```bash
# Step 3: mark the migration as applied in Prisma's _prisma_migrations table
# without re-executing the SQL (the index already exists):
npx prisma migrate resolve --applied 20260428120000_optimize_r4_stalled_partial_idx
```

### Rollback

```sql
DROP INDEX CONCURRENTLY "Application_active_status_idx";
```

`CONCURRENTLY` is safe for DROP too and avoids the write lock. Confirm the index is not backing a UNIQUE or PRIMARY KEY constraint before dropping (it is not — it is a plain partial btree index).

---

## MV / Partitioning Addendum

| Check | Result |
|---|---|
| Materialized view present | No |
| Partitioning present | No |
| DROP INDEX present | No |
| `CREATE INDEX CONCURRENTLY` | No — migration uses plain `CREATE INDEX` (see recipe above) |
| Index backs a UNIQUE or PK constraint | No — plain partial btree, safe to drop |
| Refresh ownership required | N/A |

---

## Long-term Risk & Adjacent Considerations

| Item | Risk | Action |
|---|---|---|
| Index size at production scale | 16 kB at 841 rows → ~2 MB at 100K active rows | Acceptable; partial index covers ~15% of total rows at typical ATS retention |
| Index maintenance overhead | Every INSERT/UPDATE/DELETE on Application checks the partial index predicate and updates if row matches | Low — predicate evaluation is O(1) per write; only active-status rows are indexed |
| Existing overlapping indexes | `Application_positionId_status_idx` and `Application_candidateId_status_idx` both carry `status` as a non-leading column | No conflict; the new partial index is complementary for queries that filter solely on active status without a leading position/candidate predicate |
| Prisma schema drift | Partial indexes are not representable in `schema.prisma`; this index is managed only via raw migration SQL | Document in team wiki; add a comment to `schema.prisma` above the Application model |

---

## Decision

**Accepted.** Migration `20260428120000_optimize_r4_stalled_partial_idx` applied to dev database.
For production promotion, use **Option A** (maintenance window) or **Option B** (CONCURRENTLY + migrate resolve) per traffic SLA.

### Post-acceptance actions completed

| Action | Result |
|---|---|
| Migration confirmed in `_prisma_migrations` | ✅ `finished_at: 2026-04-27T22:59:33.017Z`, `applied_steps_count: 1` |
| Index confirmed live in `pg_indexes` | ✅ `Application_active_status_idx` — 16 kB, 841 active rows indexed |
| `schema.prisma` comment added above `Application` model | ✅ Documents the raw-SQL partial index and migration reference; Prisma Client regeneration not required (no model/field changes) |

---

## Full Migration History (9 migrations applied)

| # | Migration | Timestamp | Scope |
|---|---|---|---|
| 1 | `init` | 20260426182554 | Candidate, Education, WorkExperience, Resume |
| 2 | `add_ats_core_entities` | 20260426221733 | 8 new ATS tables + FKs + timestamps |
| 3 | `alter_candidate_phone_address_not_null` | 20260426222506 | Candidate.phone + Candidate.address → NOT NULL |
| 4 | `add_indexes` | 20260426223310 | 17 indexes (FK + composite + unique) |
| 5 | `add_enums` | 20260426223656 | 5 enum types, 5 columns converted |
| 6 | `enable_pgvector` | 20260426224150 | vector extension enabled |
| 7 | `add_common_query_indexes` | 20260427011538 | I1 composite + I2/I3 partial indexes on Interview/Position |
| 8 | `normalize_3nf_expand` | 20260427133809 | Address table, Candidate.addressId, Company.description, FileType enum, Resume.fileTypeParsed |
| 9 | `optimize_r4_stalled_partial_idx` | 20260428120000 | Partial index on Application (active statuses) for R4 optimization |
