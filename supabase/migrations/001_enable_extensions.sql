-- Extensions required for La 10
CREATE EXTENSION IF NOT EXISTS "pgcrypto"     WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"    WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS moddatetime;
-- pg_cron lives in the cron schema; enable only on main / branch (not local) if needed.
CREATE EXTENSION IF NOT EXISTS pg_cron;
