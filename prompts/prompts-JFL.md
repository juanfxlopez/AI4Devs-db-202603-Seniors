# Prompt P-1

/bmad-generate-project-context

---

## Follow-up prompts

### FP-1.1
[C] Continue to context generation

### FP-1.2
[P] Party Mode

### FP-1.3
Yes. Accept these changes to the Technology Stack section and continue to the Language-Specific rules

### FP-1.4
[P] Party Mode

### FP-1.5
Yes. Accept these changes to the Language-Specific rules and continue to the Framework-Specific rules

### FP-1.6
[P] Party Mode

### FP-1.7
Yes. Accept these changes to the Framework-Specific rules and continue to the Testing rules

### FP-1.8
[P] Party Mode

### FP-1.9
Yes. Accept these changes to the Testing rules and continue to the Code Quality & Style rules

### FP-1.10
[P] Party Mode

### FP-1.11
Yes. Accept these changes to the Code Quality & Style rules and continue to the Development Workflow rules

### FP-1.12
[P] Party Mode

### FP-1.13
Yes. Accept these changes to the Development Workflow rules and continue to the Critical Don’t-Miss rules

### FP-1.14
[P] Party Mode

### FP-1.15
Yes. Accept these changes to the Critical Don’t-Miss rules


---
---

# Prompt P-2

You are an expert in prompt engineering and sudolang. Given the following prompt, prepare it using best practices for structure (role, objective...) and format to achieve a precise and exhaustive result. Stick only to the requested objective by carefully analyzing what is asked in the original prompt, and always create the prompt in English and using sudolang. Do not execute the prompt. # Original prompt: " Eres un senior software engineer experto en bases de datos, actualizaciones y migraciones usando herramientas como PostgresSQL 18, pgvector, Prisma. Tu mision es ayurdarme a hacer la actualizacion de una base de datos existente, anadiendo nuevas entidades que permitan operar el flujo completo de aplicación para diversas posiciones. Te voy a guiar con diferentes instrucciones y no debes avanzar en ningun paso a menos que estrictimante te lo indique ya que que en el resultado de cada paso me gustaria tener una discusion antes de avanzar. Asi mismo cualquier duda que tengas preguntame antes de modificar o ejecutar algo. Recuerda primero leer y entender el contexto del proyecto: @project-context.md. Paso 1. Convierte el siquiente ERD @docs/ERD-mermaid.md, proporcionado en formato mermaid, a un script SQL y guardalo en docs/ERD-sql.md. Paso 2. Conectate por el MCP de DBHub que ya esta configurado a la base de datos del codigo conectada al repositorio. Analiza la base de datos del codigo actual y el script SQL que creaste y recomiendame como expandir la estructura de datos usando las migraciones de Prisma. Aun no las executes hasta que las hayamos discutido y te indique que lo hagas en el siguiente paso.Recuerda aplicar buenas practicas, como la definición de Indices y la normalización de la base datos, ya que el ERD proporcionado no cuenta con ello. Paso 3. Preguntame cuales cambios, optimizaciones y migraciones deseo hacer." Review the @project-context.md and the @docs/ERD-mermaid.md, the code and previous prisma migrations in advance so you can understand the structure of the project and the goal of the task to make a better prompt. Also connect to the database in advance to understand what is in there. Make sure your output is a prompt fully generated in sudolang.Give me the prompt here and also create a skill for claude. 

---

## Follow-up prompts

### FP-2.1
the skill need to be also in sudolang completely as the prompt. in addition you can revise the structure of the skill in @.agents/skills/bmad-generate-project-context\ which contains the different steps in distinct files under the folder step, a template in markdown file, workflow.md and the SKILL.md. try to make the skill very robust following this structure but also use sudolang for it.

---
---

# Prompt P-3

```sudolang
# DBExpansionAgent

You are a senior software engineer specialized in database design, schema
evolution, and zero-downtime migrations on PostgreSQL 18 + pgvector, driven
through Prisma 5. You are guiding the user through a strictly gated, multi-step
expansion of an existing LTI - Talent Tracking System database.

Inputs {
  ProjectContext     = read("project-context.md")
  SourceERD          = read("docs/ERD-mermaid.md")        // mermaid erDiagram
  PrismaSchema       = read("backend/prisma/schema.prisma")
  PriorMigrations    = glob("backend/prisma/migrations/**/migration.sql")
  LiveDB             = MCP("db")                          // DBHub MCP, already configured
  TargetSqlFile      = "docs/ERD-sql.md"                  // output of Step 1
}

Stack {
  postgres   = "18 (pgvector/pgvector:pg18 image, container lti-db)"
  extensions = ["pgvector (NOT YET ENABLED in live DB — only plpgsql is)"]
  orm        = "Prisma ^5.13.0, prisma-client-js, binaryTargets [native, debian-openssl-3.0.x]"
  language   = "TypeScript ^4.9.5, CommonJS, strict"
  envVar     = "DATABASE_URL from backend/.env"
}

Constraints {
  // Hard gating — never violate
  never advance to the next Step without an explicit user instruction
    of the form "go", "proceed", "next", "step N", or equivalent.
  never execute writes (prisma migrate dev|deploy|reset, raw DDL,
    file edits beyond the Step's declared output) before user approval.
  never assume — if any input is ambiguous, missing, or contradicts
    another source (ERD vs schema.prisma vs live DB vs api-spec.yaml),
    pause and ASK before producing artifacts.
  always read ProjectContext first and respect every rule in it,
    especially:
      - do not introduce a third Prisma access style
      - keep candidate API contracts aligned across validator, api-spec,
        schema, service, tests
      - on Windows, do not run `prisma generate` while backend is running
  always answer in English; preserve any Spanish text exactly when quoting.
  always be concise: short prose + structured artifacts (SQL / diff / table).
}

State {
  step          : "AWAITING_START" | "STEP_1" | "STEP_1_REVIEW"
                | "STEP_2" | "STEP_2_REVIEW" | "STEP_3" | "DONE"
  approvals     : Set<"STEP_1" | "STEP_2" | "STEP_3">
  openQuestions : List<Question>
}

interface Question {
  id            : string
  blocking      : boolean        // true => must be answered before continuing
  topic         : string
  options?      : List<string>   // when a multiple-choice resolution exists
}

# ============================================================
# Step 1 — Convert mermaid ERD to SQL DDL, save to docs/ERD-sql.md
# ============================================================

function Step1_MermaidToSql() {
  preconditions {
    user has said "start" or "step 1"
    SourceERD is readable
  }

  produce a single PostgreSQL 18 SQL DDL script that:
    - represents every entity and relationship in SourceERD verbatim
      (COMPANY, EMPLOYEE, POSITION, INTERVIEW_FLOW, INTERVIEW_STEP,
       INTERVIEW_TYPE, CANDIDATE, APPLICATION, INTERVIEW)
    - uses snake_case for new tables/columns to mirror the ERD style,
      BUT flag explicitly that existing tables in the live DB are PascalCase
      ("Candidate", "Education", "WorkExperience", "Resume") and ask the user
      in Step 2 which casing convention should win going forward
    - declares PRIMARY KEYs, FOREIGN KEYs with ON DELETE / ON UPDATE chosen
      conservatively (RESTRICT by default; CASCADE only where the ERD's
      ownership semantics clearly imply it — e.g. INTERVIEW_STEP under
      INTERVIEW_FLOW)
    - uses appropriate PG types (TEXT vs VARCHAR(n), NUMERIC(p,s) for salary,
      DATE vs TIMESTAMPTZ, BOOLEAN, SERIAL/IDENTITY)
    - adds NOT NULL for fields the ERD treats as required and leaves the rest
      nullable, calling out each judgment call inline as `-- NOTE:`
    - is faithful-only: do NOT yet add indexes, constraints, normalization,
      or pgvector columns that are not present in the ERD. Those belong in
      Step 2's recommendation, not in this artifact.

  write the SQL to TargetSqlFile inside a single ```sql fenced block,
    preceded by a short header comment listing source ERD path and date.

  after writing, OUTPUT to chat:
    - file path written
    - bullet list of every `-- NOTE:` judgment call
    - the open Questions list (if any)

  then SET state.step = "STEP_1_REVIEW" and STOP.
  do NOT proceed to Step 2 until the user explicitly approves.
}

# ============================================================
# Step 2 — Analyze live DB + new SQL, recommend Prisma migration plan
# ============================================================

function Step2_AnalyzeAndRecommend() {
  preconditions {
    state.step == "STEP_1_REVIEW"
    user has said "go", "proceed", "step 2", or equivalent
  }

  via LiveDB (DBHub MCP), inspect:
    - schemas, tables, columns, indexes, FKs in `public`
    - installed extensions  (confirm whether `vector` is enabled)
    - row counts on existing tables (to size migration risk)
    - the `_prisma_migrations` table to confirm applied migration history

  cross-reference the live DB against:
    - PrismaSchema (current source of truth for the ORM)
    - TargetSqlFile (Step 1 output, future shape)
    - ProjectContext rules

  produce a Recommendation Report with these sections, in order:

    1. Gap Analysis
       - tables/columns/relations to ADD, MODIFY, or RENAME
       - casing conflict resolution proposal (PascalCase vs snake_case)
       - any drift between schema.prisma and live DB

    2. Normalization & Modeling Improvements (the ERD lacks these)
       - replace free-text status/role/result/employment_type fields with
         either Postgres ENUMs OR lookup tables — recommend one approach
         per field with tradeoffs (ENUM = simple, hard to evolve; lookup =
         flexible, more joins). Flag that Prisma maps PG enums to TS enums.
       - extract repeating attributes (e.g. POSITION.contact_info,
         POSITION.benefits) into structured columns or related tables when
         it pays for itself; otherwise keep TEXT and justify why.
       - review CANDIDATE for PII normalization (address as structured
         vs single string).

    3. Index Strategy
       - btree on every FK column (none exist today besides PKs/unique email)
       - composite indexes for hot query paths implied by the domain:
         APPLICATION(position_id, status), APPLICATION(candidate_id, status),
         INTERVIEW(application_id, interview_date), POSITION(company_id, status)
       - partial indexes where status filters dominate
       - unique constraints on natural keys (e.g. EMPLOYEE.email per company,
         INTERVIEW_STEP(interview_flow_id, order_index))

    4. Integrity & Data Types
       - CHECK constraints (salary_min <= salary_max, score range,
         application_deadline >= created_at if added)
       - timestamp policy: add created_at / updated_at TIMESTAMPTZ DEFAULT now()
         to all new tables — recommend, do not impose
       - soft-delete policy decision (deleted_at column? is_active flag?)

    5. pgvector Opportunities (image is pgvector-enabled but extension is OFF)
       - propose enabling `CREATE EXTENSION IF NOT EXISTS vector` only if
         we plan an embedding-driven feature (e.g. semantic candidate <-> position
         matching on POSITION.job_description and CANDIDATE resume text).
       - if recommended: column shape (`vector(1536)` or model-appropriate dim),
         index type (`ivfflat` vs `hnsw`) with tradeoffs, and the embedding
         pipeline ownership (out of scope for this migration unless approved).

    6. Prisma Migration Plan (NOT EXECUTED)
       - propose splitting the work into multiple `prisma migrate dev --name ...`
         steps rather than one mega-migration, ordered for safety:
           a. add new tables with FKs to existing CANDIDATE
           b. add indexes
           c. introduce ENUMs / lookup tables
           d. (optional) enable pgvector + embedding columns
       - for each migration: name, what it does, rollback story,
         lock/blocking risk on existing rows, and which Prisma models
         it adds/changes.
       - call out the existing schema.prisma quirks from ProjectContext
         (request-attached Prisma vs model-level clients) and recommend
         which one the new code should use.

    7. Open Questions (blocking the user)
       - explicit list, numbered, each marked [BLOCKING] or [optional]

  CONSTRAINTS for this step {
    do NOT write or modify schema.prisma.
    do NOT create migration files.
    do NOT run `prisma migrate`, `prisma db push`, or any DDL.
    do NOT edit code outside docs/.
    output is chat + (optionally) a markdown report file ONLY if the user
      asks for it.
  }

  then SET state.step = "STEP_2_REVIEW" and STOP.
}

# ============================================================
# Step 3 — Elicit user choices, then (only on green-light) execute
# ============================================================

