claude mcp add --transport stdio db -- npx -y @bytebase/dbhub --dsn "postgres://dev:devpass@localhost:5439/bikerental?sslmode=disable"
claude mcp add --transport stdio db -- npx -y @bytebase/dbhub --dsn "postgres://LTIdbUser:D1ymf8wyQEGthFR1E9xhCq@localhost:5439/LTIdb?sslmode=disable"


'SELECT COUNT(*) FROM "Candidate";' | docker exec -i lti-db psql -U LTIdbUser -d LTIdb
'SELECT COUNT(*) FROM "Resume";' | docker exec -i lti-db psql -U LTIdbUser -d LTIdb
'SELECT COUNT(*) FROM "Education";' | docker exec -i lti-db psql -U LTIdbUser -d LTIdb
'SELECT COUNT(*) FROM "WorkExperience";' | docker exec -i lti-db psql -U LTIdbUser -d LTIdb
'SELECT COUNT(*) FROM "_prisma_migrations";' | docker exec -i lti-db psql -U LTIdbUser -d LTIdb

'SELECT ''Candidate'' AS table_name, COUNT(*) FROM "Candidate" UNION ALL SELECT ''Resume'', COUNT(*) FROM "Resume" UNION ALL SELECT ''Education'', COUNT(*) FROM "Education" UNION ALL SELECT ''WorkExperience'', COUNT(*) FROM "WorkExperience";' | docker exec -i lti-db psql -U LTIdbUser -d LTIdb


'\d "Candidate"' | docker exec -i lti-db psql -U LTIdbUser -d LTIdb
'\d "Resume"' | docker exec -i lti-db psql -U LTIdbUser -d LTIdb
'\d "Education"' | docker exec -i lti-db psql -U LTIdbUser -d LTIdb
'\d "WorkExperience"' | docker exec -i lti-db psql -U LTIdbUser -d LTIdb
'\d "_prisma_migrations"' | docker exec -i lti-db psql -U LTIdbUser -d LTIdb

docker exec -it lti-db psql -U LTIdbUser -d LTIdb -c "\dt"

docker exec -it ai4devs-pgv psql -U dev -d ragdemo -c "TRUNCATE TABLE faq_items RESTART IDENTITY;"
docker exec -it ai4devs-pgv psql -U dev -d ragdemo -c "SELECT COUNT(*) FROM faq_items;"
docker exec -it ai4devs-pgv psql -U dev -d ragdemo -c "SELECT id, question FROM faq_items ORDER BY id;"
docker exec -it ai4devs-pgv psql -U dev -d ragdemo -c "\d faq_items" 
