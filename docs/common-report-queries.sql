-- =========================================================
-- File   : docs/common-report-queries.sql
-- Source : .claude/skills/db-tune-and-report/steps/step-04-report-queries-and-seed.md
-- Reports: 5 high-value ATS reports, validated against a 1000-row seed.
-- Style  : CTE pipelines + window functions (ROW_NUMBER, DENSE_RANK, LAG,
--          PERCENTILE_CONT).
-- =========================================================


-- =========================================================
-- R1 — Pipeline Funnel by Position
--      Purpose : Stage-by-stage application counts and conversion ratios
--                per position. Uses LAG() to compute the drop-off from the
--                previous funnel stage, surfacing where candidates fall out.
--      Params  : none (returns all positions with at least one application)
--      Output  : position_id, position_title, company_name, status_name,
--                stage_order, applications_in_stage, prev_stage_count,
--                conversion_pct_from_prev
-- =========================================================

WITH status_order (status_name, stage_order) AS (
  VALUES
    ('PENDING'::text,   1),
    ('SCREENING'::text, 2),
    ('INTERVIEW'::text, 3),
    ('OFFER'::text,     4),
    ('HIRED'::text,     5)
),
funnel AS (
  SELECT
    p.id                                    AS position_id,
    p.title                                 AS position_title,
    co.name                                 AS company_name,
    a.status::text                          AS status_name,
    COUNT(*)                                AS cnt
  FROM "Application" a
  JOIN "Position" p  ON p.id  = a."positionId"
  JOIN "Company"  co ON co.id = p."companyId"
  GROUP BY p.id, p.title, co.name, a.status::text
),
ordered_funnel AS (
  SELECT
    f.position_id,
    f.position_title,
    f.company_name,
    f.status_name,
    so.stage_order,
    f.cnt,
    LAG(f.cnt) OVER (
      PARTITION BY f.position_id
      ORDER BY so.stage_order
    )                                       AS prev_stage_count
  FROM funnel f
  JOIN status_order so ON so.status_name = f.status_name
)
SELECT
  position_id,
  position_title,
  company_name,
  status_name,
  stage_order,
  cnt                                                              AS applications_in_stage,
  prev_stage_count,
  ROUND(
    cnt::numeric / NULLIF(prev_stage_count, 0) * 100, 1
  )                                                               AS conversion_pct_from_prev
FROM ordered_funnel
ORDER BY position_id, stage_order;


-- =========================================================
-- R2 — Recruiter Activity Leaderboard
--      Purpose : Top-K interviewers per company ranked by interviews
--                conducted and hires assisted in a configurable lookback
--                window. Uses ROW_NUMBER() OVER (PARTITION BY companyId)
--                to produce a per-company leaderboard without the
--                LIMIT-per-group antipattern.
--      Params  : $1 = lookback_days  (e.g. 90)
--                $2 = top_k          (e.g. 5 — top K per company)
--      Output  : rank_in_company, company_name, employee_name, employee_role,
--                interviews_conducted, hires_assisted
-- =========================================================

WITH activity AS (
  SELECT
    e.id                                     AS employee_id,
    e.name                                   AS employee_name,
    e.role::text                             AS employee_role,
    e."companyId",
    co.name                                  AS company_name,
    COUNT(i.id)                              AS interviews_conducted,
    COUNT(i.id) FILTER (
      WHERE a.status = 'HIRED'
    )                                        AS hires_assisted
  FROM "Employee" e
  JOIN "Company" co ON co.id = e."companyId"
  LEFT JOIN "Interview" i
    ON  i."employeeId"     = e.id
    AND i."interviewDate" >= NOW() - ($1 * INTERVAL '1 day')
  LEFT JOIN "Application" a ON a.id = i."applicationId"
  WHERE e."isActive" = true
  GROUP BY e.id, e.name, e.role, e."companyId", co.name
),
ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY "companyId"
      ORDER BY interviews_conducted DESC, hires_assisted DESC, employee_id ASC
    )                                        AS rank_in_company
  FROM activity
)
SELECT
  rank_in_company,
  company_name,
  employee_name,
  employee_role,
  interviews_conducted,
  hires_assisted
FROM ranked
WHERE rank_in_company <= $2
ORDER BY company_name, rank_in_company;


-- =========================================================
-- R3 — Time-to-Hire by Position / Company
--      Purpose : Median and p90 elapsed days from application submission to
--                first interview date for HIRED applications. Identifies
--                slow-moving pipelines for recruiter SLA tracking.
--      Params  : none (returns all positions with ≥ 1 hire)
--      Output  : position_id, position_title, company_name, hires,
--                median_days_to_hire, p90_days_to_hire, min_days, max_days
-- =========================================================

