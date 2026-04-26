-- EnableExtension: pgvector
-- Extension is available in pgvector/pgvector:pg18 image.
-- No vector columns are added here; those require a separate migration
-- once an embedding feature is approved.
CREATE EXTENSION IF NOT EXISTS vector;
