-- =========================================================
-- File   : docs/common-queries.sql
-- Source : .claude/skills/db-tune-and-report — Step 2
-- Note   : Data state at generation time: all tables empty.
--          EXPLAIN ANALYZE plans deferred until Step 4 seed (option A)
--          or captured after option B/C decision.
-- Params : $1, $2, … PostgreSQL positional placeholders
-- =========================================================

-- =========================================================
-- Q1 — Open positions for a company (paginated, newest first)
--      Why: Recruiter dashboard landing view; called on every
--           company page load. High frequency.
--      Params: $1 INT = companyId, $2 INT = limit, $3 INT = offset
--      Output: id, title, status, location, employmentType,
--              applicationDeadline, createdAt
--      Indexes: Position_companyId_status_idx (companyId, status) ✅
-- =========================================================
SELECT p.id,
       p.title,
       p.status,
       p.location,
       p."employmentType",
       p."applicationDeadline",
       p."createdAt"
FROM   "Position" p
WHERE  p."companyId" = $1
  AND  p.status = 'OPEN'
ORDER  BY p."createdAt" DESC
LIMIT  $2 OFFSET $3;

-- =========================================================
-- Q2 — Active applications by candidate
--      Why: Candidate portal — shows in-flight pipeline entries.
--           Called on every candidate login. High frequency.
--      Params: $1 INT = candidateId
--      Output: id, applicationDate, status, position title, company name
--      Indexes: Application_candidateId_status_idx (candidateId, status) ✅
-- =========================================================
SELECT a.id,
       a."applicationDate",
       a.status,
       p.title          AS position_title,
       c.name           AS company_name
FROM   "Application" a
JOIN   "Position"    p ON p.id = a."positionId"
JOIN   "Company"     c ON c.id = p."companyId"
WHERE  a."candidateId" = $1
  AND  a.status NOT IN ('HIRED', 'REJECTED', 'WITHDRAWN')
ORDER  BY a."applicationDate" DESC;

-- =========================================================
-- Q3 — Pipeline funnel per position (status distribution)
--      Why: Hiring manager KPI widget — how many candidates
--           at each stage. Called on position detail page.
--      Params: $1 INT = positionId
--      Output: status, cnt
--      Indexes: Application_positionId_idx (positionId) ✅
-- =========================================================
SELECT a.status,
       COUNT(*) AS cnt
FROM   "Application" a
WHERE  a."positionId" = $1
GROUP  BY a.status
ORDER  BY cnt DESC;

-- =========================================================
-- Q4 — Interview calendar for an employee (date range)
--      Why: Interviewer's daily/weekly agenda view.
--           High frequency during interview season.
--      Params: $1 INT = employeeId, $2 TIMESTAMPTZ = from,
--              $3 TIMESTAMPTZ = to
--      Output: id, interviewDate, result, score,
--              candidateName, positionTitle, stepName
--      Indexes: Interview_employeeId_idx ✅ (single col);
--               proposed: (employeeId, interviewDate) composite — NEW
-- =========================================================
SELECT i.id,
       i."interviewDate",
       i.result,
       i.score,
       c."firstName" || ' ' || c."lastName" AS candidate_name,
       p.title                               AS position_title,
       ist.name                              AS step_name
FROM   "Interview"     i
JOIN   "Application"   a   ON a.id   = i."applicationId"
JOIN   "Candidate"     c   ON c.id   = a."candidateId"
JOIN   "Position"      p   ON p.id   = a."positionId"
JOIN   "InterviewStep" ist ON ist.id = i."interviewStepId"
WHERE  i."employeeId"    = $1
  AND  i."interviewDate" >= $2
  AND  i."interviewDate" <  $3
ORDER  BY i."interviewDate";

-- =========================================================
-- Q5 — Candidates without any application (recruiting backlog)
--      Why: Sourcing team identifies candidates who entered the
--           system but were never submitted. Low frequency, batch.
--      Params: none
--      Output: id, firstName, lastName, email, phone
--      Indexes: anti-join via Application_candidateId_idx ✅
-- =========================================================
SELECT c.id,
       c."firstName",
       c."lastName",
       c.email,
       c.phone
FROM   "Candidate" c
WHERE  NOT EXISTS (
         SELECT 1
         FROM   "Application" a
         WHERE  a."candidateId" = c.id
       )
ORDER  BY c.id;

-- =========================================================
-- Q6 — Interview steps remaining for an in-progress application
--      Why: Candidate tracking panel — shows pipeline progress.
--           Called on application detail view. Medium frequency.
--      Params: $1 INT = applicationId
--      Output: stepId, stepName, orderIndex, result (NULL = pending)
--      Indexes: InterviewStep_interviewFlowId_orderIndex_key ✅
--               Interview_applicationId_idx ✅
-- =========================================================
SELECT ist.id           AS step_id,
       ist.name         AS step_name,
       ist."orderIndex",
       i.result
FROM   "Application"   a
JOIN   "Position"      p   ON p.id             = a."positionId"
JOIN   "InterviewFlow" ifl ON ifl.id           = p."interviewFlowId"
JOIN   "InterviewStep" ist ON ist."interviewFlowId" = ifl.id
LEFT   JOIN "Interview" i  ON i."applicationId"    = a.id
                           AND i."interviewStepId"  = ist.id
WHERE  a.id = $1
ORDER  BY ist."orderIndex";

