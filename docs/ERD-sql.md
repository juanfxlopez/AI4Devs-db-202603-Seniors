# ERD → SQL (Step 1 output template)

> Filled by `steps/step-01-erd-to-sql.md`. Faithful-only conversion of
> `docs/ERD-mermaid.md`. No indexes / normalization / pgvector here —
> those go into the Step 2 recommendation report.

```sql
-- Source ERD : docs/ERD-mermaid.md
-- Generated  : 2026-04-26
-- Target DB  : PostgreSQL 18
-- Status     : faithful-only conversion. Improvements live in docs/ERD-sql Step 2 report.
-- Casing     : new tables use snake_case. Existing live DB tables are PascalCase
--              (Candidate, Education, WorkExperience, Resume). Resolution deferred to Step 2.

-- =========================================================
-- Schema: public
-- Engine : PostgreSQL 18
-- =========================================================

-- ---------------------------------------------------------
-- COMPANY
-- ---------------------------------------------------------
CREATE TABLE company (
    id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- NOTE: ERD `string name` — no length hint given; using TEXT (unbounded).
    --       Step 2 may recommend VARCHAR(255) for consistency with existing schema style.
    name TEXT NOT NULL
);

-- ---------------------------------------------------------
-- INTERVIEW_FLOW
-- (declared before POSITION and INTERVIEW_STEP to satisfy FK dependency order)
-- ---------------------------------------------------------
CREATE TABLE interview_flow (
    id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- NOTE: ERD `string description` — no length hint; using TEXT.
    description TEXT NOT NULL
);

-- ---------------------------------------------------------
-- INTERVIEW_TYPE
-- ---------------------------------------------------------
CREATE TABLE interview_type (
    id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- NOTE: ERD `string name` — no length hint; using TEXT.
    name        TEXT NOT NULL,
    -- NOTE: ERD `text description` — marked as text without explicit required signal;
    --       treating as nullable (a type can be named without a description).
    description TEXT
);

-- ---------------------------------------------------------
-- EMPLOYEE
-- (depends on: company)
-- ---------------------------------------------------------
CREATE TABLE employee (
    id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id INTEGER NOT NULL,
    -- NOTE: ERD `string name/email/role` — no length hints; using TEXT throughout.
    name       TEXT    NOT NULL,
    email      TEXT    NOT NULL,
    role       TEXT    NOT NULL,
    is_active  BOOLEAN NOT NULL,
    CONSTRAINT employee_company_id_fkey
        FOREIGN KEY (company_id) REFERENCES company (id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ---------------------------------------------------------
-- POSITION
-- (depends on: company, interview_flow)
-- NOTE: `position` is a SQL standard function name. While PostgreSQL allows it as an
--       unquoted table identifier, Step 2 should recommend quoting ("position") or
--       renaming to `job_position` to avoid ambiguity in queries and ORMs.
-- ---------------------------------------------------------
CREATE TABLE position (
    id                   INTEGER      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id           INTEGER      NOT NULL,
    -- NOTE: ERD `POSITION ||--|| INTERVIEW_FLOW` cardinality is 1:1 (exactly one flow per
    --       position and vice-versa). UNIQUE enforced here per ERD. If multiple positions
    --       should share a flow, this constraint must be dropped — flag for Step 2.
    interview_flow_id    INTEGER      NOT NULL UNIQUE,
    -- NOTE: ERD `string title` — no length hint; using TEXT.
    title                TEXT         NOT NULL,
    -- NOTE: ERD `text description` — nullable; short-form description may be absent initially.
    description          TEXT,
    -- NOTE: ERD `string status` — user pre-decision (Q5): will become a Prisma enum in Step 2.
    --       Faithful DDL uses TEXT here.
    status               TEXT         NOT NULL,
    is_visible           BOOLEAN      NOT NULL,
    -- NOTE: ERD `string location` — nullable; remote positions may have no fixed location.
    location             TEXT,
    job_description      TEXT,
    requirements         TEXT,
    responsibilities     TEXT,
    -- NOTE: ERD `numeric salary_min/salary_max` — user pre-decision (Q2): NUMERIC(10,2).
    --       Nullable; salary may not be disclosed at posting time.
    salary_min           NUMERIC(10,2),
    salary_max           NUMERIC(10,2),
    -- NOTE: ERD `string employment_type` — nullable; type may be set after initial draft.
    employment_type      TEXT,
    benefits             TEXT,
    company_description  TEXT,
    application_deadline DATE,
    contact_info         TEXT,
    CONSTRAINT position_company_id_fkey
        FOREIGN KEY (company_id) REFERENCES company (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT position_interview_flow_id_fkey
        FOREIGN KEY (interview_flow_id) REFERENCES interview_flow (id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ---------------------------------------------------------
-- INTERVIEW_STEP
-- (depends on: interview_flow, interview_type)
-- NOTE: ON DELETE CASCADE from interview_flow — steps are owned by their flow;
--       deleting a flow removes all its steps. Ownership is clear from ERD.
-- ---------------------------------------------------------
CREATE TABLE interview_step (
    id                INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    interview_flow_id INTEGER NOT NULL,
    interview_type_id INTEGER NOT NULL,
    -- NOTE: ERD `string name` — no length hint; using TEXT.
    name              TEXT    NOT NULL,
    order_index       INTEGER NOT NULL,
    CONSTRAINT interview_step_interview_flow_id_fkey
        FOREIGN KEY (interview_flow_id) REFERENCES interview_flow (id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT interview_step_interview_type_id_fkey
        FOREIGN KEY (interview_type_id) REFERENCES interview_type (id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ---------------------------------------------------------
-- CANDIDATE
-- NOTE: This entity already exists in the live DB as PascalCase table "Candidate"
--       with explicit VARCHAR lengths: firstName/lastName VARCHAR(100),
--       email VARCHAR(255) UNIQUE, phone VARCHAR(15), address VARCHAR(100).
--       This CREATE TABLE reflects the ERD target state for reference only.
--       Step 2 will diff against the live table and emit ALTER statements instead.
-- NOTE: Q1 decision — phone and address are NOT NULL (ERD wins over current nullable columns).
--       Step 3 will emit: ALTER TABLE "Candidate" ALTER COLUMN phone SET NOT NULL; etc.
-- NOTE: camelCase field names ("firstName", "lastName") preserved verbatim from ERD
--       to match the existing live table; quotes required in PostgreSQL.
-- ---------------------------------------------------------
CREATE TABLE candidate (
    id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- NOTE: ERD `string firstName/lastName` — using TEXT; Step 2 will align to existing VARCHAR(100).
    "firstName" TEXT NOT NULL,
    "lastName"  TEXT NOT NULL,
    -- NOTE: existing live table has UNIQUE on email; preserved by Step 2 ALTER.
    email       TEXT NOT NULL,
    -- NOTE: Q1 — NOT NULL per ERD decision; live table currently nullable → ALTER needed.
    phone       TEXT NOT NULL,
    address     TEXT NOT NULL
);

-- ---------------------------------------------------------
-- APPLICATION
-- (depends on: position, candidate)
-- ---------------------------------------------------------
CREATE TABLE application (
    id               INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    position_id      INTEGER NOT NULL,
    candidate_id     INTEGER NOT NULL,
    application_date DATE    NOT NULL,
    -- NOTE: ERD `string status` — user pre-decision (Q5): will become a Prisma enum in Step 2.
    status           TEXT    NOT NULL,
    -- NOTE: ERD `text notes` — nullable; notes are added after creation.
    notes            TEXT,
    CONSTRAINT application_position_id_fkey
        FOREIGN KEY (position_id) REFERENCES position (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT application_candidate_id_fkey
        FOREIGN KEY (candidate_id) REFERENCES candidate (id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ---------------------------------------------------------
-- INTERVIEW
-- (depends on: application, interview_step, employee)
-- NOTE: ON DELETE CASCADE from application — interviews are owned by their application;
--       deleting an application removes all its interviews.
-- NOTE: ERD `INTERVIEW ||--|| INTERVIEW_STEP : consists_of` shows 1:1 cardinality.
--       In practice, many interviews across different applications may reference the
--       same step — UNIQUE on interview_step_id is NOT applied here. Step 2 should
--       clarify if a uniqueness-per-application constraint is intended.
-- ---------------------------------------------------------
CREATE TABLE interview (
    id                INTEGER   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id    INTEGER   NOT NULL,
    interview_step_id INTEGER   NOT NULL,
    employee_id       INTEGER   NOT NULL,
    -- NOTE: ERD `date interview_date` — user pre-decision (Q3): TIMESTAMP (not DATE),
    --       so time-of-day is captured. Step 2 will recommend TIMESTAMPTZ if
    --       multi-timezone support is required.
    interview_date    TIMESTAMP NOT NULL,
    -- NOTE: ERD `string result` — nullable; result is unknown until after the interview.
    result            TEXT,
    -- NOTE: ERD `int score` — nullable; scoring may not be used for all interview types.
    score             INTEGER,
    -- NOTE: ERD `text notes` — nullable.
    notes             TEXT,
    CONSTRAINT interview_application_id_fkey
        FOREIGN KEY (application_id) REFERENCES application (id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT interview_interview_step_id_fkey
        FOREIGN KEY (interview_step_id) REFERENCES interview_step (id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT interview_employee_id_fkey
        FOREIGN KEY (employee_id) REFERENCES employee (id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);
```
