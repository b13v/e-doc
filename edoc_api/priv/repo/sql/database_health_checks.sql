-- Edoc SaaS PostgreSQL health checks.
-- Run in staging/production with psql after enabling pg_stat_statements.

-- 1. Slowest queries by total time.
SELECT
  calls,
  round(total_exec_time::numeric, 2) AS total_ms,
  round(mean_exec_time::numeric, 2) AS mean_ms,
  rows,
  shared_blks_hit,
  shared_blks_read,
  temp_blks_read,
  temp_blks_written,
  left(regexp_replace(query, '\s+', ' ', 'g'), 240) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 25;

-- 2. Slowest repeated queries by mean time.
SELECT
  calls,
  round(mean_exec_time::numeric, 2) AS mean_ms,
  round(max_exec_time::numeric, 2) AS max_ms,
  rows,
  left(regexp_replace(query, '\s+', ' ', 'g'), 240) AS query
FROM pg_stat_statements
WHERE calls >= 5
ORDER BY mean_exec_time DESC
LIMIT 25;

-- 3. Dead tuples and autovacuum health.
SELECT
  schemaname,
  relname AS table_name,
  n_live_tup,
  n_dead_tup,
  round((n_dead_tup::numeric / greatest(n_live_tup, 1)) * 100, 2) AS dead_pct,
  last_vacuum,
  last_autovacuum,
  last_analyze,
  last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 30;

-- 4. Largest tables and indexes.
SELECT
  relname AS table_name,
  pg_size_pretty(pg_relation_size(relid)) AS table_size,
  pg_size_pretty(pg_indexes_size(relid)) AS indexes_size,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 30;

-- 5. Long transactions that can block vacuum cleanup.
SELECT
  pid,
  usename,
  state,
  now() - xact_start AS xact_age,
  now() - query_start AS query_age,
  left(query, 240) AS query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start ASC
LIMIT 20;

-- 6. Unused non-primary indexes.
SELECT
  schemaname,
  relname AS table_name,
  indexrelname AS index_name,
  idx_scan,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexrelname NOT LIKE '%pkey'
ORDER BY pg_relation_size(indexrelid) DESC;

-- 7. Oban queue table state.
SELECT
  state,
  count(*) AS jobs,
  min(inserted_at) AS oldest_job,
  max(inserted_at) AS newest_job
FROM oban_jobs
GROUP BY state
ORDER BY jobs DESC;

-- 8. Oban queue table size.
SELECT
  pg_size_pretty(pg_relation_size('oban_jobs')) AS table_size,
  pg_size_pretty(pg_indexes_size('oban_jobs')) AS indexes_size,
  pg_size_pretty(pg_total_relation_size('oban_jobs')) AS total_size;

-- 9. Connection usage by state.
SELECT
  state,
  count(*) AS connections
FROM pg_stat_activity
GROUP BY state
ORDER BY connections DESC;

-- 10. Total connection pressure.
SELECT
  count(*) AS current_connections,
  current_setting('max_connections')::int AS max_connections,
  round(count(*)::numeric / current_setting('max_connections')::int * 100, 2) AS usage_pct
FROM pg_stat_activity;