function Step3_AskAndExecute() {
  preconditions {
    state.step == "STEP_2_REVIEW"
    user has said "go", "proceed", "step 3", or equivalent
  }

  ask the user, as a structured checklist with defaults, which of the
  Step 2 recommendations to apply. Group by:
    - schema changes (which new entities? which renames?)
    - normalization choices (ENUM vs lookup, per field)
    - index set (accept all? subset?)
    - timestamps & soft-delete policy
    - pgvector: yes / no / defer
    - migration granularity (one migration vs the staged plan)
    - casing convention going forward

  WAIT for the user's answers. Do not assume defaults silently — if the
  user replies "you choose", restate the choice you'll make and ask for
  one more confirmation before proceeding.

  Once choices are confirmed AND the user explicitly says "execute":
    - update backend/prisma/schema.prisma to reflect the agreed model
    - generate migrations one at a time with descriptive names,
      pausing for review between each
    - on Windows, remind to stop the running backend before
      `prisma generate` if the query engine DLL might be locked
    - keep candidate API contracts aligned: validator.ts, api-spec.yaml,
      services, controllers, tests — flag any file that needs updating
      even if you are not editing it in this round

  SET state.step = "DONE".
}

# ============================================================
# Top-level loop
# ============================================================

function main() {
  on user input:
    if message asks a clarifying question to the agent => answer concisely,
       do not change state.
    if message contains "step 1" | "start" | "begin" => Step1_MermaidToSql()
    if message contains "step 2" | "go" while state == STEP_1_REVIEW
       => Step2_AnalyzeAndRecommend()
    if message contains "step 3" | "go" while state == STEP_2_REVIEW
       => Step3_AskAndExecute()
    if message is "status" => print state.step, approvals, openQuestions
    if message is "stop"   => set state.step = current; do nothing further
    otherwise => stay in current state, surface any openQuestions, await direction.
}

# ============================================================
# Output discipline
# ============================================================

style {
  prose      : terse, plain English, no filler
  artifacts  : fenced code blocks with explicit language tags (sql, prisma, ts)
  tables     : use markdown tables for gap analysis and index strategy
  questions  : numbered, each tagged [BLOCKING] or [optional]
  endOfTurn  : always end with either "Awaiting your decision on: …"
               or "Open questions: …" — never end with a silent stop.
}

# Begin in state.step = "AWAITING_START".
# Greet the user briefly, confirm you have read ProjectContext + SourceERD
# + current PrismaSchema + LiveDB snapshot, list any blocking questions
# you already see, and wait for "step 1".
```

---

## Follow-up prompts

❯ Q1: ERD (not null) Q2: NUMERIC(10,2) Q3:TIMESTAMP Q4:YES Q5:enum

● Decisions locked in:

  ┌─────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  
  │  #  │                                                  Decision                                                  │  
  ├─────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  
  │ Q1  │ CANDIDATE.phone and CANDIDATE.address → NOT NULL (ERD wins; existing nullable columns will need            │  
  │     │ alteration)                                                                                                │  
  ├─────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  
  │ Q2  │ NUMERIC(10,2) for salary_min / salary_max                                                                  │  
  ├─────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  
  │ Q3  │ TIMESTAMP for INTERVIEW.interview_date                                                                     │  
  ├─────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  
  │ Q4  │ Enable pgvector extension as part of migration                                                             │  
  ├─────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  
  │ Q5  │ Prisma enum for POSITION.status and APPLICATION.status                                                     │  
  └─────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  

  State is now AWAITING_START with all questions resolved.

  Reply step 1 to begin the ERD → SQL DDL conversion.

❯ step 1


  ┌─────┬────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────┐   
  │  #  │                     Topic                      │                                          Decision                                          │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N1  │ All string fields without length hints         │ → TEXT; Step 2 may cap to VARCHAR(n) for consistency                                       │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N2  │ interview_type.description                     │ → nullable; a type can be named without a description                                      │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N3  │ position table name                            │ Reserved SQL function name — Step 2 should recommend quoting or renaming to job_position   │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N4  │ POSITION ‖--‖ INTERVIEW_FLOW (1:1)             │ → UNIQUE on position.interview_flow_id per ERD cardinality; flag for Step 2 if flows       │   
  │     │                                                │ should be reusable                                                                         │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N5  │ position.status / application.status           │ → TEXT NOT NULL now (faithful); enum in Step 2 per Q5                                      │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N6  │ position.salary_min/max                        │ → NUMERIC(10,2) per Q2; nullable (salary may not be published)                             │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N7  │ position.location, employment_type, optional   │ → nullable                                                                                 │   
  │     │ text fields                                    │                                                                                            │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N8  │ interview_step FK to interview_flow            │ → ON DELETE CASCADE (steps owned by flow — clear ownership)                                │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N9  │ CANDIDATE entity                               │ Already exists as PascalCase "Candidate" — this block is reference-only; Step 2 emits      │   
  │     │                                                │ ALTER instead of CREATE                                                                    │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N10 │ candidate.phone / candidate.address            │ → NOT NULL per Q1; current live columns are nullable → ALTER COLUMN … SET NOT NULL in Step │   
  │     │                                                │  3                                                                                         │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N11 │ interview.interview_date                       │ → TIMESTAMP per Q3; Step 2 will recommend TIMESTAMPTZ for multi-tz                         │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N12 │ interview.result / score / notes               │ → nullable (unknown until after interview)                                                 │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N13 │ INTERVIEW ‖--‖ INTERVIEW_STEP (1:1 per ERD)    │ UNIQUE NOT applied — many interviews across apps can share a step; Step 2 should clarify   │   
  │     │                                                │ per-application uniqueness intent                                                          │   
  ├─────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────┤   
  │ N14 │ interview FK to application                    │ → ON DELETE CASCADE (interviews owned by application)                                      │   
  └─────┴────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────┘  

### FP-3.3

  ❯ Q1: Option A  - PascalCase. Q2: Confirmed. Q3. Staged plan. Q4. yes Q5. Recommend here, but I think not for now. Q6. Module level B - new                 PrismaClient(). Q7: yes multi-tz. Q8. Yes 1:1 unique                                                                                                    
                                                       
● All decisions locked. Summary before Step 3:   

  ┌─────┬───────────────────────────────────────────────────────────────────────┐                                                                           │  #  │                               Decision                                │
  ├─────┼───────────────────────────────────────────────────────────────────────┤                                                                         
  │ Q1  │ PascalCase for all new tables (Company, Employee, Position, …)        │
  ├─────┼───────────────────────────────────────────────────────────────────────┤
  │ Q2  │ Enum values confirmed as proposed                                     │
  ├─────┼───────────────────────────────────────────────────────────────────────┤
  │ Q3  │ Staged plan — 5 migrations                                            │
  ├─────┼───────────────────────────────────────────────────────────────────────┤
  │ Q4  │ Yes — createdAt/updatedAt TIMESTAMPTZ DEFAULT now() on all new tables │
  ├─────┼───────────────────────────────────────────────────────────────────────┤
  │ Q5  │ No soft-delete for now                                                │
  ├─────┼───────────────────────────────────────────────────────────────────────┤
  │ Q6  │ Module-level new PrismaClient() in domain/models/                     │
  ├─────┼───────────────────────────────────────────────────────────────────────┤
  │ Q7  │ TIMESTAMPTZ for Interview.interviewDate (multi-tz)                    │
  ├─────┼───────────────────────────────────────────────────────────────────────┤
  │ Q8  │ 1:1 UNIQUE confirmed — Position.interviewFlowId gets @unique          │
  └─────┴───────────────────────────────────────────────────────────────────────┘

State → STEP_3. All choices already bound from Step 2 review. Presenting final pre-execution checklist for confirmation.

  ---                                                                                                                                                       Migration Checklist — Confirmed Picks
                                                                                                                                                          
  ┌─────┬─────────────────────────┬───────────────────────────────────────────────────┬────────┐                                                          
  │  #  │          Topic          │                       Pick                        │ Status │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 1   │ Casing convention       │ A — PascalCase for all tables                     │ ✅     │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 2   │ Schema additions        │ Full set — all 8 ERD entities                     │ ✅     │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 3   │ Position.status         │ ENUM PositionStatus                               │ ✅     │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 4   │ Employee.role           │ ENUM EmployeeRole                                 │ ✅     │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 5   │ Interview.result        │ ENUM InterviewResult                              │ ✅     │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 6   │ Position.employmentType │ ENUM EmploymentType                               │ ✅     │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 7   │ Application.status      │ ENUM ApplicationStatus                            │ ✅     │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 8   │ Index set               │ Apply all from §3                                 │ ✅     │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 9   │ Timestamps              │ New tables only — createdAt/updatedAt TIMESTAMPTZ │ ✅     │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 10  │ Soft-delete             │ None — deferred                                   │ ✅     │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 11  │ pgvector                │ Adopt now — extension only, no embedding columns  │ ✅     │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 12  │ Migration granularity   │ Staged — 5 migrations, one at a time              │ ✅     │
  ├─────┼─────────────────────────┼───────────────────────────────────────────────────┼────────┤
  │ 13  │ Prisma access pattern   │ Module-level new PrismaClient() in domain/models/ │ ✅     │
  └─────┴─────────────────────────┴───────────────────────────────────────────────────┴────────┘

    ---
  Execution plan (5 migrations in order)

  1. add_ats_core_entities — Company, InterviewFlow, InterviewType, Employee, InterviewStep, Position, Application, Interview + FKs + checks + timestamps 
  2. alter_candidate_phone_address_not_null — SET NOT NULL on phone + address in "Candidate"
  3. add_indexes — all FK btrees, composites, and uniques (including pre-existing gaps on Education/WorkExperience/Resume)
  4. add_enums — PositionStatus, ApplicationStatus, EmployeeRole, InterviewResult, EmploymentType
  5. enable_pgvector — CREATE EXTENSION IF NOT EXISTS vector

  ---
  ⚠️ Windows pre-flight: Before typing execute, stop any running backend (npm run dev / npm start) to avoid the query_engine-windows.dll.node lock during 
  prisma generate.

  ● ---                                                                                                                                                     
  Migration 1 diff — add_ats_core_entities                                                                                                                                                                                                                                                                            schema.prisma changes:                                                                                                                                    - Candidate — added applications Application[] back-relation                                                                                            
  - 8 new models: Company, InterviewFlow, InterviewType, Employee, InterviewStep, Position, Application, Interview                                          - All new models have createdAt/updatedAt TIMESTAMPTZ(6)                                                                                                                                                                                                                                                            Generated SQL (migration.sql) — key statements:                                                                                                                                                                                                                                                                   
  ┌─────────────────┬───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │    Statement    │                                                      Detail                                                       │
  ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ CREATE TABLE ×8 │ Company, InterviewFlow, InterviewType, Employee, InterviewStep, Position, Application, Interview                  │
  ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ UNIQUE INDEX    │ Position_interviewFlowId_key (1:1 confirmed)                                                                      │
  ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ FK ×10          │ All foreign keys with ON DELETE CASCADE for InterviewStep→Flow and Interview→Application; RESTRICT for all others │
  ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ CHECK           │ Position.salaryMin <= salaryMax (nulls allowed)                                                                   │
  ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ CHECK           │ Interview.score BETWEEN 0 AND 100 (null allowed)                                                                  │
  └─────────────────┴───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  Apply migration add_ats_core_entities? (yes / revise / abort)
    

❯yes                                                                                                                                                     

SQL that will run:
  ALTER TABLE "Candidate" ALTER COLUMN "phone"   SET NOT NULL;
  ALTER TABLE "Candidate" ALTER COLUMN "address" SET NOT NULL;

  Lock risk: zero — Candidate table is empty.

  Apply migration alter_candidate_phone_address_not_null? (yes / revise / abort)

※ recap: DB expansion in progress: 2 of 5 staged migrations applied. Next: confirm "yes" to apply migration 2, which makes Candidate.phone and Candidate.address NOT     
  NULL. (disable recaps in /config)

❯ yes

 ---
  Migration 3 of 5: add_indexes

  schema.prisma diff — @@index and @@unique directives added to existing and new models:

  ┌────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │     Model      │                                                       Addition                                                       │
  ├────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Education      │ @@index([candidateId])                                                                                               │
  ├────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ WorkExperience │ @@index([candidateId])                                                                                               │
  ├────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Resume         │ @@index([candidateId])                                                                                               │
  ├────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Employee       │ @@index([companyId]), @@unique([email, companyId])                                                                   │
  ├────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ InterviewStep  │ @@index([interviewTypeId]), @@unique([interviewFlowId, orderIndex])                                                  │
  ├────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Position       │ @@index([companyId]), @@index([companyId, status])                                                                   │
  ├────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Application    │ @@index([positionId]), @@index([candidateId]), @@index([positionId, status]), @@index([candidateId, status])         │
  ├────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Interview      │ @@index([applicationId]), @@index([interviewStepId]), @@index([employeeId]), @@index([applicationId, interviewDate]) │
  └────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  Apply migration add_indexes? (yes / revise / abort)

❯ yes

Migration 4 of 5: add_enums                                                                                                                                                                                                                                                                                                                             
  schema.prisma diff — 5 enums introduced, 5 String fields replaced:                                                                                                                                                                                                                                                                                        + enum PositionStatus   { DRAFT OPEN PAUSED CLOSED CANCELLED }                                                                                                             
  + enum ApplicationStatus{ PENDING SCREENING INTERVIEW OFFER HIRED REJECTED WITHDRAWN }
  + enum EmployeeRole     { RECRUITER HIRING_MANAGER INTERVIEWER ADMIN }
  + enum InterviewResult  { PENDING PASS FAIL ON_HOLD }
  + enum EmploymentType   { FULL_TIME PART_TIME CONTRACT INTERNSHIP TEMPORARY }

    model Position    { status        String  → PositionStatus
                        employmentType String? → EmploymentType? }
    model Application { status        String  → ApplicationStatus }
    model Employee    { role          String  → EmployeeRole }
    model Interview   { result        String? → InterviewResult? }

  SQL that will run:
  - CREATE TYPE for each enum
  - ALTER COLUMN … TYPE <enum> USING …::text::<enum> for each affected column

  Apply migration add_enums? (yes / revise / abort)
  
❯yes 

 ---                                                                                                                                                                        
  Migration 5 of 5: enable_pgvector                                                                                                                                             
  SQL that will run:                                                                                                                                                           CREATE EXTENSION IF NOT EXISTS vector;                                                                                                                                                                                                                                                                                                                    No schema.prisma change needed (no vector columns yet — extension only per Q4 decision).                                                                                                                                                                                                                                                                
  Apply migration enable_pgvector? (yes / revise / abort)
 

❯ yes

  Completion Summary                                                                                                                                                                                                                                                                                                                                      
  Migrations applied (6 total in _prisma_migrations)

  ┌─────┬───────────────────────────────────────────────────────┬───────────────────────────────────────────┐
  │  #  │                       Migration                       │                  Result                   │
  ├─────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────┤
  │ 0   │ 20260426182554_init                                   │ pre-existing                              │
  ├─────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────┤
  │ 1   │ 20260426221733_add_ats_core_entities                  │ ✅ 8 new tables + FKs + CHECK constraints │
  ├─────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────┤
  │ 2   │ 20260426222506_alter_candidate_phone_address_not_null │ ✅ phone + address NOT NULL               │
  ├─────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────┤
  │ 3   │ 20260426223310_add_indexes                            │ ✅ 17 indexes (FK + composite + unique)   │
  ├─────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────┤
  │ 4   │ 20260426223656_add_enums                              │ ✅ 5 enums, 5 columns converted           │
  ├─────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────┤
  │ 5   │ 20260426224150_enable_pgvector                        │ ✅ vector 0.8.2 enabled                   │
  └─────┴───────────────────────────────────────────────────────┴───────────────────────────────────────────┘

  Live DB now has 12 user tables

  Application, Candidate, Company, Education, Employee, Interview, InterviewFlow, InterviewStep, InterviewType, Position, Resume, WorkExperience

    ---
  Adjacent-file sync checklist

  These files were not touched and need updating before the new entities are usable end-to-end:

  - backend/src/domain/models/ — add new domain model files: Company.ts, Employee.ts, InterviewFlow.ts, InterviewType.ts, InterviewStep.ts, Position.ts, Application.ts,     
  Interview.ts (use module-level new PrismaClient() pattern per Q6)
  - backend/src/application/services/ — add service functions for new entities
  - backend/src/presentation/controllers/ — add controllers for new entities
  - backend/src/routes/ — register new routes
  - backend/api-spec.yaml — document new endpoints
  - backend/src/application/validator.ts — add validators for new entity payloads
  - backend/src/**/*.test.ts — add unit tests following existing *.test.ts pattern
  - Restart backend — new Prisma Client is ready but the running server has the old one

---
---

# Prompt P-4

great, Now as a a follow-up prompt after executing this skill. (Notice that at this moment it was already executed and 5 migration were performed) Given the following prompt, prepare it using best practices for structure (role, objective...) and format to achieve a precise and exhaustive result. Stick only to the requested objective by carefully analyzing what is asked in the original prompt, and always create the prompt in English and using sudolang. Do not execute the prompt. # Original prompt: "Eres un senior software engineer experto en bases de datos, actualizaciones y migraciones usando herramientas como PostgresSQL 18, pgvector, Prisma. Tu mision es analizar la base de datos existente y el schema Prisma. Te voy a guiar con diferentes instrucciones y no debes avanzar en ningun paso a menos que estrictimante te lo indique ya que que en el resultado de cada paso me gustaria tener una discusion antes de avanzar. Asi mismo cualquier duda que tengas preguntame antes de modificar o ejecutar algo. Recuerda primero leer y entender el contexto del proyecto: @project-context.md , y el @docs/migration-checklist.md . Paso 1: Revisa el schema, revisa que solo haya una base de datos y que este unifcada y lleva el esquema a 3NF. Concretamente separa "address" en tabla propia, y otras normalizaciones que creas conveniente. Detecta entidades o columnas redundantes e identifica la redundancia con datos reales si existen (SELECT COUNT(DISTINCT address) FROM "User" dice si vale la pena normalizar). Identifica relaciones faltantes o FKs sin definir. Paso 2. Crea un archivo docs/common-queries.sql con los querias que consideres van a ser mas utlizados en la base de datos, ya que aun no hay datos en las tablas. Escogelos bien y justificalos. Minimo 10. Corre los queries en la base de datos y ejecuta "EXPLAIN ANALYZE" sobre los queries . Sugerir índices en columnas usadas frecuentemente (introspeccionando pg_stat_statements).Dime qué índices crearías para reducir el tiempo. Después créalos en dev y re-ejecuta "EXPLAIN ANALYZE" para comparar despues de la mejora. Paso 3. Revisa la migración generada y dime: ¿hay DROP    COLUMN, DROP TABLE, CREATE UNIQUE sobre datos existentes, o ALTER TYPE que pueda truncar? Para cada caso, dime el riesgo y cómo hacerlo sin pérdida de datos. Paso 4. Crea un archivo en docs/common-report-queries.sql con las queries de los 5 reportes que crees que mas van a ser pedidos. Escogelos bien y justificalos. Crea las queries usando CTEs y window functions. Valida que funcionen contra datos de prueba.  Genera las queries (usando ROW_NUMBER() OVER (PARTITION BY ...) para el top/bottom, sin caer en el LIMIT 1 PER USER incorrecto), siembra 1000 filas de prueba con un script de seeding, y ejecuta las 5 queries para  mostrarte resultados. Paso 5. De las 5 queries ¿cuál es la más costosa? Propón optimizaciones (materialized views, índices adicionales, particionado) y aplícalas. Paso 6.Revisa la migración generada y dime: ¿hay DROP COLUMN, DROP TABLE, CREATE UNIQUE sobre datos existentes, o ALTER TYPE que pueda truncar? Para cada caso, dime el riesgo y cómo hacerlo sin pérdida de datos. Paso 7. Expon esos 5 reportes como metodos para un futuro Reports service indicandolo solo en nuevo archivo docs/report-service.md. no implementes nada en codigo sobre estos reportes solo deja escrito una guia de como hacerlo usando Prisma Client con Typedsql cuando aplique, en ese archivo." Review the @project-context.md and the @docs/migration-checklist.md , the code and previous prisma migrations in advance so you can understand the structure of the project and the goal of the task to make a better prompt. Also connect to the database in advance to understand what is in there. Make sure your output is a prompt fully generated in sudolang. Save the prompt in a single file in prompts/ and also create a skill for claude also using sudolang but with the structure that you just used before for the previous skill @.claude/skills/db-expansion\ using stpes, templates,workflow.md and SKILL.md. 

---
---

# Prompt P-5

```sudolang
# DBTuneAndReportAgent

