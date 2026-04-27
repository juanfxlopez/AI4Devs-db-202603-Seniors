# Normalization Report (Step 1 output)

> Generated: 2026-04-27
> Branch: `feat/update-migrate-db-JFL`
> Skill: `db-tune-and-report` — Step 1

---

## 1. Database Singularity

| Check | Result | Verdict |
|---|---|---|
| Non-template databases | `postgres`, `LTIdb` | ✅ Acceptable |
| Schemas in `LTIdb` | `public` | ✅ Pass |

`postgres` is the PostgreSQL system/maintenance database — always present. `LTIdb` is the sole application database. Single logical schema `public`. No isolation concern.

---

## 2. Address Normalization (`Candidate.address`)

| Probe | Value |
|---|---|
| `Candidate` row count | `evidence_pending` (0 rows at audit time) |
| Distinct addresses | `evidence_pending` |
| Duplication ratio | — |

**Decision:** Extract `Candidate.address VARCHAR(100)` into a new `Address` model; replace with `Candidate.addressId Int @unique` (NOT NULL — address required at intake).

**Rationale:** Tables were empty at audit time. Proceeding on schema reasoning: `address` mixes street, city, region, postal code, and country into one opaque string, blocking city/country filtering, geocoding, and the future semantic search use case (pgvector location vectors). Splitting now costs nothing with zero rows; splitting later requires backfill.

**Cardinality:** One-to-one — single `Address` per `Candidate`.

### Migration Preview (expand → migrate → contract)

```prisma
model Address {
  id         Int        @id @default(autoincrement())
  street     String?    @db.VarChar(200)
  city       String     @db.VarChar(100)
  region     String?    @db.VarChar(100)
  postalCode String?    @db.VarChar(20)
  country    String     @db.VarChar(100)
  candidate  Candidate?
  createdAt  DateTime   @default(now()) @db.Timestamptz(6)
  updatedAt  DateTime   @updatedAt @db.Timestamptz(6)

  @@unique([street, city, postalCode, country])
  @@index([city, country])
}

model Candidate {
  id              Int              @id @default(autoincrement())
  firstName       String           @db.VarChar(100)
  lastName        String           @db.VarChar(100)
  email           String           @unique @db.VarChar(255)
  phone           String           @db.VarChar(15)
  // REMOVED: address String @db.VarChar(100)
  addressId       Int              @unique          // NOT NULL, one-to-one
  address         Address          @relation(fields: [addressId], references: [id])
  educations      Education[]
  workExperiences WorkExperience[]
  resumes         Resume[]
  applications    Application[]
}
```

**Expand-migrate-contract choreography:**
1. **Expand** — `CREATE TABLE Address`; `ALTER TABLE Candidate ADD COLUMN addressId INT NOT NULL UNIQUE`; keep old `address VARCHAR` column
2. **Migrate** — backfill (no-op with 0 rows); switch application layer to write `addressId`
3. **Contract** — `ALTER TABLE Candidate DROP COLUMN address`

---

## 3. Other Normalization Candidates

| Table | Column | n_rows | n_distinct | Flag | Recommendation |
|---|---|---|---|---|---|
| `Position` | `companyDescription` | — | — | **extract recommended** (3NF transitive dep.) | **Promoted:** move to `Company.description TEXT?`; `Position.companyId → Company.description` is a transitive FD violating 3NF |
| `Resume` | `fileType` | — | — | **evidence_pending** (code-constrained) | **Promoted:** only `application/pdf` / `.docx` allowed by Multer — convert to `FileType` enum (`PDF`, `DOCX`) |
| `Education` | `institution` | — | — | **evidence_pending** | Deferred — could repeat across candidates; extract once data confirms duplication ratio |
| `Company` | `name` | — | — | keep (no bound) | Unbounded TEXT vs no VARCHAR limit — style note; add `@db.VarChar(200)` optionally |
| `Employee` | `email` | — | — | keep (unique enforced) | Unbounded TEXT; add `@db.VarChar(255)` to align with `Candidate.email` |
| `WorkExperience` | `company` | — | — | keep (different semantics) | Free-text career history; not a reference to `Company` table |

### Promoted changes — additional model diffs

