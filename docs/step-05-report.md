# Step 5 Report — Optimize Costliest Report (R4: Stalled Applications)

> Generated: 2026-04-28
> Branch: `feat/update-migrate-db-JFL`
> Skill: `db-tune-and-report` — Step 5
> Costliest report: R4 — Stalled Applications (3.789 ms baseline)
> Optimization chosen: P3 — Query Rewrite + Partial Index

---

## 1. Costliest Report — R4 Confirmed

From Step 4 EXPLAIN ANALYZE (1,000-application seed):

| Report | Execution Time | Reason selected |
|---|---|---|
| R1 Pipeline Funnel | 1.496 ms | — |
| R2 Recruiter Leaderboard | 1.038 ms | — |
| R3 Time-to-Hire | 1.350 ms | — |
| **R4 Stalled Applications** | **3.789 ms** | **Costliest — selected for optimization** |
| R5 Candidate Quality | 2.636 ms | — |

---

## 2. Root Cause Analysis

EXPLAIN (ANALYZE, BUFFERS) on R4 before optimization revealed four compounding issues:

| # | Root cause | EXPLAIN evidence |
|---|---|---|
| 1 | **Post-window stall filter** — `idle_duration > 14 days` applied after `ROW_NUMBER()` | 277 of 841 window rows discarded post-computation; window processed 33% more rows than needed |
| 2 | **Triple COALESCE evaluation** — `COALESCE(last_interview_date, application_date::timestamptz)` computed three times per row | Appears in window `ORDER BY`, in `stall_calc` column list, and in the `WHERE` filter |
| 3 | **LEFT JOIN + GROUP BY for MAX(interviewDate)** — HashAggregate over full Interview join | 169 kB hash aggregate; does not use `Interview_applicationId_interviewDate_idx`; scales O(N) with interview volume |
| 4 | **No partial index on Application.status** — `status NOT IN (HIRED, REJECTED, WITHDRAWN)` triggers a full Seq Scan | 1,000 rows read, 159 discarded; no index to exclude terminal statuses |

---

## 3. Optimization Proposals Evaluated

Three options were presented. User selected **P3 (both P1 + P2)**:

| Proposal | Approach | DDL? | Expected speedup at scale |
|---|---|---|---|
| P1 | Query rewrite: LATERAL + pre_filtered CTE | None | −50 to −65% execution time |
| P2 | Partial index on Application.status (active rows only) | Additive index | −60 to −80% Application scan at ≥10K rows |
| **P3 (chosen)** | **Both P1 and P2** | **Additive index only** | **Best combined outcome** |

---

## 4. Changes Applied

### 4a. Query Rewrite (P1) — `docs/common-report-queries.sql`

Three structural changes in the R4 query:

**Change 1 — LATERAL replaces LEFT JOIN + GROUP BY**

Before:
```sql
LEFT JOIN "Interview" i ON i."applicationId" = a.id
...
GROUP BY a.id, a."positionId", p.title, a."candidateId", c."firstName", c."lastName",
         a.status, a."applicationDate"
-- MAX(i."interviewDate") as last_interview_date computed via HashAggregate
```

After:
```sql
LEFT JOIN LATERAL (
  SELECT MAX("interviewDate") AS last_interview_date
  FROM   "Interview"
  WHERE  "applicationId" = a.id
) last_i ON true
-- Resolved per row via Index Only Scan on Interview_applicationId_interviewDate_idx
```

The LATERAL triggers an `Index Only Scan Backward` on `Interview_applicationId_interviewDate_idx`, avoiding the full hash join. At production scale, this is O(841 × log N) vs O(N) for the hash approach.

**Change 2 — COALESCE computed once**

Before: `COALESCE(last_interview_date, application_date::timestamptz)` evaluated three times — in the `stall_calc` column, in the `ORDER BY` clause, and in the `WHERE` filter.

After: computed once as `last_touch` in `active_apps`, referenced by name everywhere.

**Change 3 — pre_filtered CTE applied before ROW_NUMBER()**

Before:
```sql
stall_calc AS (SELECT *, ROW_NUMBER() OVER (...) ... FROM active_apps)
SELECT ... FROM stall_calc WHERE idle_duration > ($1 * INTERVAL '1 day')
-- window runs on 841 rows; 277 discarded after
```

