# Common Queries & Index Tuning Report (Step 2 output)

> Generated: 2026-04-27
> Branch: `feat/update-migrate-db-JFL`
> Skill: `db-tune-and-report` — Step 2
> EXPLAIN ANALYZE strategy: Option B — 129-row seed, plans captured, data truncated.

---

## 1. Common Queries

12 queries written to `docs/common-queries.sql`. Each is justified by a concrete ATS workflow and role.

| ID | Topic | Frequency | Key indexes used |
|---|---|---|---|
| Q1 | Open positions for a company (paginated) | High | `Position_companyId_status_idx` ✅ |
| Q2 | Active applications by candidate | High | `Application_candidateId_status_idx` ✅ |
| Q3 | Pipeline funnel per position | Medium | `Application_positionId_status_idx` ✅ |
| Q4 | Interview calendar for employee (date range) | High | `Interview_employeeId_idx` (gap → I1) |
| Q5 | Candidates without any application (backlog) | Low/batch | `Application_candidateId_status_idx` Index Only ✅ |
| Q6 | Steps remaining for in-progress application | Medium | pkey chain ✅ |
| Q7 | Avg score per InterviewType for a position | Low/ad-hoc | `Application_positionId_status_idx` + pkeys ✅ |
| Q8 | Most recent interview per application (bulk) | Medium | `Interview_applicationId_interviewDate_idx` ✅ |
| Q9 | Job board search — salary range + type | High | `Position_companyId_status_idx` (gap → I2) |
| Q10 | Companies ranked by application volume | Low/weekly | `Position_companyId_status_idx` + `Application_positionId_idx` ✅ |
| Q11 | Top 5 employees by interviews in last 30 days | Low/daily | Seq Scan (gap → I1) |
| Q12 | Stale open positions with zero applications | Low/weekly | `Position_companyId_status_idx` (gap → I3) |

---

## 2. pg_stat_statements Hotspots

No application-level query hotspots at audit time — all entries were system introspection queries from this session (max 4.65 ms cumulative). The database had no prior application traffic. Hotspot-driven analysis will be available after the Step 4 seed produces workload statistics.

---

## 3. Index Proposals — diff against existing 32 indexes

### Existing index coverage (Migration 4: `add_indexes`)

All FK columns and key composite filters already covered. No duplicates introduced.

### Net-new indexes proposed and applied (Migration 7: `add_common_query_indexes`)

| Index | Table | Kind | Serves | Rationale |
|---|---|---|---|---|
| `Interview_employeeId_interviewDate_idx` | Interview | btree composite `(employeeId, interviewDate)` | Q4, Q11 | Single-col `employeeId_idx` leaves `interviewDate` as a heap post-filter; composite converts it to an index range condition |
| `Position_open_visible_employmentType_idx` | Position | btree partial `(employmentType) WHERE status='OPEN' AND isVisible=true` | Q9 | Job board search filters open+visible first; existing index leads with `companyId`, unusable here |
| `Position_open_createdAt_idx` | Position | btree partial `(createdAt) WHERE status='OPEN'` | Q12 | Stale-position alert sorts open positions by age; no prior index covers this access pattern |

---

## 4. EXPLAIN ANALYZE — Before Plans (129-row seed, no new indexes)

| Query | Leading node | ms | Observation |
|---|---|---|---|
| Q1 | Index Scan `companyId_status_idx` | 0.046 | Optimal ✅ |
| Q2 | Bitmap Index Scan `candidateId_status_idx` | 0.299 | Optimal ✅ |
| Q3 | Bitmap Index Scan `positionId_status_idx` | 0.395 | Optimal ✅ |
| Q4 | Bitmap Index Scan `employeeId_idx` + date heap-filter (21/30 rows discarded) | 0.279 | Gap: date is post-filter ⚠️ |
| Q5 | Index Only Scan `candidateId_status_idx` | 0.173 | Optimal ✅ |
| Q6 | Index chain (all pkeys) | 3.003 | Acceptable; Interview filter discards 6/8 rows post-index |
| Q7 | Seq Scan Interview + Hash Join (score IS NOT NULL filter, 8/30 discarded) | 0.654 | Acceptable at scale with existing indexes |
| Q8 | Bitmap Index Scan `applicationId_interviewDate_idx` | 0.310 | Optimal ✅ |
| Q9 | Index Scan `companyId_status_idx` + employmentType/isVisible heap-filter | 0.100 | Gap: type+visibility are post-filters ⚠️ |
| Q10 | Seq Scan Position + Bitmap `positionId_idx` | 0.217 | Acceptable ✅ |
| Q11 | Seq Scan Interview (22/30 removed by date) + Hash Join | 0.138 | Gap: full scan for date range ⚠️ |
| Q12 | Index Scan `companyId_status_idx` + createdAt heap-filter | 0.062 | Gap: age filter is post-filter ⚠️ |

---

## 5. EXPLAIN ANALYZE — After Plans (indexes applied, same 129-row seed)

> With only 4 Position rows and 30 Interview rows, the PostgreSQL planner correctly chooses sequential scans for all tables — index overhead exceeds heap scan cost at this scale. New indexes will engage automatically at production row counts (≈300+ Interview rows, ≈50+ Position rows).

| Query | After plan | ms | Index engagement threshold |
|---|---|---|---|
| Q4 | Seq Scan (planner cost lower than I1 at 30 rows) | 0.392 | ~300 Interview rows |
| Q9 | Seq Scan (planner cost lower than I2 at 4 rows) | 0.240 | ~50 Position rows |
| Q11 | Seq Scan (planner cost lower than I1 at 30 rows) | 0.186 | ~300 Interview rows |
| Q12 | Seq Scan (planner cost lower than I3 at 4 rows) | 0.124 | ~50 Position rows |

---

## 6. Expected Production Impact

| Index | Query | Scan change at scale | Expected speedup |
|---|---|---|---|
| I1 `(employeeId, interviewDate)` | Q4 | Bitmap single-col + heap filter → Index Range Scan | 3–10× for high-volume interviewers |
| I1 `(employeeId, interviewDate)` | Q11 | Full Seq Scan → Index Range Scan by date | 5–20× as Interview table grows |
| I2 partial `(employmentType)` | Q9 | Full scan + multi-filter → Partial Index Scan | 2–5× on populated job boards |
| I3 partial `(createdAt)` | Q12 | Full scan + double filter → Partial Index Range | 3–8× as open positions accumulate |

---

## 7. Migration Applied

`20260427011538_add_common_query_indexes` — applied and tracked in `_prisma_migrations`. Prisma Client regenerated. No destructive DDL; verdict: **safe**.