WITH hired_apps AS (
  SELECT
    a.id                                     AS application_id,
    a."positionId"                           AS position_id,
    p.title                                  AS position_title,
    p."companyId"                            AS company_id,
    co.name                                  AS company_name,
    a."applicationDate"::timestamptz         AS applied_on,
    MIN(i."interviewDate")                   AS first_interview_at
  FROM "Application" a
  JOIN "Position" p  ON p.id  = a."positionId"
  JOIN "Company"  co ON co.id = p."companyId"
  LEFT JOIN "Interview" i ON i."applicationId" = a.id
  WHERE a.status = 'HIRED'
  GROUP BY
    a.id, a."positionId", p.title, p."companyId", co.name, a."applicationDate"
),
days_calc AS (
  SELECT
    *,
    EXTRACT(EPOCH FROM (first_interview_at - applied_on)) / 86400.0
                                             AS days_to_hire
  FROM hired_apps
  WHERE first_interview_at IS NOT NULL
),
position_agg AS (
  SELECT
    position_id,
    position_title,
    company_id,
    company_name,
    COUNT(*)                                                       AS hires,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_hire)     AS median_days,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY days_to_hire)     AS p90_days,
    MIN(days_to_hire)                                              AS min_days,
    MAX(days_to_hire)                                              AS max_days
  FROM days_calc
  GROUP BY position_id, position_title, company_id, company_name
)
SELECT
  position_id,
  position_title,
  company_name,
  hires,
  ROUND(median_days::numeric, 1)                                  AS median_days_to_hire,
  ROUND(p90_days::numeric,   1)                                   AS p90_days_to_hire,
  ROUND(min_days::numeric,   1)                                   AS min_days,
  ROUND(max_days::numeric,   1)                                   AS max_days
FROM position_agg
ORDER BY median_days_to_hire ASC NULLS LAST;


-- =========================================================
-- R4 — Stalled Applications
--      Purpose : Active applications (not HIRED/REJECTED/WITHDRAWN) with
--                no interview activity for more than N days. Used by
--                recruiters to triage neglected candidates before SLA breach.
--                ROW_NUMBER() OVER (PARTITION BY position_id) ranks the
--                most stalled application per position for quick action.
--      Params  : $1 = stall_threshold_days (e.g. 14)
--      Output  : application_id, position_title, candidate_name, status_name,
--                application_date, last_interview_date, idle_days,
--                oldest_stall_rank
-- =========================================================

WITH active_apps AS (
  SELECT
    a.id                                     AS application_id,
    a."positionId"                           AS position_id,
    p.title                                  AS position_title,
    a."candidateId"                          AS candidate_id,
    CONCAT(c."firstName", ' ', c."lastName") AS candidate_name,
    a.status::text                           AS status_name,
    a."applicationDate"                      AS application_date,
    MAX(i."interviewDate")                   AS last_interview_date
  FROM "Application" a
  JOIN "Position"  p ON p.id = a."positionId"
  JOIN "Candidate" c ON c.id = a."candidateId"
  LEFT JOIN "Interview" i ON i."applicationId" = a.id
  WHERE a.status NOT IN ('HIRED', 'REJECTED', 'WITHDRAWN')
  GROUP BY
    a.id, a."positionId", p.title,
    a."candidateId", c."firstName", c."lastName",
    a.status, a."applicationDate"
),
stall_calc AS (
  SELECT
    *,
    COALESCE(
      last_interview_date,
      application_date::timestamptz
    )                                        AS last_touch,
    NOW() - COALESCE(
      last_interview_date,
      application_date::timestamptz
    )                                        AS idle_duration,
    ROW_NUMBER() OVER (
      PARTITION BY position_id
      ORDER BY
        COALESCE(last_interview_date, application_date::timestamptz) ASC,
        application_id ASC
    )                                        AS oldest_stall_rank
  FROM active_apps
)
SELECT
  application_id,
  position_title,
  candidate_name,
  status_name,
  application_date,
  last_interview_date,
  EXTRACT(DAY FROM idle_duration)::int       AS idle_days,
  oldest_stall_rank
FROM stall_calc
WHERE idle_duration > ($1 * INTERVAL '1 day')
ORDER BY idle_duration DESC, application_id ASC;


-- =========================================================
-- R5 — Candidate Quality by Education Institution
--      Purpose : Rank candidate feeder institutions by average and p75
--                interview scores to inform sourcing strategy. Each
--                candidate's avg score is computed first, then aggregated
--                per institution. DENSE_RANK() produces a stable ranking
--                that handles ties without gaps.
--      Params  : none (returns all institutions with ≥ 1 scored interview)
--      Output  : quality_rank, institution, candidates_evaluated,
--                avg_interview_score, p75_interview_score, total_interviews
-- =========================================================

WITH scored_interviews AS (
  SELECT
    a."candidateId"                          AS candidate_id,
    i.score
  FROM "Interview" i
  JOIN "Application" a ON a.id = i."applicationId"
  WHERE i.score IS NOT NULL
),
candidate_avg AS (
  SELECT
    candidate_id,
    AVG(score)                               AS avg_score,
    COUNT(*)                                 AS interview_count
  FROM scored_interviews
  GROUP BY candidate_id
),
institution_agg AS (
  SELECT
    ed.institution,
    COUNT(DISTINCT ca.candidate_id)          AS candidates_evaluated,
    AVG(ca.avg_score)                        AS avg_score,
    PERCENTILE_CONT(0.75) WITHIN GROUP (
      ORDER BY ca.avg_score
    )                                        AS p75_score,
    SUM(ca.interview_count)                  AS total_interviews
  FROM candidate_avg ca
  JOIN "Education" ed ON ed."candidateId" = ca.candidate_id
  GROUP BY ed.institution
),
ranked AS (
  SELECT
    *,
    DENSE_RANK() OVER (
      ORDER BY p75_score DESC, avg_score DESC, institution ASC
    )                                        AS quality_rank
  FROM institution_agg
)
SELECT
  quality_rank,
  institution,
  candidates_evaluated,
  ROUND(avg_score::numeric, 2)             AS avg_interview_score,
  ROUND(p75_score::numeric, 2)             AS p75_interview_score,
  total_interviews::int                     AS total_interviews
FROM ranked
ORDER BY quality_rank, institution;