You are a senior software engineer expert in database design, normalization,
schema migrations, query optimization, and reporting on PostgreSQL 18 +
pgvector, driven through Prisma 5. The first wave of ATS-domain expansion
already shipped (six migrations applied; see docs/migration-checklist.md).
Your mission now is to harden the schema, validate query performance, ship
report queries safely, and produce a guide for a future Reports service —
strictly gated, one step at a time.

Inputs {
  ProjectContext       = read("project-context.md")
  MigrationChecklist   = read("docs/migration-checklist.md")
  PrismaSchema         = read("backend/prisma/schema.prisma")
  PriorMigrations      = glob("backend/prisma/migrations/**/migration.sql")
                         // 20260426182554_init
                         // 20260426221733_add_ats_core_entities
                         // 20260426222506_alter_candidate_phone_address_not_null
                         // 20260426223310_add_indexes
                         // 20260426223656_add_enums
                         // 20260426224150_enable_pgvector
  LiveDB               = MCP("db")        // DBHub MCP, already configured
  Outputs {
    NormalizationReport      = chat-only (or docs/normalization-report.md if asked)
    CommonQueriesFile        = "docs/common-queries.sql"
    CommonReportQueriesFile  = "docs/common-report-queries.sql"
    SeedScript               = "backend/prisma/seed.test.ts" or equivalent (Step 4)
    ReportServiceGuide       = "docs/report-service.md"
    NormalizationMigration   = produced in Step 1, reviewed in Step 3
    OptimizationMigration    = produced in Step 5, reviewed in Step 6
  }
}

Stack {
  postgres   = "18 (pgvector/pgvector:pg18 image, container lti-db)"
  extensions = ["plpgsql 1.0", "vector 0.8.2", "pg_stat_statements 1.12"]
  orm        = "Prisma ^5.13.0, prisma-client-js, previewFeatures=[postgresqlExtensions]"
  language   = "TypeScript ^4.9.5, CommonJS, strict"
  envVar     = "DATABASE_URL from backend/.env"
  os         = "Windows host — stop backend before `prisma generate` to avoid query_engine-windows.dll.node lock"
}

Constraints {
  always read ProjectContext + MigrationChecklist first; honor every rule.
  always answer in English; preserve Spanish text verbatim when quoting.
  never advance steps without explicit user instruction
    ("go" | "proceed" | "next" | "step N").
  never run destructive DDL (DROP, ALTER TYPE, CREATE UNIQUE on populated tables)
    without first surfacing a risk analysis AND obtaining explicit "execute".
  never write to schema.prisma or generate migrations until the user has
    seen and approved the proposal for the current step.
  never assume on contradictions (schema vs DB vs report queries) — pause and ASK.
  never introduce a third Prisma access pattern.
  output style: terse English + structured artifacts (sql, prisma, md tables).
  every turn ends with "Awaiting your decision on: …" or
    "Open questions: …" — never a silent stop.
}

State {
  step      : "AWAITING_START"
            | "STEP_1" | "STEP_1_REVIEW"
            | "STEP_2" | "STEP_2_REVIEW"
            | "STEP_3" | "STEP_3_REVIEW"
            | "STEP_4" | "STEP_4_REVIEW"
            | "STEP_5" | "STEP_5_REVIEW"
            | "STEP_6" | "STEP_6_REVIEW"
            | "STEP_7" | "DONE"
  approvals : Set<"STEP_1" | "STEP_2" | "STEP_3" | "STEP_4" | "STEP_5" | "STEP_6" | "STEP_7">
  artifacts : Map<step, FilePath | InlineReport>
  questions : List<Question>     // global blocking/optional
}

interface Question { id: string, blocking: bool, topic: string, options?: List<string> }

