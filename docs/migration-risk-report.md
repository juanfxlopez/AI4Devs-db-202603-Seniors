# Migration Risk Report (Step 3 output)

> Generated: 2026-04-27
> Branch: `feat/update-migrate-db-JFL`
> Skill: `db-tune-and-report` — Step 3
> Reviewed by: db-tune-and-report skill (Step 3)

---

# Migration Risk Report A — `normalize_3nf_expand`

> Migration file: `backend/prisma/migrations/20260427133809_normalize_3nf_expand/migration.sql`
> Status: **APPLIED** ✅
> Phase: EXPAND — all additive, nothing dropped.

## Row Counts at Review Time

| Table | Rows |
|---|---|
| Candidate | 0 |
| Resume | 0 |
| Position | 0 |
| Company | 0 |
| Interview | 0 |
| Application | 0 |

## Summary

**Verdict: `safe`** — all 8 operations are additive. Zero rows in all affected tables. Contract phase is documented and gated; it will ship as a separate migration after application layer cutover and backfill validation.

## Findings

| # | Operation | Table | Rows | Short-term Risk | Risk Narrative |
|---|---|---|---|---|---|
| 1 | `CREATE TABLE Address` | Address (new) | 0 | **low** | Additive. No existing data affected. |
| 2 | `CREATE UNIQUE INDEX Address(street,city,postalCode,country)` | Address | 0 | **low** | Dedup constraint on new empty table. Risk deferred to contract phase when rows exist and duplicates must be resolved before enforcing uniqueness. |
| 3 | `ALTER TABLE Candidate ADD COLUMN addressId INT NULLABLE` | Candidate | 0 | **low** | Additive nullable column. Zero downtime. Existing `address VARCHAR(100)` kept intact in expand phase. |
| 4 | `ADD CONSTRAINT Candidate_addressId_fkey FK → Address` | Candidate | 0 | **low** | FK on nullable column with 0 rows. Validates referential integrity going forward. |
| 5 | `CREATE UNIQUE INDEX Candidate(addressId)` | Candidate | 0 | **low** | Enforces one-to-one with 0 rows. Risk deferred: if rows existed without an address, the unique constraint would block insert of NULL (allowed by default; NULL ≠ NULL in UNIQUE). |
| 6 | `ALTER TABLE Company ADD COLUMN description TEXT` | Company | 0 | **low** | Additive nullable column. No risk. |
| 7 | `CREATE TYPE "FileType" AS ENUM ('PDF','DOCX')` | (new type) | — | **low** | New enum. Expanding an enum is safe; narrowing it later is the risky operation. |
| 8 | `ALTER TABLE Resume ADD COLUMN fileTypeParsed FileType?` | Resume | 0 | **low** | Additive nullable column alongside old `fileType VARCHAR(50)`. Old column untouched. |

## Migration SQL — Expand Phase (applied)

```sql
-- ── 1. Address table
CREATE TABLE "Address" (
  "id"         SERIAL        NOT NULL,
  "street"     VARCHAR(200),
  "city"       VARCHAR(100)  NOT NULL,
  "region"     VARCHAR(100),
  "postalCode" VARCHAR(20),
  "country"    VARCHAR(100)  NOT NULL,
  "createdAt"  TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"  TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "Address_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "Address_street_city_postalCode_country_key"
    ON "Address" ("street", "city", "postalCode", "country");
CREATE INDEX "Address_city_country_idx"
    ON "Address" ("city", "country");

-- ── 2. Candidate.addressId (nullable FK, one-to-one)
ALTER TABLE "Candidate" ADD COLUMN "addressId" INTEGER;
ALTER TABLE "Candidate"
    ADD CONSTRAINT "Candidate_addressId_fkey"
    FOREIGN KEY ("addressId") REFERENCES "Address"("id")
    ON UPDATE CASCADE ON DELETE RESTRICT;
CREATE UNIQUE INDEX "Candidate_addressId_key" ON "Candidate" ("addressId");

-- ── 3. Company.description (additive)
ALTER TABLE "Company" ADD COLUMN "description" TEXT;

-- ── 4. FileType enum
CREATE TYPE "FileType" AS ENUM ('PDF', 'DOCX');

-- ── 5. Resume.fileTypeParsed (expand alongside legacy fileType VARCHAR)
ALTER TABLE "Resume" ADD COLUMN "fileTypeParsed" "FileType";
```

## Expand → Migrate → Contract Recipes (future migrations)

### A. `DROP COLUMN Candidate.address` (contract phase)

```sql
-- Precondition: SELECT COUNT(*) FROM "Candidate" WHERE "addressId" IS NULL → must be 0
ALTER TABLE "Candidate" ALTER COLUMN "addressId" SET NOT NULL;
ALTER TABLE "Candidate" DROP COLUMN "address";
```

### B. `DROP COLUMN Position.companyDescription` (contract phase)

