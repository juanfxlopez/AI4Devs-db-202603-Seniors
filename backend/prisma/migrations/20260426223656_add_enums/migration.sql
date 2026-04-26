-- CreateEnum
CREATE TYPE "PositionStatus" AS ENUM ('DRAFT', 'OPEN', 'PAUSED', 'CLOSED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "ApplicationStatus" AS ENUM ('PENDING', 'SCREENING', 'INTERVIEW', 'OFFER', 'HIRED', 'REJECTED', 'WITHDRAWN');

-- CreateEnum
CREATE TYPE "EmployeeRole" AS ENUM ('RECRUITER', 'HIRING_MANAGER', 'INTERVIEWER', 'ADMIN');

-- CreateEnum
CREATE TYPE "InterviewResult" AS ENUM ('PENDING', 'PASS', 'FAIL', 'ON_HOLD');

-- CreateEnum
CREATE TYPE "EmploymentType" AS ENUM ('FULL_TIME', 'PART_TIME', 'CONTRACT', 'INTERNSHIP', 'TEMPORARY');

-- AlterTable: Employee.role String -> EmployeeRole
ALTER TABLE "Employee" ALTER COLUMN "role" TYPE "EmployeeRole" USING "role"::"EmployeeRole";

-- AlterTable: Position.status String -> PositionStatus
ALTER TABLE "Position" ALTER COLUMN "status" TYPE "PositionStatus" USING "status"::"PositionStatus";

-- AlterTable: Position.employmentType String? -> EmploymentType?
ALTER TABLE "Position" ALTER COLUMN "employmentType" TYPE "EmploymentType" USING "employmentType"::"EmploymentType";

-- AlterTable: Application.status String -> ApplicationStatus
ALTER TABLE "Application" ALTER COLUMN "status" TYPE "ApplicationStatus" USING "status"::"ApplicationStatus";

-- AlterTable: Interview.result String? -> InterviewResult?
ALTER TABLE "Interview" ALTER COLUMN "result" TYPE "InterviewResult" USING "result"::"InterviewResult";
