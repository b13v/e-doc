# Edoc SaaS PostgreSQL Tuning Runbook

Date: 2026-05-03

Scope: production and staging PostgreSQL databases for the Phoenix/Ecto edoc SaaS application.

This runbook converts the PostgreSQL performance risks from the article into operational checks for this codebase. The order matters: measure first, then tune. Do not add indexes, partition tables, or change global PostgreSQL settings without checking the current query plans and table statistics.

## Current App Baseline

- Ecto pool in production defaults to `POOL_SIZE=21` in `config/runtime.exs`.
- Oban production queues are `default: 10`, `pdf_generation: 5`, `billing: 1`, so max worker concurrency is 16.
- Core list indexes already exist for `invoices`, `acts`, and `contracts` on `(company_id, inserted_at)`.
- Billing tables exist under `plans`, `subscriptions`, `billing_invoices`, `payments`, `usage_counters`, `usage_events`, and `billing_audit_events`.
- The app uses UUID binary IDs globally. Do not refactor existing primary keys unless production write metrics prove this is the bottleneck.

## 1. Enable Query Visibility

Enable `pg_stat_statements` in PostgreSQL. This requires `shared_preload_libraries` and usually a database restart.

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Recommended PostgreSQL settings:

```ini
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = top
pg_stat_statements.max = 10000
track_io_timing = on
log_min_duration_statement = 500
log_lock_waits = on
log_temp_files = 0
```

Use this query to find the highest-impact statements:

```sql
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
```

Use this query for individually slow queries:

```sql
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
```

## 2. Check Table Bloat and Autovacuum Health

PostgreSQL MVCC leaves dead tuples after updates/deletes. Autovacuum must keep up, especially for Oban, billing, token, and document tables.

```sql
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
```

Investigate tables where `dead_pct > 10` or where `last_autovacuum` is old despite frequent writes.

Check table and index sizes:

```sql
SELECT
  relname AS table_name,
  pg_size_pretty(pg_relation_size(relid)) AS table_size,
  pg_size_pretty(pg_indexes_size(relid)) AS indexes_size,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 30;
```

Check long transactions that can block vacuum cleanup:

```sql
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
```

## 3. Tune Autovacuum on High-Churn Tables

Prefer table-level settings first. They are safer than aggressive global changes.

Candidate tables for table-level tuning:

- `oban_jobs`
- `generated_documents`
- `billing_invoices`
- `payments`
- `usage_events`
- `usage_counters`
- `billing_audit_events`
- `document_deliveries`
- `public_access_tokens`
- `refresh_tokens`
- `email_verification_tokens`
- `password_reset_tokens`

Initial safe table-level settings:

```sql
ALTER TABLE oban_jobs SET (
  autovacuum_vacuum_scale_factor = 0.01,
  autovacuum_analyze_scale_factor = 0.02
);

ALTER TABLE generated_documents SET (
  autovacuum_vacuum_scale_factor = 0.03,
  autovacuum_analyze_scale_factor = 0.03
);

ALTER TABLE billing_invoices SET (
  autovacuum_vacuum_scale_factor = 0.03,
  autovacuum_analyze_scale_factor = 0.03
);

ALTER TABLE payments SET (
  autovacuum_vacuum_scale_factor = 0.03,
  autovacuum_analyze_scale_factor = 0.03
);

ALTER TABLE usage_events SET (
  autovacuum_vacuum_scale_factor = 0.03,
  autovacuum_analyze_scale_factor = 0.03
);
```

Only apply these after confirming the tables exist in the target database:

```sql
SELECT tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'oban_jobs',
    'generated_documents',
    'billing_invoices',
    'payments',
    'usage_events'
  )
ORDER BY tablename;
```

## 4. Validate Critical Query Plans

Use this pattern before adding indexes:

```sql
EXPLAIN (ANALYZE, BUFFERS)
-- paste the exact SQL from logs or pg_stat_statements here
;
```

Prioritize these app pages and jobs:

- `/invoices`
- `/invoices/overdue`
- `/acts`
- `/contracts`
- `/buyers`
- `/company`
- `/company/billing`
- `/admin/billing/clients`
- `/admin/billing/clients/:id`
- `/admin/billing/invoices`
- PDF generation worker document fetches
- Billing lifecycle worker queries

Good signs:

