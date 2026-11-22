\set ON_ERROR_STOP on

SELECT pg_advisory_xact_lock(814731, 1);

CREATE SCHEMA IF NOT EXISTS mechmaster_admin;
REVOKE ALL ON SCHEMA mechmaster_admin FROM PUBLIC;

CREATE TABLE IF NOT EXISTS mechmaster_admin.schema_migrations (
    version text PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT now()
);

SELECT NOT EXISTS (
    SELECT 1 FROM mechmaster_admin.schema_migrations WHERE version = '001'
) AS apply_001 \gset
\if :apply_001
    \ir migrations/001_enable_postgis.sql
    INSERT INTO mechmaster_admin.schema_migrations (version) VALUES ('001');
\endif

SELECT public.postgis_full_version();
