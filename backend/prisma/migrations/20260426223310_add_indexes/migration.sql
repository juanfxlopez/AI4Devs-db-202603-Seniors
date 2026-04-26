-- AddIndex: Education.candidateId (pre-existing FK gap)
CREATE INDEX "Education_candidateId_idx" ON "Education"("candidateId");

-- AddIndex: WorkExperience.candidateId (pre-existing FK gap)
CREATE INDEX "WorkExperience_candidateId_idx" ON "WorkExperience"("candidateId");

-- AddIndex: Resume.candidateId (pre-existing FK gap)
CREATE INDEX "Resume_candidateId_idx" ON "Resume"("candidateId");

-- AddIndex: Employee.companyId (FK)
CREATE INDEX "Employee_companyId_idx" ON "Employee"("companyId");

-- AddUniqueIndex: Employee(email, companyId) — email unique within a company
CREATE UNIQUE INDEX "Employee_email_companyId_key" ON "Employee"("email", "companyId");

-- AddIndex: InterviewStep.interviewTypeId (FK)
CREATE INDEX "InterviewStep_interviewTypeId_idx" ON "InterviewStep"("interviewTypeId");

-- AddUniqueIndex: InterviewStep(interviewFlowId, orderIndex) — enforce ordered steps per flow
CREATE UNIQUE INDEX "InterviewStep_interviewFlowId_orderIndex_key" ON "InterviewStep"("interviewFlowId", "orderIndex");

-- AddIndex: Position.companyId (FK)
CREATE INDEX "Position_companyId_idx" ON "Position"("companyId");

-- AddIndex: Position(companyId, status) — recruiter board hot path
CREATE INDEX "Position_companyId_status_idx" ON "Position"("companyId", "status");

-- AddIndex: Application.positionId (FK)
CREATE INDEX "Application_positionId_idx" ON "Application"("positionId");

-- AddIndex: Application.candidateId (FK)
CREATE INDEX "Application_candidateId_idx" ON "Application"("candidateId");

-- AddIndex: Application(positionId, status) — hot recruiter board
CREATE INDEX "Application_positionId_status_idx" ON "Application"("positionId", "status");

-- AddIndex: Application(candidateId, status) — candidate dashboard
CREATE INDEX "Application_candidateId_status_idx" ON "Application"("candidateId", "status");

-- AddIndex: Interview.applicationId (FK)
CREATE INDEX "Interview_applicationId_idx" ON "Interview"("applicationId");

-- AddIndex: Interview.interviewStepId (FK)
CREATE INDEX "Interview_interviewStepId_idx" ON "Interview"("interviewStepId");

-- AddIndex: Interview.employeeId (FK)
CREATE INDEX "Interview_employeeId_idx" ON "Interview"("employeeId");

-- AddIndex: Interview(applicationId, interviewDate) — pipeline calendar view
CREATE INDEX "Interview_applicationId_interviewDate_idx" ON "Interview"("applicationId", "interviewDate");
