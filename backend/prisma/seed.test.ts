// backend/prisma/seed.test.ts
//
// Purpose: seed ~1000 applications across the ATS schema to validate
//          docs/common-report-queries.sql against realistic data.
//
// SAFETY:  this script TRUNCATES every ATS table. It refuses to run
//          unless ALLOW_DESTRUCTIVE_SEED=true AND DATABASE_URL references
//          a known-safe host (lti-db or localhost).
//
// NOTE:    Position.interviewFlowId is @unique — each Position owns one
//          InterviewFlow. Flows are created per-position (30 flows total).

import {
  PrismaClient,
  ApplicationStatus,
  EmployeeRole,
  EmploymentType,
  InterviewResult,
  PositionStatus,
} from '@prisma/client';
import { faker } from '@faker-js/faker';

const SAFETY_ENV = 'ALLOW_DESTRUCTIVE_SEED';
// Accept either the container name ("lti-db") or a local port-forward ("localhost").
// Production databases use cloud hostnames — never localhost or lti-db.
const ALLOWED_DB_HOSTS = ['lti-db', 'localhost'];

const prisma = new PrismaClient();
faker.seed(20260427);

// ── Guards ──────────────────────────────────────────────────────────────────

async function preflight(): Promise<void> {
  if (process.env[SAFETY_ENV] !== 'true') {
    throw new Error(
      `Refusing to run: ${SAFETY_ENV} is not "true". ` +
        `This script truncates all ATS tables. Set ${SAFETY_ENV}=true to confirm.`
    );
  }
  const url = process.env.DATABASE_URL ?? '';
  const isSafeHost = ALLOWED_DB_HOSTS.some((h) => url.includes(h));
  if (!isSafeHost) {
    throw new Error(
      `Refusing to run: DATABASE_URL must reference one of [${ALLOWED_DB_HOSTS.join(', ')}]. ` +
        `Got: ${url.replace(/:[^:@/]+@/, ':***@')}`
    );
  }
}