- Uses the expected composite index.
- Reads few shared blocks.
- Does not sort large result sets in memory.
- Does not scan all tenant rows when filtering by `company_id`.

Bad signs:

- Sequential scan on large tenant-scoped tables.
- High `shared_blks_read`.
- High `temp_blks_written`.
- Nested-loop explosion from missing preloads or missing indexes.

## 5. Candidate Indexes to Validate, Not Blindly Apply

Only create these if `EXPLAIN (ANALYZE, BUFFERS)` or `pg_stat_statements` proves the matching query is slow.

Billing invoice lifecycle:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS billing_invoices_status_due_at_idx
ON billing_invoices (status, due_at);
```

Tenant billing page and admin client detail:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS billing_invoices_company_status_due_at_idx
ON billing_invoices (company_id, status, due_at);
```

Usage counting:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS usage_events_company_period_metric_idx
ON usage_events (company_id, period_start, period_end, metric);
```

Payment review queues:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS payments_status_inserted_at_idx
ON payments (status, inserted_at);
```

Default bank account lookup:

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS company_bank_accounts_company_default_idx
ON company_bank_accounts (company_id, is_default);
```

Check unused indexes before adding more:

```sql
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
```

## 6. Monitor Oban Table Health

Oban uses PostgreSQL as its queue. This is acceptable for this app size, but the `oban_jobs` table must stay small and vacuumed.

```sql
SELECT
  state,
  count(*) AS jobs,
  min(inserted_at) AS oldest_job,
  max(inserted_at) AS newest_job
FROM oban_jobs
GROUP BY state
ORDER BY jobs DESC;
```

Check total Oban table size:

```sql
SELECT
  pg_size_pretty(pg_relation_size('oban_jobs')) AS table_size,
  pg_size_pretty(pg_indexes_size('oban_jobs')) AS indexes_size,
  pg_size_pretty(pg_total_relation_size('oban_jobs')) AS total_size;
```

If completed/discarded jobs grow without bound, configure `Oban.Plugins.Pruner` with a shorter retention period instead of letting the table bloat.

## 7. Check Connection Pool Pressure

PostgreSQL active connections:

```sql
SELECT
  state,
  count(*) AS connections
FROM pg_stat_activity
GROUP BY state
ORDER BY connections DESC;
```

Total usage:

```sql
SELECT
  count(*) AS current_connections,
  current_setting('max_connections')::int AS max_connections,
  round(count(*)::numeric / current_setting('max_connections')::int * 100, 2) AS usage_pct
FROM pg_stat_activity;
```

Application guidance:

- Keep `POOL_SIZE` greater than Oban concurrency plus web request headroom.
- Current Oban max concurrency is 16, so `POOL_SIZE=21` leaves only 5 connections for web traffic.
- Consider `POOL_SIZE=30` to `35` if production PostgreSQL `max_connections` can support it.
- Consider PgBouncer in transaction pooling mode when web concurrency grows beyond what direct PostgreSQL connections can handle.

## 8. Future Partitioning Candidates

Do not partition core business tables yet. Partition only when table sizes and query plans prove it is needed.

Possible future candidates:

- `usage_events` by `period_start` or `inserted_at`
- `billing_audit_events` by `inserted_at`
- `document_deliveries` by `inserted_at`
- `public_access_tokens` by `expires_at`, if token volume grows

Avoid partitioning `invoices`, `acts`, and `contracts` until there is real evidence that tenant-scoped composite indexes no longer perform well.

## 9. Operational Checklist

Weekly:

- Review top 25 total-time queries from `pg_stat_statements`.
- Review top 30 dead tuple tables.
- Review `oban_jobs` count and size.
- Check long-running transactions.

Monthly:

- Review unused indexes.
- Review table/index growth.
- Run `EXPLAIN (ANALYZE, BUFFERS)` on the slowest business queries.
- Confirm billing lifecycle jobs are not leaving large draft/sent/overdue backlogs.

Before adding an index:

- Capture the slow SQL.
- Run `EXPLAIN (ANALYZE, BUFFERS)`.
- Verify the proposed index matches the filter and order.
- Create with `CONCURRENTLY` in production.
- Re-run the same plan after creation.

Before changing global PostgreSQL config:

- Record current load, connections, memory, table sizes, and slow queries.
- Apply one change at a time.
- Observe for at least one business day.