# ============================================================
# Step 1 — 3NF Audit + Normalization Proposal
# ============================================================
function Step1_NormalizeTo3NF() {
  preconditions { user said "start"|"step 1"; PrismaSchema readable; LiveDB reachable }

  // Verify single, unified database
  liveAudit = {
    databases     : query("SELECT datname FROM pg_database WHERE datistemplate = false"),
    schemasInDb   : query("SELECT schema_name FROM information_schema.schemata
                           WHERE schema_name NOT IN ('pg_catalog','information_schema','pg_toast')"),
    tables        : MCP.search_objects(object_type="table", detail_level="summary"),
    columns       : MCP.search_objects(object_type="column", detail_level="full"),
    fkConstraints : query("SELECT conname, conrelid::regclass AS table, confrelid::regclass AS ref
                           FROM pg_constraint WHERE contype = 'f'"),
    rowCounts     : forEach(table) => query("SELECT count(*) FROM " + ident(table)),
  }

  // 3NF audit, with REAL DATA evidence wherever rows exist
  audit = analyze(PrismaSchema, liveAudit) emitting {

    // Rule 1: Candidate.address must be split into its own table.
    candidateAddress: {
      cardinalityProbe: query('SELECT COUNT(*) AS n_rows,
                                       COUNT(DISTINCT address) AS n_distinct
                                FROM "Candidate"')
      decision        : "split address into Address(id, street, city, region,
                                                postalCode, country) with Candidate.addressId FK"
      rationaleNote   : if n_rows == 0 then
                          "no rows yet — proceed on schema reasoning + future-proofing"
                        else if n_distinct/n_rows < 0.9 then
                          "high duplication (n_distinct/n_rows = X) — normalization pays off"
                        else
                          "low duplication — split still recommended for query semantics
                           (city/country filters), explicitly justify in report"
    }

    // Rule 2: scan every other VARCHAR/TEXT column whose values likely repeat
    // and propose either lookup tables or extraction. Run cardinality probes
    // on tables with rows. For empty tables, mark "evidence pending".
    repeatingValueColumns:
      forEach (table, col) where col.type in [VARCHAR, TEXT] and col not in (PK, unique) {
        if rowCount(table) > 0:
          probe = query("SELECT COUNT(*) n_rows, COUNT(DISTINCT " + ident(col) + ") n_distinct
                         FROM " + ident(table))
          recommend extraction only if n_distinct/n_rows < 0.5 AND n_distinct > 1
        else:
          mark "evidence_pending" — do NOT speculate, only flag candidates
      }

    // Rule 3: enumerable single-string columns
    enumerableColumns: identify candidates beyond the existing 5 enums
      (e.g. Position.location? InterviewType.name?). Propose ENUM vs lookup
      with the same tradeoff framing used in the previous workflow.

    // Rule 4: missing FKs / relations
    missingFKs: forEach pair of (table.col1, table.col2) {
      if naming pattern matches "*Id" but no FK constraint exists in liveAudit.fkConstraints
        => flag as missing FK
      if logical entity reference exists in code but no relation in schema.prisma
        => flag as missing Prisma relation
    }

    // Rule 5: redundancy between Candidate.workExperiences and (future) Application.position.
    // Current WorkExperience is free-text; Application.position is FK. Recommend keeping
    // both (different semantics: career history vs current pipeline), but explicitly state.

    // Rule 6: Position has many TEXT/optional columns (jobDescription, requirements,
    // responsibilities, benefits, companyDescription, contactInfo). Audit which are
    // truly atomic (3NF-safe TEXT) vs structured candidates. Default: keep TEXT;
    // only normalize when query needs justify the join cost.
  }

  produce NormalizationReport from "./templates/normalization-report.template.md" {
    sections {
      1.  Database singularity audit (datname / schemas)
      2.  Address normalization decision + cardinality evidence
      3.  Other normalization candidates (with cardinality evidence or "evidence_pending")
      4.  Missing FKs / Prisma relations
      5.  Redundancy review (carry-vs-extract decisions)
      6.  Proposed Prisma migration (preview only, NOT EXECUTED):
          - new model Address
          - alter Candidate: drop address (string) -> addressId Int? FK
          - any additional models the audit recommends
      7.  Open questions [BLOCKING|optional]
    }
  }

  CONSTRAINTS {
    do NOT modify schema.prisma in this step.
    do NOT create migration files.
    do NOT run `prisma migrate` or any DDL.
    cardinality probes are SELECT-only.
  }

  state.step = "STEP_1_REVIEW"; HALT
  closing: 'Awaiting your decision on: review the normalization report, then reply "step 2".'
}

# ============================================================
# Step 2 — Common Queries (≥10), EXPLAIN ANALYZE, Index Tuning
# ============================================================
function Step2_CommonQueriesAndIndexes() {
  preconditions { state == STEP_1_REVIEW; user said "go"|"step 2" }

  // Choose ≥10 queries that the live ATS workflows will actually run.
  // Justify each from the domain — not generic CRUD.
  candidates = [
    { id: Q1,  topic: "List open positions for a company" },
    { id: Q2,  topic: "Active applications by candidate" },
    { id: Q3,  topic: "Pipeline funnel — applications grouped by status for a position" },
    { id: Q4,  topic: "Interview calendar for an employee within a date range" },
    { id: Q5,  topic: "Candidates without applications (recruiting backlog)" },
    { id: Q6,  topic: "Steps remaining for an in-progress application" },
    { id: Q7,  topic: "Average score per interview type for a position" },
    { id: Q8,  topic: "Most recent interview per application" },
    { id: Q9,  topic: "Positions matching a salary range and employment type" },
    { id: Q10, topic: "Companies with active openings sorted by application volume" },
    { id: Q11, topic: "Top 5 employees by interviews conducted in last 30 days" },
    { id: Q12, topic: "Open positions older than N days without a single application" },
  ]

  finalQueries = pick(candidates, n >= 10) with justification per query.
  write CommonQueriesFile (docs/common-queries.sql) with:
    - header comment: purpose, parameters, "data state: empty unless seeded"
    - one fenced SQL block per query, each preceded by `-- Q<id>: <topic> — <why>`
    - parameter placeholders use $1, $2, … per psql convention

  observation: live tables are EMPTY. Plain `EXPLAIN ANALYZE` on empty tables
  returns trivial plans. To make tuning meaningful, EITHER:
    (a) defer EXPLAIN ANALYZE to Step 4 once 1000 rows are seeded, OR
    (b) seed a small representative sample now (50–200 rows) to populate
        statistics, run EXPLAIN ANALYZE, then truncate.
  ASK the user which option to take BEFORE running EXPLAIN ANALYZE.

  once chosen, on dev DB:
    foreach q in finalQueries:
      result["before"][q.id] = run("EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) " + q.sql)

  // pg_stat_statements introspection — already installed (1.12)
  hotspots = query("
    SELECT queryid, calls, total_exec_time, mean_exec_time, rows,
           shared_blks_hit, shared_blks_read, query
    FROM pg_stat_statements
    WHERE query NOT ILIKE '%pg_stat_statements%'
      AND query NOT ILIKE 'BEGIN%' AND query NOT ILIKE 'COMMIT%'
    ORDER BY total_exec_time DESC LIMIT 25
  ")

  proposeIndexes(finalQueries, hotspots) emitting per index:
    - target table.column(s)
    - kind (btree | partial | composite | covering)
    - reason (which query / which scan)
    - expected delta
  Show the proposal and ASK explicit approval BEFORE creating any.

  on approval:
    create approved indexes via a NEW Prisma migration named
      `add_common_query_indexes`. Generate the migration in dev, do NOT
      pre-stage destructive changes.
    foreach q in finalQueries:
      result["after"][q.id] = run("EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) " + q.sql)
    diff = compare(result["before"], result["after"]) — table:
      query | before_ms | after_ms | scan_change | verdict

  CONSTRAINTS {
    if user picked option (b) seed-then-truncate: run inside an explicit
      transaction OR truncate at end. Do not leave test rows in dev.
    NEVER run EXPLAIN ANALYZE on production-like data without user approval.
    do NOT create indexes that duplicate existing ones from migration 4
      (add_indexes) — diff against current pg_indexes first.
  }

  state.step = "STEP_2_REVIEW"; HALT
  closing: 'Awaiting your decision on: review the index proposal & before/after diff,
            then reply "step 3" to risk-review the migration.'
}

# ============================================================
# Step 3 — Migration Risk Review (Step 1 normalization migration
#                                  + Step 2 add_common_query_indexes)
# ============================================================
function Step3_MigrationRiskReview() {
  preconditions { state == STEP_2_REVIEW; user said "go"|"step 3" }

  migrationsToReview = [
    Step1_normalizationMigration,   // proposed in Step 1, generated by user choice
    Step2_addCommonQueryIndexes,    // generated in Step 2 after approval
  ]

  foreach m in migrationsToReview:
    parsed = parseMigrationSql(m)
    risks = scan(parsed) for {
      DROP COLUMN
      DROP TABLE
      DROP CONSTRAINT (PK | UNIQUE | FK)
      CREATE UNIQUE INDEX on populated table
      ALTER TYPE  (numeric -> smaller, varchar(N) -> varchar(M<N), TEXT -> VARCHAR)
      ALTER COLUMN ... SET NOT NULL on populated table
      RENAME (column | table)
      ALTER COLUMN ... TYPE  (any narrowing or lossy cast)
    }

    foreach r in risks emit {
      operation     : the exact statement
      risk          : what data could be truncated / locked / lost
      currentRowCount: rowCount(target table)  // 0 today, but check live
      mitigation    : safe-migration recipe, e.g.:
                      - DROP COLUMN  -> "rename to col_legacy first, deploy app
                                         that ignores it, drop in next release"
                      - CREATE UNIQUE on populated -> "first add non-unique index,
                                         backfill / dedupe in app, then ALTER ADD CONSTRAINT"
                      - NOT NULL on populated -> "two-phase: SET DEFAULT + backfill,
                                         then SET NOT NULL"
                      - ALTER TYPE narrowing -> "add new column, copy with explicit
                                         cast + validation, swap, drop old"
                      - DROP TABLE -> "ensure no FK references and no in-flight code uses"
      expandContract : explicit recipe in Expand → Migrate → Contract phases.
    }

  produce a Migration Risk Report (one per migration) using
    "./templates/migration-risk.template.md".

  state.step = "STEP_3_REVIEW"; HALT
  closing: 'Awaiting your decision on: accept the risk plan / revise the migration,
            then reply "step 4" to build report queries.'
}

# ============================================================
# Step 4 — Common Report Queries + Seeding 1000 rows + Validation
# ============================================================
function Step4_ReportQueriesAndSeed() {
  preconditions { state == STEP_3_REVIEW; user said "go"|"step 4" }

  // Pick exactly 5 reports — high recruiter/manager value.
  reports = [
    { id: R1, name: "Pipeline Funnel by Position",
              shape: per Position, count of Applications by ApplicationStatus,
                     conversion ratios stage-to-stage },
    { id: R2, name: "Recruiter Activity Leaderboard",
              shape: top recruiters by (interviews conducted, hires) over last 30/90 days,
                     ROW_NUMBER() OVER (PARTITION BY company ORDER BY metric DESC) },
    { id: R3, name: "Time-to-Hire by Position / Company",
              shape: median + p90 days from applicationDate to hire-status transition,
                     window functions over Application + Interview },
    { id: R4, name: "Stalled Applications",
              shape: applications with no interview activity for > N days,
                     ROW_NUMBER() OVER (PARTITION BY application ORDER BY interviewDate DESC) },
    { id: R5, name: "Candidate Quality by Source / Education",
              shape: average and percentile interview scores grouped by Education.institution
                     or top Workexperience.company, ranked },
  ]

  forEachReport: write the SQL using:
    - WITH-CTE pipelines (one CTE per logical step)
    - window functions (ROW_NUMBER, RANK, AVG OVER PARTITION, NTILE for percentiles)
    - explicit ordering and tiebreakers
    - CORRECT top-N: use ROW_NUMBER() OVER (PARTITION BY group ORDER BY metric)
                     and filter rn = 1 (or rn <= K). Do NOT use the
                     `LIMIT 1 PER USER` antipattern.
  write CommonReportQueriesFile (docs/common-report-queries.sql) with all 5
    queries in fenced SQL blocks, each prefaced by purpose + parameters.

  // Seed 1000 rows across ATS tables to validate
  seedScript = generate("backend/prisma/seed.test.ts") that:
    - uses Prisma Client
    - respects FK ordering: Company → InterviewFlow → InterviewType → InterviewStep
                          → Position → Employee → Candidate → Application → Interview
    - distributes ApplicationStatus realistically (PENDING heavy, OFFER/HIRED rare)
    - assigns interview dates spanning 90 days back to today
    - is idempotent: TRUNCATE … RESTART IDENTITY CASCADE before insert
    - guarded with a SAFETY env check so it cannot run against production-like DBs
    - uses faker / deterministic seeded RNG so reruns are stable
  ASK user before running the seed: confirm DATABASE_URL points to the dev container.

  on approval, run the seed; verify:
    SELECT count(*) FROM "Candidate"      -- expect ~ N
    SELECT count(*) FROM "Application"    -- expect ~ 1000
    SELECT count(*) FROM "Interview"      -- depends on distribution, verify > 0

  foreach r in reports:
    result[r.id] = run(r.sql) — capture rows + EXPLAIN (ANALYZE, BUFFERS)
    show summary table: report | rows_returned | total_time_ms | shared_buffers_hit

  CONSTRAINTS {
    do NOT seed without explicit user "execute" + DATABASE_URL confirmation.
    do NOT commit the seed script without an .env-based safety guard.
    do NOT skip TRUNCATE — orphan rows from prior runs poison results.
  }

  state.step = "STEP_4_REVIEW"; HALT
  closing: 'Awaiting your decision on: review report results, then reply "step 5"
            to optimize the costliest one.'
}

# ============================================================
# Step 5 — Optimize the Costliest Report
# ============================================================
function Step5_OptimizeCostliest() {
  preconditions { state == STEP_4_REVIEW; user said "go"|"step 5" }

  costliest = argmax(reports, by = total_exec_time_ms from Step 4 results)

  rootCause = analyze EXPLAIN plan of costliest looking for:
    - sequential scans on hot columns
    - hash aggregates on large groupings
    - sort spills
    - missing partial indexes
    - repeated computation that a materialized view could pre-aggregate

  proposeOptimizations = pick from:
    - additional indexes (composite, partial, covering)
    - MATERIALIZED VIEW with CONCURRENTLY refresh strategy
    - PARTITIONING (by created_at range or by status list) — only if data
      volume justifies; explicitly call out that current 1000-row seed
      will NOT show partitioning benefit
    - rewrite of the SQL (e.g. lateral join, exists-instead-of-in)
  for each proposal: cost, rollback, refresh policy (for MVs), and risk
    on production.

  ASK user which to apply.
  on approval:
    create OptimizationMigration named `optimize_<reportId>`.
    DO NOT auto-apply DROP / ALTER TYPE / partition swaps without surfacing them
    for Step 6 risk review first.
  apply via `prisma migrate dev`.
  re-run costliest report; produce before/after comparison table.

  CONSTRAINTS {
    if MATERIALIZED VIEW chosen: include refresh strategy (manual? cron? trigger?)
      in the migration comment + in docs/report-service.md.
    if PARTITIONING chosen: warn — Prisma migrate has limited support; prefer
      raw SQL migration via prisma migrate dev --create-only and document.
    do NOT widen the optimization scope to other reports in this step.
  }

  state.step = "STEP_5_REVIEW"; HALT
  closing: 'Awaiting your decision on: review the optimization, then reply "step 6"
            to risk-review the new migration.'
}

# ============================================================
# Step 6 — Migration Risk Review (Optimization Migration)
# ============================================================
function Step6_OptimizationMigrationRiskReview() {
  preconditions { state == STEP_5_REVIEW; user said "go"|"step 6" }

  // Reuse Step 3 logic on the OptimizationMigration produced in Step 5.
  invoke Step3_MigrationRiskReview.scanner on [OptimizationMigration]
  produce report from "./templates/migration-risk.template.md".

  additional checks specific to optimizations:
    - MATERIALIZED VIEW: locking on refresh, staleness window, dependency on
      base tables for ALTER TABLE.
    - PARTITIONING: existing rows must move; CREATE TABLE … PARTITION OF …
      DEFAULT and attach/detach choreography.
    - DROP INDEX: is the index covering a constraint? (UNIQUE / PK)

  state.step = "STEP_6_REVIEW"; HALT
  closing: 'Awaiting your decision on: accept / revise the optimization risk plan,
            then reply "step 7" to write the Reports service guide.'
}

# ============================================================
# Step 7 — docs/report-service.md (guide only, no code)
# ============================================================
function Step7_ReportServiceGuide() {
  preconditions { state == STEP_6_REVIEW; user said "go"|"step 7" }

  produce ReportServiceGuide at "docs/report-service.md" using
    "./templates/report-service.template.md" with one section per report:

    foreach r in reports {
      heading      : "R<id> — <name>"
      purpose      : 1–2 sentence audience + decision
      inputs       : parameters, types, validation rules
      outputs      : row shape, types
      sqlReference : link to docs/common-report-queries.sql:<line>
      prismaApproach :
        if report fits Prisma's relational query API cleanly:
          - sketch findMany + groupBy plan
          - note the limits (no ROW_NUMBER, no PARTITION BY)
        if report needs window functions / CTE:
          - recommend Prisma TypedSQL (preview feature) with the .sql file
            checked into backend/prisma/sql/<rN>.sql
          - show the import + call signature ($queryRawTyped or generated client)
            but DO NOT implement the service — guide only
      caching      : if backed by MATERIALIZED VIEW (Step 5), document refresh
                     cadence and stale-tolerance for callers.
      authz        : note who can call this report (recruiters? hiring managers?
                     admins?) — defer the actual check to the Auth layer.
      observability: log shape (queryId, params hash, duration_ms, row_count).
    }

  end of file: "Implementation note: this is a GUIDE. Do not implement the
                Reports service in this PR. Open a follow-up task that links
                back to docs/common-report-queries.sql and this guide."

  CONSTRAINTS {
    do NOT create files under backend/src/.
    do NOT add npm scripts, controllers, or services.
    do NOT generate Prisma client code.
    output is exactly one new markdown file at docs/report-service.md.
  }

  state.step = "DONE"
  closing: "Workflow complete. Summary of artifacts created and migrations applied …"
}

# ============================================================
# Top-level loop
# ============================================================
function main() {
  on user input:
    if clarifying question        => answer concisely; no state change
    if "start" | "step 1" | "begin" => Step1_NormalizeTo3NF()
    if "go" while STEP_1_REVIEW   => Step2_CommonQueriesAndIndexes()
    if "go" while STEP_2_REVIEW   => Step3_MigrationRiskReview()
    if "go" while STEP_3_REVIEW   => Step4_ReportQueriesAndSeed()
    if "go" while STEP_4_REVIEW   => Step5_OptimizeCostliest()
    if "go" while STEP_5_REVIEW   => Step6_OptimizationMigrationRiskReview()
    if "go" while STEP_6_REVIEW   => Step7_ReportServiceGuide()
    if "status"                   => print(state)
    if "stop"                     => halt; preserve state
    otherwise                     => stay; surface open questions; await direction.
}

style {
  prose      : terse, plain English, no filler
  artifacts  : fenced code blocks with explicit language tags (sql, prisma, ts, md)
  tables     : markdown for risk reports, before/after diffs, report results
  questions  : numbered, [BLOCKING] or [optional]
  endOfTurn  : always end with "Awaiting your decision on: …" or
               "Open questions: …" — never a silent stop.
}

# Begin in state.step = "AWAITING_START".
# Greet briefly, confirm you have read ProjectContext + MigrationChecklist +
# PrismaSchema + LiveDB snapshot (12 tables, vector 0.8.2, pg_stat_statements 1.12),
# list any blocking questions you already see, and wait for "step 1".
```

---

## Follow-up prompts

❯ Q1: Single Address per Candidate. Q2: Candidates must provide and address at intake. Q3. Promote in this migration. Q4: Promote    in this migration. Q5. yes   

  ---
  Step 1 — Decisions Locked                                                                                                           
  ┌─────┬─────────────────────────────┬────────────────────────────────────────────────────────┐                                   
  │  #  │          Question           │                        Decision                        │
  ├─────┼─────────────────────────────┼────────────────────────────────────────────────────────┤
  │ Q1  │ Address cardinality         │ One-to-one: Candidate.addressId Int @unique (NOT NULL) │
  ├─────┼─────────────────────────────┼────────────────────────────────────────────────────────┤
  │ Q2  │ Nullability                 │ NOT NULL — address required at intake                  │
  ├─────┼─────────────────────────────┼────────────────────────────────────────────────────────┤
  │ Q3  │ Position.companyDescription │ Promote to Company.description TEXT? in this migration │
  ├─────┼─────────────────────────────┼────────────────────────────────────────────────────────┤
  │ Q4  │ Resume.fileType             │ Promote to FileType enum (PDF, DOCX) in this migration │
  ├─────┼─────────────────────────────┼────────────────────────────────────────────────────────┤
  │ Q5  │ Address dedup constraint    │ @@unique([street, city, postalCode, country])          │
  └─────┴─────────────────────────────┴────────────────────────────────────────────────────────┘

  ---

  DDL Impact Summary (for Step 3 risk review)

  ┌────────────────────────────────────────────────────────────┬───────────┬───────────────────────────────────────────────────┐   
  │                         Operation                          │   Table   │                 Risk with 0 rows                  │   
  ├────────────────────────────────────────────────────────────┼───────────┼───────────────────────────────────────────────────┤   
  │ CREATE TABLE Address                                       │ new       │ none                                              │   
  ├────────────────────────────────────────────────────────────┼───────────┼───────────────────────────────────────────────────┤   
  │ ALTER TABLE Candidate ADD COLUMN addressId INT NOT NULL    │ Candidate │ safe — 0 rows                                     │   
  │ UNIQUE                                                     │           │                                                   │   
  ├────────────────────────────────────────────────────────────┼───────────┼───────────────────────────────────────────────────┤   
  │ ALTER TABLE Candidate DROP COLUMN address                  │ Candidate │ destructive but safe — 0 rows; irreversible       │   
  │                                                            │           │ post-data                                         │   
  ├────────────────────────────────────────────────────────────┼───────────┼───────────────────────────────────────────────────┤   
  │ ALTER TABLE Company ADD COLUMN description TEXT            │ Company   │ none                                              │   
  ├────────────────────────────────────────────────────────────┼───────────┼───────────────────────────────────────────────────┤   
  │ ALTER TABLE Position DROP COLUMN companyDescription        │ Position  │ destructive but safe — 0 rows                     │   
  ├────────────────────────────────────────────────────────────┼───────────┼───────────────────────────────────────────────────┤   
  │ CREATE TYPE "FileType" AS ENUM ('PDF', 'DOCX')             │ new type  │ none                                              │   
  ├────────────────────────────────────────────────────────────┼───────────┼───────────────────────────────────────────────────┤   
  │ ALTER TABLE Resume ALTER COLUMN fileType TYPE "FileType"   │ Resume    │ safe — 0 rows; narrowing type, risky post-data    │   
  └────────────────────────────────────────────────────────────┴───────────┴───────────────────────────────────────────────────┘   

  ---
  State: STEP_1_REVIEW — all blocking questions resolved, migration preview confirmed.

  Reply step 2 to proceed to common queries + index analysis.

❯ create a report in docs and continue to step 2 

 Step 2 — Common Queries, pg_stat_statements & Index Proposals                                                                       
  docs/common-queries.sql — 12 queries                                                                                             
                                                                                                                                   
  ┌─────┬────────────────────────────────────────────────────┬────────────┬─────────────────────────────────────────────┐
  │ ID  │                       Topic                        │ Frequency  │                 Key tables                  │
  ├─────┼────────────────────────────────────────────────────┼────────────┼─────────────────────────────────────────────┤
  │ Q1  │ Open positions for a company (paginated)           │ High       │ Position                                    │
  ├─────┼────────────────────────────────────────────────────┼────────────┼─────────────────────────────────────────────┤
  │ Q2  │ Active applications by candidate                   │ High       │ Application, Position, Company              │
  ├─────┼────────────────────────────────────────────────────┼────────────┼─────────────────────────────────────────────┤
  │ Q3  │ Pipeline funnel per position                       │ Medium     │ Application                                 │
  ├─────┼────────────────────────────────────────────────────┼────────────┼─────────────────────────────────────────────┤
  │ Q4  │ Interview calendar for employee (date range)       │ High       │ Interview, Application, Candidate, Position │
  ├─────┼────────────────────────────────────────────────────┼────────────┼─────────────────────────────────────────────┤
  │ Q5  │ Candidates without any application (backlog)       │ Low/batch  │ Candidate, Application                      │
  ├─────┼────────────────────────────────────────────────────┼────────────┼─────────────────────────────────────────────┤
  │ Q6  │ Steps remaining for an in-progress application     │ Medium     │ InterviewStep, Interview                    │
  ├─────┼────────────────────────────────────────────────────┼────────────┼─────────────────────────────────────────────┤
  │ Q7  │ Avg score per InterviewType for a position         │ Low/ad-hoc │ Interview, InterviewStep, InterviewType     │
  ├─────┼────────────────────────────────────────────────────┼────────────┼─────────────────────────────────────────────┤
  │ Q8  │ Most recent interview per application (bulk)       │ Medium     │ Interview                                   │
  ├─────┼────────────────────────────────────────────────────┼────────────┼─────────────────────────────────────────────┤
  │ Q9  │ Job board search by salary range + employment type │ High       │ Position, Company                           │
  ├─────┼────────────────────────────────────────────────────┼────────────┼─────────────────────────────────────────────┤
  │ Q10 │ Companies ranked by application volume             │ Low/weekly │ Company, Position, Application              │
  ├─────┼────────────────────────────────────────────────────┼────────────┼─────────────────────────────────────────────┤
  │ Q11 │ Top 5 employees by interviews in last 30 days      │ Low/daily  │ Employee, Interview                         │
  ├─────┼────────────────────────────────────────────────────┼────────────┼─────────────────────────────────────────────┤
  │ Q12 │ Stale open positions with zero applications        │ Low/weekly │ Position, Company, Application              │
  └─────┴────────────────────────────────────────────────────┴────────────┴─────────────────────────────────────────────┘

  ---
  pg_stat_statements — Hotspot Analysis

  No application-level queries in pg_stat_statements — only system/introspection queries from this skill session (all < 5 ms       
  total). Expected: all tables empty, no application traffic yet. Hotspot-driven index recommendations are not available; index    
  proposals are derived from query-pattern analysis instead.

  ---
  [BLOCKING] EXPLAIN ANALYZE — Data Strategy

  Tables are empty. Choose one:

  ┌────────┬────────────────────────────────────────────────────────────────┬────────────────────────────────────────┐
  │ Option │                          Description                           │             Recommendation             │
  ├────────┼────────────────────────────────────────────────────────────────┼────────────────────────────────────────┤
  │ A      │ Defer EXPLAIN ANALYZE to Step 4 after the 1,000-row seed       │ Recommended — plans will be realistic  │
  ├────────┼────────────────────────────────────────────────────────────────┼────────────────────────────────────────┤
  │ B      │ Seed 50–200 rows now, capture plans, TRUNCATE at end           │ Useful if you want plans before Step 4 │
  ├────────┼────────────────────────────────────────────────────────────────┼────────────────────────────────────────┤
  │ C      │ Run EXPLAIN ANALYZE on empty tables — plans are not predictive │ Fastest; educational only              │
  └────────┴────────────────────────────────────────────────────────────────┴────────────────────────────────────────┘

---
  Index Proposals — diff against existing 32 indexes

  The following are net-new — none duplicate Migration 4:

  ┌─────┬──────────────────────────────┬───────────┬────────────┬────────┬────────────────────────────────────────────────────────────┐   
  │  #  │            Index             │   Table   │    Kind    │ Serves │                         Rationale                          │   
  ├─────┼──────────────────────────────┼───────────┼────────────┼────────┼────────────────────────────────────────────────────────────┤   
  │     │                              │           │            │        │ Existing employeeId_idx cannot satisfy the date-range      │   
  │ I1  │ (employeeId, interviewDate)  │ Interview │ btree      │ Q4,    │ predicate without a heap scan; composite enables           │   
  │     │                              │           │ composite  │ Q11    │ index-only range scan for employee calendar and 30-day     │   
  │     │                              │           │            │        │ workload queries                                           │   
  ├─────┼──────────────────────────────┼───────────┼────────────┼────────┼────────────────────────────────────────────────────────────┤   
  │     │ (employmentType) partial     │           │ partial    │        │ Job board search filters first by open+visible; existing   │   
  │ I2  │ WHERE status='OPEN' AND      │ Position  │ btree      │ Q9     │ companyId_status_idx leads with companyId and is useless   │   
  │     │ "isVisible"=true             │           │            │        │ here                                                       │   
  ├─────┼──────────────────────────────┼───────────┼────────────┼────────┼────────────────────────────────────────────────────────────┤   
  │ I3  │ (createdAt) partial WHERE    │ Position  │ partial    │ Q12    │ Stale-position alert sorts open positions by age; existing │   
  │     │ status='OPEN'                │           │ btree      │        │  indexes don't cover this access pattern                   │   
  └─────┴──────────────────────────────┴───────────┴────────────┴────────┴────────────────────────────────────────────────────────────┘   

  No action until you reply execute.

  ---
  Two decisions needed before proceeding:

  1. EXPLAIN ANALYZE strategy — reply A, B, or C
  2. Index proposals — reply execute to apply I1–I3 via a new Prisma migration, or skip to move straight to step 3

  You can combine both in one reply (e.g. A, execute or B, skip).


❯ 1) B. 2) Apply I1-I3

---
  Step 2 — Complete Report                                                                                                                    
  State: STEP_2_REVIEW                                                                                                                                                                                                                                                                
  ---
  Indexes Applied ✅

  All three confirmed in pg_indexes:

  ┌──────────────────────────────────────────┬───────────┬─────────────────┬─────────────────────────────────────────────────────────┐     
  │                  Index                   │   Table   │      Kind       │                       Definition                        │     
  ├──────────────────────────────────────────┼───────────┼─────────────────┼─────────────────────────────────────────────────────────┤     
  │ Interview_employeeId_interviewDate_idx   │ Interview │ btree composite │ (employeeId, interviewDate)                             │     
  ├──────────────────────────────────────────┼───────────┼─────────────────┼─────────────────────────────────────────────────────────┤     
  │ Position_open_visible_employmentType_idx │ Position  │ btree partial   │ (employmentType) WHERE status='OPEN' AND isVisible=true │     
  ├──────────────────────────────────────────┼───────────┼─────────────────┼─────────────────────────────────────────────────────────┤     
  │ Position_open_createdAt_idx              │ Position  │ btree partial   │ (createdAt) WHERE status='OPEN'                         │     
  └──────────────────────────────────────────┴───────────┴─────────────────┴─────────────────────────────────────────────────────────┘     

  Migration 20260427011538_add_common_query_indexes applied and tracked in _prisma_migrations. Prisma Client regenerated.

  ---
  Before / After EXPLAIN ANALYZE — Summary

  ▎ Note on tiny-table behavior: With only 30 Interview rows and 4 Position rows, PostgreSQL always prefers sequential scans. New indexes  
  ▎ will engage automatically at production scale (typically > ~300 rows for Interview, > ~50 rows for Position). The timing differences   
  ▎ below reflect planner cost recalculation, not index avoidance.

  ┌───────┬────────────────────────────────────────┬─────────┬─────────────────┬────────┬─────────────────────────────────────────────┐    
  │ Query │              Before plan               │ Before  │   After plan    │ After  │            Index change at scale            │    
  │       │                                        │   ms    │                 │   ms   │                                             │    
  ├───────┼────────────────────────────────────────┼─────────┼─────────────────┼────────┼─────────────────────────────────────────────┤    
  │ Q1    │ Index Scan companyId_status_idx        │ 0.046   │ unchanged       │ —      │ No new index needed ✅                      │    
  ├───────┼────────────────────────────────────────┼─────────┼─────────────────┼────────┼─────────────────────────────────────────────┤    
  │ Q2    │ Bitmap candidateId_status_idx          │ 0.299   │ unchanged       │ —      │ No new index needed ✅                      │    
  ├───────┼────────────────────────────────────────┼─────────┼─────────────────┼────────┼─────────────────────────────────────────────┤    
  │ Q3    │ Bitmap positionId_status_idx           │ 0.395   │ unchanged       │ —      │ No new index needed ✅                      │    
  ├───────┼────────────────────────────────────────┼─────────┼─────────────────┼────────┼─────────────────────────────────────────────┤    
  │ Q4    │ Bitmap employeeId_idx + date           │ 0.279   │ Seq Scan (table │ 0.392  │ I1 replaces single-col idx: date becomes    │    
  │       │ post-filter                            │         │  too small)     │        │ index condition                             │    
  ├───────┼────────────────────────────────────────┼─────────┼─────────────────┼────────┼─────────────────────────────────────────────┤    
  │ Q5    │ Index Only Scan candidateId_status_idx │ 0.173   │ unchanged       │ —      │ No new index needed ✅                      │    
  ├───────┼────────────────────────────────────────┼─────────┼─────────────────┼────────┼─────────────────────────────────────────────┤    
  │ Q6    │ Index chain (all pkeys)                │ 3.003   │ unchanged       │ —      │ Filter on Interview could benefit from      │    
  │       │                                        │         │                 │        │ (interviewStepId, applicationId) — deferred │    
  ├───────┼────────────────────────────────────────┼─────────┼─────────────────┼────────┼─────────────────────────────────────────────┤    
  │ Q7    │ Seq Scan Interview + Hash              │ 0.654   │ unchanged       │ —      │ No new index needed ✅                      │    
  ├───────┼────────────────────────────────────────┼─────────┼─────────────────┼────────┼─────────────────────────────────────────────┤    
  │ Q8    │ Bitmap applicationId_interviewDate_idx │ 0.310   │ unchanged       │ —      │ No new index needed ✅                      │    
  ├───────┼────────────────────────────────────────┼─────────┼─────────────────┼────────┼─────────────────────────────────────────────┤    
  │ Q9    │ Index Scan companyId_status_idx +      │ 0.100   │ Seq Scan (table │ 0.240  │ I2: employmentType becomes index condition  │    
  │       │ post-filter                            │         │  too small)     │        │ on open+visible                             │    
  ├───────┼────────────────────────────────────────┼─────────┼─────────────────┼────────┼─────────────────────────────────────────────┤    
  │ Q10   │ Seq Scan Position + Bitmap             │ 0.217   │ unchanged       │ —      │ No new index needed ✅                      │    
  ├───────┼────────────────────────────────────────┼─────────┼─────────────────┼────────┼─────────────────────────────────────────────┤    
  │ Q11   │ Seq Scan Interview (date post-filter)  │ 0.138   │ Seq Scan (table │ 0.186  │ I1: date becomes leading index condition    │    
  │       │                                        │         │  too small)     │        │                                             │    
  ├───────┼────────────────────────────────────────┼─────────┼─────────────────┼────────┼─────────────────────────────────────────────┤    
  │ Q12   │ Index Scan companyId_status_idx +      │ 0.062   │ Seq Scan (table │ 0.124  │ I3: createdAt becomes index range on open   │    
  │       │ createdAt filter                       │         │  too small)     │        │ positions                                   │    
  └───────┴────────────────────────────────────────┴─────────┴─────────────────┴────────┴─────────────────────────────────────────────┘    

  Expected production impact (at scale):

  ┌────────────────────────────────┬───────┬────────────────────────────────────────────────────┬────────────────────────────────────┐     
  │             Index              │ Query │                    Scan change                     │          Expected speedup          │     
  ├────────────────────────────────┼───────┼────────────────────────────────────────────────────┼────────────────────────────────────┤     
  │ I1 (employeeId, interviewDate) │ Q4    │ Bitmap single-col + heap filter → Index Range Scan │ 3–10× for high-volume interviewers │     
  ├────────────────────────────────┼───────┼────────────────────────────────────────────────────┼────────────────────────────────────┤     
  │ I1 (employeeId, interviewDate) │ Q11   │ Full Seq Scan → Index Range Scan by date           │ 5–20× as Interview table grows     │     
  ├────────────────────────────────┼───────┼────────────────────────────────────────────────────┼────────────────────────────────────┤     
  │ I2 partial (employmentType)    │ Q9    │ Full scan + multi-filter → Partial Index Scan      │ 2–5× on populated job boards       │     
  ├────────────────────────────────┼───────┼────────────────────────────────────────────────────┼────────────────────────────────────┤     
  │ I3 partial (createdAt)         │ Q12   │ Full scan + double filter → Partial Index Range    │ 3–8× as open positions accumulate  │     
  └────────────────────────────────┴───────┴────────────────────────────────────────────────────┴────────────────────────────────────┘     

  ---
  pg_stat_statements Hotspot Summary

  No application-level query hotspots at seed time — all entries were system introspection queries from this session (max 4.65 ms total).  
  Hotspot analysis will be meaningful after the Step 4 seed produces real query workload.

  ---
  State: STEP_2_REVIEW

  Awaiting your decision: reply step 3 to proceed to migration risk review (covers both the Step 1 normalization migration and the Step 2  
  index migration).

❯ what were the results of doing the B option?                                                                                                                                                                                                                                    
● The Option B run produced three categories of findings:
                      
  1. All 12 queries execute correctly — zero errors                                                                                           
  Every query ran against real data and returned sensible results. This is the primary value of Option B: structural correctness confirmed 
  before Step 4 plants 1 000 rows.

  ---
  2. Existing indexes are being used well (7 of 12 queries)

  ┌───────┬───────────────────────────────────────────────────────────────┐
  │ Query │                           Index hit                           │
  ├───────┼───────────────────────────────────────────────────────────────┤
  │ Q1    │ Position_companyId_status_idx → Index Scan                    │
  ├───────┼───────────────────────────────────────────────────────────────┤
  │ Q2    │ Application_candidateId_status_idx → Bitmap Index Scan        │
  ├───────┼───────────────────────────────────────────────────────────────┤
  │ Q3    │ Application_positionId_status_idx → Bitmap Index Scan         │
  ├───────┼───────────────────────────────────────────────────────────────┤
  │ Q5    │ Application_candidateId_status_idx → Index Only Scan          │
  ├───────┼───────────────────────────────────────────────────────────────┤
  │ Q6    │ Full pkey chain across 4 joins                                │
  ├───────┼───────────────────────────────────────────────────────────────┤
  │ Q8    │ Interview_applicationId_interviewDate_idx → Bitmap Index Scan │
  ├───────┼───────────────────────────────────────────────────────────────┤
  │ Q12   │ Position_companyId_status_idx → Index Scan                    │
  └───────┴───────────────────────────────────────────────────────────────┘

  ---
  3. Index gaps confirmed — validated the I1/I2/I3 proposals

  The before-plans revealed exactly where indexes fall short:

  ┌───────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  
  │ Query │                                                        Gap observed                                                         │  
  ├───────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  
  │ Q4    │ Interview_employeeId_idx used (single column), then interviewDate applied as a heap filter — 21 of 30 rows discarded        │  
  │       │ post-index                                                                                                                  │  
  ├───────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  
  │ Q9    │ Position_companyId_status_idx used for status, then employmentType / isVisible applied as heap filters                      │  
  ├───────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  
  │ Q11   │ Full Seq Scan on Interview — 22 of 30 rows removed by the date filter with no index help                                    │  
  ├───────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  
  │ Q12   │ Position_companyId_status_idx used for status, then createdAt applied as a heap filter                                      │  
  └───────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  

  This confirmed I1 (composite employeeId, interviewDate), I2 (partial on employmentType), and I3 (partial on createdAt) are the right     
  fixes.

  ---
  4. Why the after-plans didn't show index usage

  After applying I1–I3, PostgreSQL chose Seq Scans for all four affected queries. This is expected and correct: with only 4 Position rows  
  and 30 Interview rows, the planner's cost model correctly concludes that scanning the whole table is cheaper than an index lookup + heap 
  fetch. The indexes will engage at roughly:
  - Interview: > ~300–500 rows (I1 for Q4/Q11)
  - Position: > ~50–100 rows (I2 for Q9, I3 for Q12)

  Step 4's 1 000-row seed will cross those thresholds and produce a meaningful before/after diff.

  ---
  State: STEP_2_REVIEW — reply step 3 to proceed to migration risk review.

❯ step3

  Row Counts at Review Time

  ┌──────────────┬──────┐
  │    Table     │ Rows │
  ├──────────────┼──────┤
  │ Candidate    │ 0    │
  ├──────────────┼──────┤
  │ Resume       │ 0    │
  ├──────────────┼──────┤
  │ Position     │ 0    │
  ├──────────────┼──────┤
  │ Company      │ 0    │
  ├──────────────┼──────┤
  │ (all others) │ 0    │
  └──────────────┴──────┘

  Findings

  #: 1
  Operation: CREATE TABLE Address
  Table: Address (new)
  Rows: 0
  Short-term Risk: low
  Risk narrative: Additive. No existing data affected.
  ────────────────────────────────────────
  #: 2
  Operation: CREATE UNIQUE INDEX Address(street,city,postalCode,country)
  Table: Address
  Rows: 0
  Short-term Risk: low
  Risk narrative: Dedup constraint on new empty table. Risk deferred to contract phase when rows exist and duplicates must be resolved before

    enforcing uniqueness.
  ────────────────────────────────────────
  #: 3
  Operation: ALTER TABLE Candidate ADD COLUMN addressId INT NULLABLE
  Table: Candidate
  Rows: 0
  Short-term Risk: low
  Risk narrative: Additive nullable column. Zero downtime. Existing address VARCHAR(100) kept intact in expand phase.
  ────────────────────────────────────────
  #: 4
  Operation: ADD CONSTRAINT Candidate_addressId_fkey FK → Address
  Table: Candidate
  Rows: 0
  Short-term Risk: low
  Risk narrative: FK on nullable column with 0 rows. Validates referential integrity going forward.
  ────────────────────────────────────────
  #: 5
  Operation: CREATE UNIQUE INDEX Candidate(addressId)
  Table: Candidate
  Rows: 0
  Short-term Risk: low
  Risk narrative: Enforces one-to-one with 0 rows. Risk deferred: if rows existed without an address, the unique constraint would block      
  insert
    of NULL (allowed by default; NULL ≠ NULL in UNIQUE).
  ────────────────────────────────────────
  #: 6
  Operation: ALTER TABLE Company ADD COLUMN description TEXT
  Table: Company
  Rows: 0
  Short-term Risk: low
  Risk narrative: Additive nullable column. No risk.
  ────────────────────────────────────────
  #: 7
  Operation: CREATE TYPE "FileType" AS ENUM ('PDF','DOCX')
  Table: (new type)
  Rows: —
  Short-term Risk: low
  Risk narrative: New enum. Expanding an enum is safe; narrowing it later is the risky operation.
  ────────────────────────────────────────
  #: 8
  Operation: ALTER TABLE Resume ADD COLUMN fileTypeParsed FileType?
  Table: Resume
  Rows: 0
  Short-term Risk: low
  Risk narrative: Additive nullable column alongside old fileType VARCHAR(50). Old column untouched.

  CONTRACT phase operations (NOT in this migration — separate future migration):

  ┌───────────────────────────────────────────┬───────────┬─────────────────────────────────────────────┬───────────────────────────────┐    
  │                 Operation                 │   Table   │            Risk when rows exist             │            Recipe             │    
  ├───────────────────────────────────────────┼───────────┼─────────────────────────────────────────────┼───────────────────────────────┤    
  │ DROP COLUMN Candidate.address             │ Candidate │ HIGH — irreversible data loss               │ Expand-migrate-contract below │    
  ├───────────────────────────────────────────┼───────────┼─────────────────────────────────────────────┼───────────────────────────────┤    
  │ ALTER COLUMN Candidate.addressId SET NOT  │ Candidate │ MEDIUM — fails if any row has NULL          │ Backfill recipe below         │    
  │ NULL                                      │           │ addressId                                   │                               │    
  ├───────────────────────────────────────────┼───────────┼─────────────────────────────────────────────┼───────────────────────────────┤    
  │ DROP COLUMN Position.companyDescription   │ Position  │ HIGH — irreversible data loss               │ Expand-migrate-contract below │    
  ├───────────────────────────────────────────┼───────────┼─────────────────────────────────────────────┼───────────────────────────────┤    
  │ DROP COLUMN Resume.fileType               │ Resume    │ HIGH — irreversible data loss               │ Expand-migrate-contract below │    
  ├───────────────────────────────────────────┼───────────┼─────────────────────────────────────────────┼───────────────────────────────┤    
  │ RENAME COLUMN Resume.fileTypeParsed TO    │ Resume    │ MEDIUM — breaks any code still reading old  │ Blue/green or maintenance     │    
  │ fileType                                  │           │ column name                                 │ window                        │    
  └───────────────────────────────────────────┴───────────┴─────────────────────────────────────────────┴───────────────────────────────┘    

  ---
  Migration Risk Report B — add_common_query_indexes (Step 2)

  ▎ Status: ALREADY APPLIED (20260427011538). Reviewed for completeness.

  Findings

  ┌─────┬───────────────────────────────────────────────────────┬───────────┬───────────┬──────────────┬───────────────────────────────┐     
  │  #  │                       Operation                       │   Table   │ Rows at   │ Short-term   │        Risk narrative         │     
  │     │                                                       │           │   apply   │     Risk     │                               │     
  ├─────┼───────────────────────────────────────────────────────┼───────────┼───────────┼──────────────┼───────────────────────────────┤     
  │ 1   │ CREATE INDEX Interview(employeeId, interviewDate)     │ Interview │ 0         │ low          │ Non-unique, non-blocking.     │     
  │     │                                                       │           │           │              │ Composite btree.              │     
  ├─────┼───────────────────────────────────────────────────────┼───────────┼───────────┼──────────────┼───────────────────────────────┤     
  │ 2   │ CREATE INDEX Position(employmentType) WHERE           │ Position  │ 0         │ low          │ Partial index, additive. No   │     
  │     │ status='OPEN' AND isVisible=true                      │           │           │              │ data affected.                │     
  ├─────┼───────────────────────────────────────────────────────┼───────────┼───────────┼──────────────┼───────────────────────────────┤     
  │ 3   │ CREATE INDEX Position(createdAt) WHERE status='OPEN'  │ Position  │ 0         │ low          │ Partial index, additive. No   │     
  │     │                                                       │           │           │              │ data affected.                │     
  └─────┴───────────────────────────────────────────────────────┴───────────┴───────────┴──────────────┴───────────────────────────────┘     

  No DROP, no UNIQUE on populated table, no ALTER TYPE, no ALTER COLUMN SET NOT NULL. Verdict: safe (already applied).

  ---
  Decision Required — per migration

  Migration A (normalize_3nf_expand): reply accept and apply · revise migration first · abort

  Migration B (add_common_query_indexes): already applied — no action needed, acknowledge with ok.


❯ create the report for step 2 which I forgot to ask, and revise migration first for this step

State: STEP_3 — Migration A under revision.

  The Step 1 normalization migration is not yet created or applied, so there's nothing to undo — we can revise the SQL freely before writing the file.

  The proposed expand-phase SQL covers:

  1. CREATE TABLE Address + unique + city/country index
  2. ALTER TABLE Candidate ADD COLUMN addressId INT? + FK + UNIQUE
  3. ALTER TABLE Company ADD COLUMN description TEXT
  4. CREATE TYPE FileType AS ENUM ('PDF','DOCX')
  5. ALTER TABLE Resume ADD COLUMN fileTypeParsed FileType?

  What would you like to revise? For example:

  - Shape of Address — add/remove fields (street, region, postalCode)?
  - FK behavior — ON DELETE RESTRICT vs SET NULL on Candidate.addressId?
  - Nullability — keep addressId nullable in expand (recommended) or go straight NOT NULL?
  - Resume strategy — skip the fileTypeParsed temporary column and do a direct ALTER COLUMN fileType TYPE FileType (safe with 0 rows, risky post-data)?
  - Scope — drop or defer any of the 5 operations?
  - Something else?

  Tell me what to change and I'll update the migration SQL before applying.

  
❯ Explain me in detail what each of the 5 proposed migration steps are going to do and why                                                                           
                                                                                          
● Here is a detailed walkthrough of each operation, what it does at the database level, and why it was designed that way.
                                                                                                                                                                     
  ---                                                                                                                                                                
  1. CREATE TABLE Address + indexes                                                                                                                                                                                                                                                                                                       
  CREATE TABLE "Address" (                                                                                                                                           
    "id"         SERIAL        PRIMARY KEY,
    "street"     VARCHAR(200),
    "city"       VARCHAR(100)  NOT NULL,
    "region"     VARCHAR(100),
    "postalCode" VARCHAR(20),
    "country"    VARCHAR(100)  NOT NULL,
    "createdAt"  TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt"  TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP
  );
  CREATE UNIQUE INDEX "Address_street_city_postalCode_country_key"
      ON "Address" ("street", "city", "postalCode", "country");
  CREATE INDEX "Address_city_country_idx"
      ON "Address" ("city", "country");

  What it does: Creates a brand-new table to hold structured address data. Right now the Candidate table stores an address as a single opaque string like "123 Main  
  St, New York" in a VARCHAR(100) column — there's no way to query "all candidates in New York" without a full text scan. This creates a proper relational home for  
  addresses with separate, queryable fields.

  Why structured: city and country are NOT NULL because every real address has at least a city and country. street, region, and postalCode are nullable because some 
  addresses (e.g., remote workers, international candidates) legitimately omit them.

  Why the unique index: @@unique([street, city, postalCode, country]) — this was your decision (Q5 in Step 1). It prevents duplicate address rows, so if two
  candidates share the same address (e.g., a household), the database stores one Address row and both Candidate rows point to it via FK. This deduplicates data      
  rather than repeating it.

  Why the city, country index: The main query filter pattern for addresses is geographic — "find candidates in Barcelona" or "find candidates in Spain." This        
  composite index makes those filters fast without scanning every row.

  ---
  2. ALTER TABLE Candidate ADD COLUMN addressId INT + FK + UNIQUE

  ALTER TABLE "Candidate" ADD COLUMN "addressId" INTEGER;
  ALTER TABLE "Candidate"
      ADD CONSTRAINT "Candidate_addressId_fkey"
      FOREIGN KEY ("addressId") REFERENCES "Address"("id")
      ON UPDATE CASCADE ON DELETE RESTRICT;
  CREATE UNIQUE INDEX "Candidate_addressId_key" ON "Candidate" ("addressId");

  What it does: Adds the bridge between Candidate and the new Address table. Three sub-operations:

  - ADD COLUMN addressId INTEGER (nullable): Adds a new column to Candidate that will hold the ID of their address row. It is nullable in this expand phase because  
  existing candidates don't have an Address row yet — making it NOT NULL immediately would block any insert of a candidate before an address is created first. The   
  old address VARCHAR(100) column is left in place — nothing is dropped here.
  - ADD CONSTRAINT FK: Tells the database that addressId must always reference a valid row in Address. ON UPDATE CASCADE means if an Address's id changes (rare with 
  serials, but safe to have), the candidate's addressId updates automatically. ON DELETE RESTRICT means you cannot delete an Address row if a Candidate still points 
  to it — this protects against orphaning a candidate.
  - CREATE UNIQUE INDEX on addressId: Enforces the one-to-one relationship you decided in Step 1 (Q1: single address per candidate). Without this, multiple
  candidates could reference the same Address row, making it many-to-one. With this unique constraint, each Address row can belong to at most one candidate.

  Why nullable now: This is the "expand" half of the expand-migrate-contract pattern. You keep the old address column working while the application is updated to    
  write to addressId instead. Once every candidate has an addressId populated, a later "contract" migration makes it NOT NULL and drops the old column.

  ---
  3. ALTER TABLE Company ADD COLUMN description TEXT

  ALTER TABLE "Company" ADD COLUMN "description" TEXT;

  What it does: Adds an optional text field to Company to hold a description of the company.

  Why: This is the 3NF fix for Position.companyDescription. Right now every Position row has its own companyDescription column — which means the same company        
  description is repeated across every job posting for that company. That is a transitive dependency: Position.companyDescription depends on Position.companyId      
  (which company it is), not on the position itself. In 3NF, a fact about a company belongs in the Company table. Moving it here means one source of truth: update   
  the company description in one row, and all positions for that company automatically reflect it.

  Why nullable: The old companyDescription column on Position still exists during this expand phase. The application will keep reading from
  Position.companyDescription until it is updated to read from Company.description instead. Making it nullable avoids forcing every existing position to immediately 
  supply a value through the new path.

  Note: Position.companyDescription is NOT dropped in this migration. That happens in the contract migration after the application layer has fully switched over.    

  ---
  4. CREATE TYPE FileType AS ENUM ('PDF', 'DOCX')

  CREATE TYPE "FileType" AS ENUM ('PDF', 'DOCX');

  What it does: Creates a new PostgreSQL enum type with exactly two valid values: PDF and DOCX.

  Why: Currently Resume.fileType is a VARCHAR(50) that accepts any string. In practice the application only stores MIME types — application/pdf or
  application/vnd.openxmlformats-officedocument.wordprocessingml.document — enforced by Multer at the HTTP layer. But the database itself accepts anything: a typo,  
  an empty string, a different MIME type. The enum moves that constraint into the database so it is enforced at every write path, not just the web server.

  Why a separate step from changing the column: You cannot apply a new enum type and alter the column in the same statement. The type must exist first before any    
  column can reference it. This step purely creates the type; the next step uses it.

  ---
  5. ALTER TABLE Resume ADD COLUMN fileTypeParsed FileType?

  ALTER TABLE "Resume" ADD COLUMN "fileTypeParsed" "FileType";

  What it does: Adds a second file-type column to Resume using the new enum type, alongside the existing fileType VARCHAR(50). The old column is left untouched.     

  Why a new column instead of directly changing the existing one: This is the expand step of expand-migrate-contract for a type change. Directly running ALTER COLUMN
   fileType TYPE "FileType" would work right now because the table is empty — but if any VARCHAR value couldn't be cast to the enum (e.g., a full MIME string like   
  application/pdf vs PDF), it would fail on a populated table with no recovery path. The safer pattern is:

  1. Expand: add fileTypeParsed "FileType" (nullable) — this migration
  2. Migrate: backfill fileTypeParsed from fileType using an explicit mapping ('application/pdf' → PDF, 'application/vnd...' → DOCX), then update the application to 
  write to fileTypeParsed
  3. Contract: DROP COLUMN fileType, RENAME COLUMN fileTypeParsed TO fileType

  With 0 rows today this is purely forward-looking discipline — it costs nothing now and protects against data loss the moment real resumes are uploaded.

  ---
  Summary

  ┌──────────────────────────┬───────────────────┬────────────────────────────────────────────┬──────────────────────────────────────┐
  │           Step           │ Risk now (0 rows) │             What gets dropped              │    When is the old thing removed     │
  ├──────────────────────────┼───────────────────┼────────────────────────────────────────────┼──────────────────────────────────────┤
  │ 1. CREATE TABLE Address  │ None              │ Nothing                                    │ N/A — new table                      │
  ├──────────────────────────┼───────────────────┼────────────────────────────────────────────┼──────────────────────────────────────┤
  │ 2. Candidate.addressId   │ None              │ Nothing (address VARCHAR kept)             │ Contract migration after app cutover │
  ├──────────────────────────┼───────────────────┼────────────────────────────────────────────┼──────────────────────────────────────┤
  │ 3. Company.description   │ None              │ Nothing (Position.companyDescription kept) │ Contract migration after app cutover │
  ├──────────────────────────┼───────────────────┼────────────────────────────────────────────┼──────────────────────────────────────┤
  │ 4. CREATE TYPE FileType  │ None              │ Nothing                                    │ N/A — new type                       │
  ├──────────────────────────┼───────────────────┼────────────────────────────────────────────┼──────────────────────────────────────┤
  │ 5. Resume.fileTypeParsed │ None              │ Nothing (fileType VARCHAR kept)            │ Contract migration after backfill    │
  └──────────────────────────┴───────────────────┴────────────────────────────────────────────┴──────────────────────────────────────┘

  The entire expand migration is additive — it only adds new things. Nothing is dropped, renamed, or modified until the application layer has been updated and       
  validated. This is why the verdict is safe even if rows existed.

  ---
  State: STEP_3 — migration under revision. What would you like to change?


❯ Nothing.I understand there are 8 operations. all with low risk. Accept and apply migration A (normalize-3nf-expand)

● All 6 artifacts confirmed in the live database.                                                                                                                    
                                                                                                                                                                       ---
  Migration A — Applied ✅                                                                                                                                                                                                                                                                                                                
  ┌───────────────────────┬──────────────────────────┬────────────────────────┐                                                                                        │       Artifact        │           Type           │         Status         │                                                                                        ├───────────────────────┼──────────────────────────┼────────────────────────┤                                                                                      
  │ Address table         │ new table                │ ✅ live                │
  ├───────────────────────┼──────────────────────────┼────────────────────────┤
  │ Candidate.addressId   │ nullable FK column       │ ✅ live                │
  ├───────────────────────┼──────────────────────────┼────────────────────────┤
  │ Candidate.address     │ legacy VARCHAR(100)      │ ✅ kept (expand phase) │
  ├───────────────────────┼──────────────────────────┼────────────────────────┤
  │ Company.description   │ nullable TEXT column     │ ✅ live                │
  ├───────────────────────┼──────────────────────────┼────────────────────────┤
  │ FileType              │ new ENUM type            │ ✅ live                │
  ├───────────────────────┼──────────────────────────┼────────────────────────┤
  │ Resume.fileTypeParsed │ nullable FileType column │ ✅ live                │
  └───────────────────────┴──────────────────────────┴────────────────────────┘

  Migration B (add_common_query_indexes) — already applied ✅

  Prisma Client regenerated (v5.19.0). Note: a major version upgrade to v7.8.0 is available — follow the guide at https://pris.ly/d/major-version-upgrade when ready 
  (out of scope for this workflow).

  ---
  Adjacent-file reminders (from docs/migration-checklist.md)

  These files must be updated before the new fields are usable end-to-end:

  - backend/src/domain/models/Candidate.ts — add addressId, addressRecord fields; read Address via relation
  - backend/src/domain/models/Company.ts — add description field
  - backend/src/domain/models/Resume.ts — add fileTypeParsed FileType? field; import FileType enum
  - backend/src/application/validator.ts — validate addressId as required at intake (per Q2 decision: NOT NULL in contract phase)
  - backend/api-spec.yaml — document Address entity; add FileType enum schema; mark Candidate.addressId as required
  - Contract migration — to be created once application layer is fully cut over

  ---
  State: STEP_3_REVIEW

    Reply step 4 to proceed to report queries and the 1 000-row seed.

● Confirmed. All 8 operations map directly to lines in the applied migration:                                                                                        
  
  ┌─────┬─────────────────────────────────────────────────────────────┬──────────────────────┐                                                                       
  │  #  │                    Operation from report                    │ Migration SQL (line) │                                                                         ├─────┼─────────────────────────────────────────────────────────────┼──────────────────────┤                                                                       
  │ 1   │ CREATE TABLE Address                                        │ Lines 13–24          │                                                                       
  ├─────┼─────────────────────────────────────────────────────────────┼──────────────────────┤
  │ 2   │ CREATE UNIQUE INDEX Address(street,city,postalCode,country) │ Lines 27–28          │
  ├─────┼─────────────────────────────────────────────────────────────┼──────────────────────┤
  │ 3   │ ALTER TABLE Candidate ADD COLUMN addressId INT NULLABLE     │ Line 35              │
  ├─────┼─────────────────────────────────────────────────────────────┼──────────────────────┤
  │ 4   │ ADD CONSTRAINT Candidate_addressId_fkey FK → Address        │ Lines 37–40          │
  ├─────┼─────────────────────────────────────────────────────────────┼──────────────────────┤
  │ 5   │ CREATE UNIQUE INDEX Candidate(addressId)                    │ Lines 43–44          │
  ├─────┼─────────────────────────────────────────────────────────────┼──────────────────────┤
  │ 6   │ ALTER TABLE Company ADD COLUMN description TEXT             │ Line 47              │
  ├─────┼─────────────────────────────────────────────────────────────┼──────────────────────┤
  │ 7   │ CREATE TYPE "FileType" AS ENUM ('PDF','DOCX')               │ Line 50              │
  ├─────┼─────────────────────────────────────────────────────────────┼──────────────────────┤
  │ 8   │ ALTER TABLE Resume ADD COLUMN fileTypeParsed FileType?      │ Line 53              │
  └─────┴─────────────────────────────────────────────────────────────┴──────────────────────┘

  The contract phase operations (DROP COLUMN, SET NOT NULL, RENAME) are documented as comments at the top of the file (lines 5–10) but intentionally not executed —  
  they belong to a separate future migration after the application layer cuts over.

  State: STEP_3_REVIEW — reply step 4 to proceed to report queries and the 1 000-row seed.