async function truncateAll(): Promise<void> {
  await prisma.$executeRawUnsafe(
    `TRUNCATE TABLE "Interview","Application","Resume","WorkExperience",` +
      `"Education","Candidate","Position","Employee","InterviewStep",` +
      `"InterviewType","InterviewFlow","Company" RESTART IDENTITY CASCADE`
  );
  console.log('Truncated all tables.');
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function weightedStatus(): ApplicationStatus {
  const r = faker.number.float({ min: 0, max: 1 });
  if (r < 0.45) return ApplicationStatus.PENDING;
  if (r < 0.65) return ApplicationStatus.SCREENING;
  if (r < 0.80) return ApplicationStatus.INTERVIEW;
  if (r < 0.85) return ApplicationStatus.OFFER;
  if (r < 0.90) return ApplicationStatus.HIRED;
  if (r < 0.98) return ApplicationStatus.REJECTED;
  return ApplicationStatus.WITHDRAWN;
}

function interviewRange(status: ApplicationStatus): [number, number] {
  switch (status) {
    case ApplicationStatus.PENDING:   return [0, 0];
    case ApplicationStatus.SCREENING: return [0, 1];
    case ApplicationStatus.INTERVIEW: return [1, 3];
    case ApplicationStatus.OFFER:     return [2, 3];
    case ApplicationStatus.HIRED:     return [2, 3];
    case ApplicationStatus.REJECTED:  return [0, 2];
    case ApplicationStatus.WITHDRAWN: return [0, 1];
  }
}

function finalResult(status: ApplicationStatus): InterviewResult {
  if (status === ApplicationStatus.HIRED)    return InterviewResult.PASS;
  if (status === ApplicationStatus.REJECTED) return InterviewResult.FAIL;
  return InterviewResult.PENDING;
}

const INSTITUTION_POOL = [
  'MIT', 'Stanford University', 'Harvard University',
  'University of California', 'Georgia Tech', 'Carnegie Mellon',
  'New York University', 'University of Texas', 'University of Michigan',
  'Northwestern University', 'Columbia University', 'University of Chicago',
  'Duke University', 'University of Washington', 'Purdue University',
  'Penn State', 'University of Florida', 'Ohio State University',
];

const DEGREE_POOL = [
  'BSc Computer Science', 'MSc Software Engineering', 'MBA',
  'BA Business Administration', 'BSc Mathematics', 'PhD Computer Science',
  'BSc Information Systems', 'MSc Data Science',
];

// ── Seed ─────────────────────────────────────────────────────────────────────

async function seed(): Promise<void> {
  const now = new Date();
  const ninetyDaysAgo = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000);

  // 1. Companies (8)
  console.log('Creating companies...');
  const companies = [];
  for (let ci = 0; ci < 8; ci++) {
    const c = await prisma.company.create({
      data: {
        name: faker.company.name(),
        description: faker.company.catchPhrase(),
      },
    });
    companies.push(c);
  }

  // 2. InterviewTypes (5 shared across all flows)
  console.log('Creating interview types...');
  const typeData = [
    { name: 'Phone Screen',         description: 'Initial screening call' },
    { name: 'Technical Assessment', description: 'Role-specific technical test' },
    { name: 'Behavioral Interview', description: 'Culture fit and soft skills' },
    { name: 'Case Study',           description: 'Problem-solving exercise' },
    { name: 'Final Round',          description: 'Executive/team panel interview' },
  ];
  const types = [];
  for (const t of typeData) {
    const it = await prisma.interviewType.create({ data: t });
    types.push(it);
  }

  // Step patterns applied cyclically across 30 positions
  const stepPatterns = [
    [types[0], types[1], types[2], types[4]], // Standard: screen → tech → behavioral → final
    [types[0], types[1], types[4]],           // Fast-Track: screen → tech → final
    [types[0], types[2], types[4]],           // Executive: screen → behavioral → final
  ];
  const patternNames = ['Standard', 'Fast-Track', 'Executive'];

  // 3. Positions (30) — each owns a unique InterviewFlow + InterviewSteps
  //    Position.interviewFlowId is @unique, so flows cannot be shared.
  console.log('Creating 30 positions (each with dedicated InterviewFlow + Steps)...');
  const employmentTypes = Object.values(EmploymentType);
  const positions: { id: number; companyId: number; positionIndex: number }[] = [];
  const stepsByPosition: { id: number }[][] = [];

  for (let pi = 0; pi < 30; pi++) {
    const company = companies[pi % companies.length];
    const pattern = stepPatterns[pi % stepPatterns.length];
    const pName   = patternNames[pi % patternNames.length];

    const flow = await prisma.interviewFlow.create({
      data: { description: `${pName} Flow — Position ${pi + 1}` },
    });

    const flowSteps: { id: number }[] = [];
    for (let si = 0; si < pattern.length; si++) {
      const itype = pattern[si];
      const step = await prisma.interviewStep.create({
        data: {
          interviewFlowId: flow.id,
          interviewTypeId: itype.id,
          name: `${itype.name} — Step ${si + 1}`,
          orderIndex: si + 1,
        },
      });
      flowSteps.push(step);
    }
    stepsByPosition.push(flowSteps);

    const p = await prisma.position.create({
      data: {
        companyId:        company.id,
        interviewFlowId:  flow.id,
        title:            faker.person.jobTitle(),
        description:      faker.lorem.sentence(),
        status:           pi < 24 ? PositionStatus.OPEN : (pi < 27 ? PositionStatus.PAUSED : PositionStatus.CLOSED),
        isVisible:        pi < 27,
        location:         faker.location.city(),
        jobDescription:   faker.lorem.paragraph(),
        requirements:     faker.lorem.paragraph(),
        responsibilities: faker.lorem.paragraph(),
        salaryMin:        faker.number.int({ min: 40000, max: 80000 }),
        salaryMax:        faker.number.int({ min: 80001, max: 150000 }),
        employmentType:   faker.helpers.arrayElement(employmentTypes),
        applicationDeadline: faker.date.future({ years: 1 }),
        contactInfo:      faker.internet.email(),
      },
    });
    positions.push({ id: p.id, companyId: company.id, positionIndex: pi });
  }

  // 4. Employees (~12 per company — roles biased toward INTERVIEWER)
  console.log('Creating employees...');
  const employeesByCompany: Record<number, { id: number }[]> = {};
  const rolesCycle = [
    EmployeeRole.RECRUITER, EmployeeRole.RECRUITER,
    EmployeeRole.HIRING_MANAGER,
    EmployeeRole.INTERVIEWER, EmployeeRole.INTERVIEWER,
    EmployeeRole.INTERVIEWER, EmployeeRole.INTERVIEWER,
    EmployeeRole.INTERVIEWER,
  ];
  for (let ci = 0; ci < companies.length; ci++) {
    const company = companies[ci];
    employeesByCompany[company.id] = [];
    for (let ei = 0; ei < 12; ei++) {
      const e = await prisma.employee.create({
        data: {
          companyId: company.id,
          name:      faker.person.fullName(),
          email:     `emp.${ci}.${ei}.${faker.string.alphanumeric(5)}@${faker.internet.domainName()}`,
          role:      rolesCycle[ei % rolesCycle.length],
          isActive:  ei < 11,
        },
      });
      employeesByCompany[company.id].push(e);
    }
  }

  // 5. Candidates (500) + Education (1–2 per candidate)
  console.log('Creating 500 candidates with education records...');
  const candidates: { id: number }[] = [];
  for (let i = 0; i < 500; i++) {
    const eduCount = faker.number.int({ min: 1, max: 2 });
    const educations = Array.from({ length: eduCount }, () => {
      const startDate = faker.date.past({ years: 8 });
      const endDate   = faker.date.between({ from: startDate, to: new Date() });
      return {
        institution: faker.helpers.arrayElement(INSTITUTION_POOL),
        title:       faker.helpers.arrayElement(DEGREE_POOL),
        startDate,
        endDate,
      };
    });

    const c = await prisma.candidate.create({
      data: {
        firstName: faker.person.firstName(),
        lastName:  faker.person.lastName(),
        email:     `cand.${i}.${faker.string.alphanumeric(6)}@${faker.internet.domainName()}`,
        phone:     `+1${faker.string.numeric(10)}`.slice(0, 15),
        address:   faker.location.streetAddress().slice(0, 100),
        educations: { create: educations },
      },
    });
    candidates.push(c);
  }

  // 6. Applications (1000 — weighted status distribution)
  console.log('Creating 1000 applications...');
  const applications: Array<{
    id: number;
    positionId: number;
    applicationDate: Date;
    status: ApplicationStatus;
    positionIndex: number;
    companyId: number;
  }> = [];

  for (let i = 0; i < 1000; i++) {
    const candidate = candidates[i % candidates.length];
    const posObj    = positions[faker.number.int({ min: 0, max: positions.length - 1 })];
    const status    = weightedStatus();
    const appDate   = faker.date.between({ from: ninetyDaysAgo, to: now });

    const app = await prisma.application.create({
      data: {
        positionId:      posObj.id,
        candidateId:     candidate.id,
        applicationDate: appDate,
        status,
        notes: faker.helpers.maybe(() => faker.lorem.sentence(), { probability: 0.3 }),
      },
    });

    applications.push({
      id:             app.id,
      positionId:     posObj.id,
      applicationDate: appDate,
      status,
      positionIndex:  posObj.positionIndex,
      companyId:      posObj.companyId,
    });
  }

  // 7. Interviews (0–3 per application, biased by status)
  console.log('Creating interviews...');
  let interviewCount = 0;

  for (const app of applications) {
    const [minI, maxI] = interviewRange(app.status);
    const numInterviews = faker.number.int({ min: minI, max: maxI });
    if (numInterviews === 0) continue;

    const employees = employeesByCompany[app.companyId] ?? [];
    if (employees.length === 0) continue;

    const flowSteps = stepsByPosition[app.positionIndex] ?? [];
    if (flowSteps.length === 0) continue;

    const stepsToRun = flowSteps.slice(0, Math.min(numInterviews, flowSteps.length));
    let prevDate = app.applicationDate;

    for (let s = 0; s < stepsToRun.length; s++) {
      const step   = stepsToRun[s];
      const isLast = s === stepsToRun.length - 1;

      const interviewDate = faker.date.between({ from: prevDate, to: now });
      prevDate = interviewDate;

      await prisma.interview.create({
        data: {
          applicationId:   app.id,
          interviewStepId: step.id,
          employeeId:      faker.helpers.arrayElement(employees).id,
          interviewDate,
          result: isLast ? finalResult(app.status) : InterviewResult.PASS,
          score:  faker.helpers.maybe(
            () => faker.number.int({ min: 1, max: 10 }),
            { probability: 0.85 }
          ),
          notes: faker.helpers.maybe(() => faker.lorem.sentence(), { probability: 0.4 }),
        },
      });
      interviewCount++;
    }
  }

  console.log(`Created ${interviewCount} interview records.`);
}

// ── Verify ───────────────────────────────────────────────────────────────────

async function verify(): Promise<void> {
  const [candidates, applications, interviews, education] = await prisma.$transaction([
    prisma.candidate.count(),
    prisma.application.count(),
    prisma.interview.count(),
    prisma.education.count(),
  ]);
  console.log('\nSeed complete. Row counts:');
  console.table({ candidates, applications, interviews, education });

  if (applications < 950 || applications > 1050) {
    console.warn(`WARNING: application count (${applications}) outside expected range 950–1050.`);
  }
}

// ── Entry ────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  await preflight();
  await truncateAll();
  await seed();
  await verify();
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