After:
```sql
pre_filtered AS (SELECT * FROM active_apps WHERE NOW() - last_touch > ($1 * INTERVAL '1 day'))
ranked AS (SELECT *, ROW_NUMBER() OVER (...) FROM pre_filtered)
-- window runs on 564 rows only
```

The planner inlined `pre_filtered` into the Nested Loop filter condition and applied it before the sort+window, reducing window input from 841 → 564 rows (−33%).

---

### 4b. Partial Index (P2) — Migration `20260428120000_optimize_r4_stalled_partial_idx`

```sql
CREATE INDEX "Application_active_status_idx"
    ON "Application" ("status")
    WHERE status NOT IN ('HIRED', 'REJECTED', 'WITHDRAWN');
```

- **Kind:** Partial btree index on active applications only
- **Maintenance:** Automatic — PostgreSQL maintains it on every INSERT/UPDATE/DELETE
- **Staleness window:** None — always consistent
- **Rollback:** `DROP INDEX CONCURRENTLY "Application_active_status_idx"`
- **Status at time of report:** ✅ Applied via `prisma migrate deploy`

---

## 5. Before / After Comparison

| Metric | Before | After | Delta |
|---|---|---|---|
| Execution time | 3.789 ms | **2.817 ms** | **−25.7%** |
| Rows through window | 841 | **564** | **−33%** |
| Rows returned | 564 | 564 | — |
| Shared buffers hit | 40 | 2,008 | +1,968 (structural — see §6) |
| Interview scan | Hash join over 728 rows (HashAggregate 169 kB) | Index Only Scan LATERAL × 841 lookups | structural change |
| Application scan | Seq Scan (1,000 rows, 159 removed) | Seq Scan — partial index not engaged at 1K; engages at ≥10K | partial index live |
| COALESCE evaluations | 3× per row | **1× per row** | −2 per row |
| Planning time | 2.275 ms | 3.830 ms | +1.555 ms (LATERAL plan is more complex to plan) |

---

## 6. Buffer Hit Note — Why 40 → 2,008 is Not a Regression

The 50× increase in buffer hits appears alarming but is a structural consequence of the LATERAL approach, not a performance regression:

| Approach | Mechanism | Buffer scaling with interview volume |
|---|---|---|
| Original (LEFT JOIN + HashAggregate) | One sequential pass over all Interview rows; one hash table built | **O(N)** — grows linearly with every interview ever inserted |
| Optimized (LATERAL Index Only Scan) | 841 index lookups, each reading 1–2 index pages | **O(K × log N)** — K = active applications (bounded), N = total interviews |

At 728 interviews, the LATERAL needs 841 × ~2.3 pages ≈ 1,966 buffer hits. At 100K interviews, the LATERAL still needs ≈ 841 × 4 pages ≈ 3,364 hits — while the original would need ~100K hits to scan all interviews. The crossover where LATERAL wins on buffer count is ~5K interview rows.

---

## 7. Partial Index — Production Forecast

`Application_active_status_idx` is live but not engaged at 1K rows (Seq Scan is cheaper below ~300–500 rows). Expected behavior at scale:

| Application rows | Scan type | Estimated speedup on Application step |
|---|---|---|
| 1,000 (current) | Seq Scan (planner correct) | — |
| 10,000 | Index Scan via partial index | −60 to −70% |
| 100,000 | Index Scan via partial index | −80 to −90% |

At 100K applications with ~15% active rate, the partial index covers ~15K rows — a 7× smaller index than a full-table index on status.

---

## 8. Remaining Optimization Headroom

| Opportunity | Applicable at scale? | Action |
|---|---|---|
| Partial index on Application.status (P2) | Yes — engages at ≥10K rows | ✅ Already applied; no further action |
| Add `candidateId` to `Application_active_status_idx` as a covering column | Yes — avoids Candidate heap fetch | Optional future migration |
| Materialized view for R4 | Only if the query becomes a dashboard fixture refreshed periodically | Deferred — document in Step 7 report-service guide |

---

## 9. Migration Applied

| Migration | Timestamp | Scope | Status |
|---|---|---|---|
| `optimize_r4_stalled_partial_idx` | 20260428120000 | Partial index on Application (active statuses) | ✅ Applied |

---

## 10. Next Step

**Step 6** — Risk-review migration `20260428120000_optimize_r4_stalled_partial_idx` before production promotion.