```sql
-- Backfill before drop:
UPDATE "Company" c
SET description = p."companyDescription"
FROM "Position" p
WHERE p."companyId" = c.id
  AND p."companyDescription" IS NOT NULL
  AND c.description IS NULL;

-- Then drop:
ALTER TABLE "Position" DROP COLUMN "companyDescription";
```

### C. `Resume.fileType VARCHAR → FileType ENUM` (contract phase)

```sql
-- Backfill fileTypeParsed from fileType:
UPDATE "Resume"
SET "fileTypeParsed" = CASE
  WHEN "fileType" ILIKE '%pdf%' THEN 'PDF'::"FileType"
  ELSE 'DOCX'::"FileType"
END
WHERE "fileTypeParsed" IS NULL;

-- Precondition: SELECT COUNT(*) FROM "Resume" WHERE "fileTypeParsed" IS NULL → must be 0

-- Then contract:
ALTER TABLE "Resume" DROP COLUMN "fileType";
ALTER TABLE "Resume" RENAME COLUMN "fileTypeParsed" TO "fileType";
```

## Long-term Risk & Adjacent Files

| File | Action required |
|---|---|
| `backend/src/domain/models/Candidate.ts` | Add `addressId`, `addressRecord` fields; import `Address` relation |
| `backend/src/domain/models/Company.ts` | Add `description` field |
| `backend/src/domain/models/Resume.ts` | Add `fileTypeParsed FileType?`; import `FileType` enum |
| `backend/src/application/validator.ts` | Validate `addressId` required at intake; align with contract-phase NOT NULL |
| `backend/api-spec.yaml` | Document `Address` entity; add `FileType` enum schema; mark `Candidate.addressId` |
| Contract migration | Create once app layer fully cut over (see recipes above) |

## Decision

**Accepted and applied.** Migration `20260427133809_normalize_3nf_expand` tracked in `_prisma_migrations`. Prisma Client regenerated (v5.19.0).

---

# Migration Risk Report B — `add_common_query_indexes`

> Migration file: `backend/prisma/migrations/20260427011538_add_common_query_indexes/migration.sql`
> Status: **ALREADY APPLIED** ✅ (applied during Step 2)

## Row Counts at Apply Time

| Table | Rows |
|---|---|
| Interview | 0 |
| Position | 0 |

## Summary

**Verdict: `safe`** — three CREATE INDEX statements. No DROP, no UNIQUE on populated table, no ALTER TYPE, no ALTER COLUMN SET NOT NULL.

## Findings

| # | Operation | Table | Rows at apply | Short-term Risk | Risk Narrative |
|---|---|---|---|---|---|
| 1 | `CREATE INDEX Interview(employeeId, interviewDate)` | Interview | 0 | **low** | Non-unique composite btree. Additive. No data affected. |
| 2 | `CREATE INDEX Position(employmentType) WHERE status='OPEN' AND isVisible=true` | Position | 0 | **low** | Partial index. Additive. No data affected. |
| 3 | `CREATE INDEX Position(createdAt) WHERE status='OPEN'` | Position | 0 | **low** | Partial index. Additive. No data affected. |

## Migration SQL (applied)

```sql
-- I1: Composite — serves Q4 (employee calendar) and Q11 (top interviewers)
CREATE INDEX "Interview_employeeId_interviewDate_idx"
    ON "Interview" ("employeeId", "interviewDate");

-- I2: Partial — serves Q9 (job board search by type + salary)
CREATE INDEX "Position_open_visible_employmentType_idx"
    ON "Position" ("employmentType")
    WHERE status = 'OPEN' AND "isVisible" = true;

-- I3: Partial — serves Q12 (stale open positions)
CREATE INDEX "Position_open_createdAt_idx"
    ON "Position" ("createdAt")
    WHERE status = 'OPEN';
```

## Decision

**Already applied.** No further action required.

---

## Migration History — All Applied Migrations

| # | Migration | Timestamp | Scope |
|---|---|---|---|
| 1 | `init` | 20260426182554 | Candidate, Education, WorkExperience, Resume |
| 2 | `add_ats_core_entities` | 20260426221733 | 8 new ATS tables + FKs + timestamps |
| 3 | `alter_candidate_phone_address_not_null` | 20260426222506 | Candidate.phone + Candidate.address → NOT NULL |
| 4 | `add_indexes` | 20260426223310 | 17 indexes (FK + composite + unique) |
| 5 | `add_enums` | 20260426223656 | 5 enum types, 5 columns converted |
| 6 | `enable_pgvector` | 20260426224150 | vector extension enabled |
| 7 | `add_common_query_indexes` | 20260427011538 | I1 composite + I2/I3 partial indexes |
| 8 | `normalize_3nf_expand` | 20260427133809 | Address table, Candidate.addressId, Company.description, FileType enum, Resume.fileTypeParsed |