-- =========================================================
-- Q7 — Average score per InterviewType for a position
--      Why: Hiring manager evaluates which interview type is most
--           discriminating. Run ad-hoc on position close.
--      Params: $1 INT = positionId
--      Output: interview_type, interview_count, avg_score
--      Indexes: Application_positionId_idx ✅
--               Interview_applicationId_idx ✅
--               InterviewStep_interviewTypeId_idx ✅
-- =========================================================
SELECT it.name              AS interview_type,
       COUNT(i.id)          AS interview_count,
       ROUND(AVG(i.score), 2) AS avg_score
FROM   "Interview"     i
JOIN   "InterviewStep" ist ON ist.id = i."interviewStepId"
JOIN   "InterviewType" it  ON it.id  = ist."interviewTypeId"
JOIN   "Application"   a   ON a.id   = i."applicationId"
WHERE  a."positionId" = $1
  AND  i.score IS NOT NULL
GROUP  BY it.id, it.name
ORDER  BY avg_score DESC;

-- =========================================================
-- Q8 — Most recent interview per application (bulk lookup)
--      Why: Application list view — show latest interview status
--           without loading all interviews. Medium frequency.
--      Params: $1 INT[] = array of applicationIds
--      Output: id, applicationId, interviewDate, result, score, stepName
--      Indexes: Interview_applicationId_interviewDate_idx ✅ (DISTINCT ON)
-- =========================================================
SELECT DISTINCT ON (i."applicationId")
       i.id,
       i."applicationId",
       i."interviewDate",
       i.result,
       i.score,
       ist.name AS step_name
FROM   "Interview"     i
JOIN   "InterviewStep" ist ON ist.id = i."interviewStepId"
WHERE  i."applicationId" = ANY($1::int[])
ORDER  BY i."applicationId", i."interviewDate" DESC;

-- =========================================================
-- Q9 — Positions matching salary range and employment type
--      Why: Public job board search. High frequency on career pages.
--      Params: $1 EmploymentType, $2 NUMERIC = salaryMin budget,
--              $3 NUMERIC = salaryMax budget
--      Output: id, title, location, employmentType, salaryMin, salaryMax,
--              company name
--      Indexes: existing Position_companyId_status_idx not helpful here;
--               proposed partial idx WHERE status='OPEN' AND isVisible=true
--               ON (employmentType) — NEW
-- =========================================================
SELECT p.id,
       p.title,
       p.location,
       p."employmentType",
       p."salaryMin",
       p."salaryMax",
       c.name AS company_name
FROM   "Position" p
JOIN   "Company"  c ON c.id = p."companyId"
WHERE  p.status      = 'OPEN'
  AND  p."isVisible" = true
  AND  p."employmentType" = $1
  AND  (p."salaryMin" IS NULL OR p."salaryMin" <= $2)
  AND  (p."salaryMax" IS NULL OR p."salaryMax" >= $3)
ORDER  BY p."salaryMin" ASC NULLS LAST;

-- =========================================================
-- Q10 — Companies ranked by application volume on open positions
--       Why: Internal analytics — which companies have the most
--            active pipelines. Weekly recruiter report.
--       Params: none
--       Output: id, name, open_positions, total_applications
--       Indexes: Position_companyId_status_idx ✅
--                Application_positionId_idx ✅
-- =========================================================
SELECT c.id,
       c.name,
       COUNT(DISTINCT p.id) AS open_positions,
       COUNT(a.id)          AS total_applications
FROM   "Company"     c
JOIN   "Position"    p ON p."companyId" = c.id AND p.status = 'OPEN'
LEFT   JOIN "Application" a ON a."positionId" = p.id
GROUP  BY c.id, c.name
ORDER  BY total_applications DESC, open_positions DESC;

-- =========================================================
-- Q11 — Top 5 employees by interviews in the last 30 days
--       Why: Workload balancing dashboard for recruiting ops.
--            Daily or weekly cadence.
--       Params: none (interval hardcoded; parameterise if needed)
--       Output: id, name, email, role, interviews_count
--       Indexes: Interview_employeeId_idx ✅ (single col);
--                proposed: (interviewDate, employeeId) — NEW
-- =========================================================
SELECT e.id,
       e.name,
       e.email,
       e.role,
       COUNT(i.id) AS interviews_count
FROM   "Employee"  e
JOIN   "Interview" i ON i."employeeId" = e.id
WHERE  i."interviewDate" >= NOW() - INTERVAL '30 days'
GROUP  BY e.id, e.name, e.email, e.role
ORDER  BY interviews_count DESC
LIMIT  5;

-- =========================================================
-- Q12 — Open positions older than N days with zero applications
--       Why: Stale-pipeline alert — flags positions that need
--            sourcing attention. Weekly scheduled report.
--       Params: $1 INT = age threshold in days
--       Output: id, title, status, createdAt, company, age
--       Indexes: Position_companyId_status_idx not ideal (leads companyId);
--                proposed partial idx WHERE status='OPEN' ON (createdAt) — NEW
-- =========================================================
SELECT p.id,
       p.title,
       p.status,
       p."createdAt",
       c.name                              AS company_name,
       NOW() - p."createdAt"              AS age
FROM   "Position" p
JOIN   "Company"  c ON c.id = p."companyId"
WHERE  p.status      = 'OPEN'
  AND  p."createdAt" < NOW() - ($1 || ' days')::INTERVAL
  AND  NOT EXISTS (
         SELECT 1
         FROM   "Application" a
         WHERE  a."positionId" = p.id
       )
ORDER  BY p."createdAt" ASC;