```prisma
enum FileType {
  PDF
  DOCX
}

model Company {
  id          Int        @id @default(autoincrement())
  name        String
  description String?                                // ADDED: promoted from Position.companyDescription
  employees   Employee[]
  positions   Position[]
  createdAt   DateTime   @default(now()) @db.Timestamptz(6)
  updatedAt   DateTime   @updatedAt @db.Timestamptz(6)
}

// Position: companyDescription String? field REMOVED

model Resume {
  id          Int       @id @default(autoincrement())
  filePath    String    @db.VarChar(500)
  fileType    FileType                               // was: String @db.VarChar(50)
  uploadDate  DateTime
  candidateId Int
  candidate   Candidate @relation(fields: [candidateId], references: [id])

  @@index([candidateId])
}
```

---

## 4. Missing FKs / Prisma Relations

**No missing foreign keys.** All 13 `*Id` columns verified against `pg_constraint`:

| Table | Column | FK | Ref | ON DELETE |
|---|---|---|---|---|
| `Education` | `candidateId` | ✅ | `Candidate(id)` | RESTRICT |
| `WorkExperience` | `candidateId` | ✅ | `Candidate(id)` | RESTRICT |
| `Resume` | `candidateId` | ✅ | `Candidate(id)` | RESTRICT |
| `Employee` | `companyId` | ✅ | `Company(id)` | RESTRICT |
| `InterviewStep` | `interviewFlowId` | ✅ | `InterviewFlow(id)` | CASCADE |
| `InterviewStep` | `interviewTypeId` | ✅ | `InterviewType(id)` | RESTRICT |
| `Position` | `companyId` | ✅ | `Company(id)` | RESTRICT |
| `Position` | `interviewFlowId` | ✅ | `InterviewFlow(id)` | RESTRICT |
| `Application` | `positionId` | ✅ | `Position(id)` | RESTRICT |
| `Application` | `candidateId` | ✅ | `Candidate(id)` | RESTRICT |
| `Interview` | `applicationId` | ✅ | `Application(id)` | CASCADE |
| `Interview` | `interviewStepId` | ✅ | `InterviewStep(id)` | RESTRICT |
| `Interview` | `employeeId` | ✅ | `Employee(id)` | RESTRICT |

---

## 5. Redundancy Review

- `WorkExperience.company` (free text) vs `Company` table — keep both; distinct semantics (career history vs live hiring entity).
- `Position` had 6 optional TEXT columns — `companyDescription` extracted (§3); the rest (`jobDescription`, `requirements`, `responsibilities`, `benefits`, `contactInfo`) are position-specific and retained.
- `Position.description` and `Position.jobDescription` overlap semantically — clarify in API docs which field the frontend form populates to avoid double-maintenance.

---

## 6. DDL Impact Summary (for Step 3 risk review)

| Operation | Table | Risk (0 rows at audit) |
|---|---|---|
| `CREATE TABLE Address` | new | none |
| `ALTER TABLE Candidate ADD COLUMN addressId INT NOT NULL UNIQUE` | Candidate | safe — 0 rows |
| `ALTER TABLE Candidate DROP COLUMN address` | Candidate | destructive but safe — 0 rows; irreversible post-data |
| `ALTER TABLE Company ADD COLUMN description TEXT` | Company | none |
| `ALTER TABLE Position DROP COLUMN companyDescription` | Position | destructive but safe — 0 rows |
| `CREATE TYPE "FileType" AS ENUM ('PDF', 'DOCX')` | new type | none |
| `ALTER TABLE Resume ALTER COLUMN fileType TYPE "FileType"` | Resume | safe — 0 rows; narrowing type, risky post-data |

---

## 7. Decisions Log

| # | Question | Decision |
|---|---|---|
| Q1 | Address cardinality | One-to-one: single `Address` per `Candidate` |
| Q2 | `Candidate.addressId` nullability | `NOT NULL` — address required at intake |
| Q3 | `Position.companyDescription` | Promoted to `Company.description TEXT?` |
| Q4 | `Resume.fileType` | Promoted to `FileType` enum (`PDF`, `DOCX`) |
| Q5 | `Address` dedup constraint | `@@unique([street, city, postalCode, country])` added |
