# Performance Audit Report

**Date:** 2026-02-19
**Project:** Edoc API (Elixir/Phoenix)

## Executive Summary

This audit identified several performance concerns including unoptimized database queries, missing database indexes, lack of caching infrastructure, and potential N+1 query patterns. The most critical issues are missing composite indexes for frequently queried column combinations and the complete absence of a caching layer.

---

## N+1 Query Analysis

### 1. Preload After Query (Multiple Queries)

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/invoicing.ex`
- **Lines 17-18:** `list_invoices_for_user/2` fetches all invoices first, then preloads associations
  ```elixir
  |> Repo.all()
  |> Repo.preload([...])
  ```
  **Impact:** 1 query for invoices + N queries for each preload association. Should use `Ecto.preload/3` with nested preload syntax.

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/buyers_controller.ex`
- **Lines 22-24:** Fetches buyers then preloads bank_accounts in a separate query
  ```elixir
  buyers = Buyers.list_buyers_for_company(company.id, limit: page_size, offset: offset)
  |> Repo.preload(bank_accounts: :bank)
  ```

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/contract_html_controller.ex`
- **Line 207:** Preload after fetching contract
  ```elixir
  contract = EdocApi.Repo.preload(contract, [:buyer, :contract_items])
  ```

### 2. Enum.each with Repo Operations

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/acts.ex`
- **Lines 108-115:** Creating act items one-by-one in a loop
  ```elixir
  Enum.each(prepared_items, fn item_attrs ->
    attrs = Map.put(item_attrs, "act_id", act.id)
    case %ActItem{} |> ActItem.changeset(attrs) |> Repo.insert() do
      {:ok, _} -> :ok
      {:error, changeset} -> Repo.rollback({:validation, %{changeset: changeset}})
    end
  end)
  ```
  **Impact:** Each item insert is a separate database query. Consider `Repo.insert_all/2` for bulk inserts.

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/invoicing.ex`
- **Lines 244-250:** Similar pattern for invoice items
- **Lines 311-317:** Same pattern in update function

### 3. Multiple Sequential Queries in Controllers

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/invoices_controller.ex`
- **Lines 51-53:** Multiple independent queries that could be parallelized or optimized:
  ```elixir
  contracts = Invoicing.list_issued_contracts_for_user(user.id)
  buyers = Buyers.list_buyers_for_company(company.id)
  bank_accounts = Payments.list_company_bank_accounts_for_user(user.id)
  kbe_codes = Payments.list_kbe_codes()
  knp_codes = Payments.list_knp_codes()
  ```

---

## Database Indexes

### Missing Indexes on Foreign Keys

1. **invoices.bank_account_id** - HAS index (added in migration 20260113134116)
2. **invoices.contract_id** - HAS index (added in migration 20260118120100)
3. **invoices.kbe_code_id** - HAS index (added in migration 20260209130000)
4. **invoices.knp_code_id** - HAS index (added in migration 20260209130000)

### Missing Composite Indexes

1. **contracts.status** - No index on status field
   - **File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/invoicing.ex:38`
   - Query: `where([c], c.company_id == ^company_id and c.status == "issued")`
   - **Recommendation:** Add composite index `(company_id, status)` or separate index on `status`

2. **invoices.user_id** - HAS index (from migration 20251227104600)

3. **invoices.status** - No index on status field
   - Multiple queries filter by status (draft, issued, paid)
   - **Recommendation:** Add index on `invoices.status`

4. **acts.status** - HAS index (from migration 20260216120000, line 37)

### Index Analysis by Table

| Table | Foreign Key | Index Status | Notes |
|-------|-------------|--------------|-------|
| invoices | user_id | HAS | From 20251227104600 |
| invoices | company_id | HAS | From 20251227104600 |
| invoices | bank_account_id | HAS | From 20260113134116 |
| invoices | contract_id | HAS | From 20260118120100 |
| invoices | kbe_code_id | HAS | From 20260209130000 |
| invoices | knp_code_id | HAS | From 20260209130000 |
| invoices | status | MISSING | Queries filter by status frequently |
| contracts | company_id | HAS | From 20260118120000 |
| contracts | buyer_id | HAS | From 20260204000003 |
| contracts | status | MISSING | Queries filter by "issued" status |
| acts | company_id | HAS | From 20260216120000 |
| acts | user_id | HAS | From 20260216120000 |
| acts | buyer_id | HAS | From 20260216120000 |
| acts | contract_id | HAS | From 20260216120000 |
| acts | status | HAS | From 20260216120000 |
| buyers | company_id | HAS | From 20260204000002 |
| company_bank_accounts | company_id | HAS | From 20260113124833 |
| company_bank_accounts | bank_id | HAS | From 20260113124833 |
| company_bank_accounts | kbe_code_id | HAS | From 20260113124833 |
| company_bank_accounts | knp_code_id | HAS | From 20260113124833 |

### Recommended Migration for Missing Indexes

```elixir
# Recommended: Add status indexes
defmodule EdocApi.Repo.Migrations.AddStatusIndexes do
  use Ecto.Migration

  def change do
    # For filtering invoices by status (draft, issued, paid)
    create(index(:invoices, [:status]))

    # For filtering contracts by status (draft, issued)
    create(index(:contracts, [:status]))

    # Composite index for common query pattern
    create(index(:contracts, [:company_id, :status]))
  end
end
```

---

## Query Patterns

### 1. Select All Without Limit

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/invoices_controller.ex`
- **Line 22:** `list_invoices_for_user` called without pagination in HTML controller
  ```elixir
  invoices = Invoicing.list_invoices_for_user(user.id)
  ```
  **Impact:** Fetches ALL invoices for a user without pagination. Could cause memory issues as data grows.

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/acts_controller.ex`
- **Line 16:** Same issue - no pagination
  ```elixir
  acts = Acts.list_acts_for_user(user.id)
  ```

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api_web/controllers/buyer_html_controller.ex`
- Buyers listing also lacks pagination in HTML views

### 2. Delete All Without Batching

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/invoicing.ex`
- **Lines 306-308:** Deleting invoice items
  ```elixir
  InvoiceItem
  |> where([ii], ii.invoice_id == ^invoice_id)
  |> Repo.delete_all()
  ```
  **Note:** `delete_all` is efficient but doesn't trigger callbacks. Consider if this is intentional.

### 3. Order By Without Index

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/invoicing.ex`
- **Line 100:** `order_by([i], desc: i.inserted_at)` without index on inserted_at for user queries
  - Consider composite index: `(user_id, inserted_at DESC)`

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/buyers.ex`
- **Line 49:** `order_by([b], asc: b.name)` - no index on name
  - Could be slow with many buyers

### 4. Inefficient ilike Queries

**File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/buyers.ex`
- **Lines 220-226:** Search with leading wildcard
  ```elixir
  |> where([b], ilike(b.name, ^query) or ilike(b.bin_iin, ^query))
  ```
  **Impact:** Leading wildcard (`%query%`) prevents index usage. Consider:
  - PostgreSQL full-text search
  - Trigram indexes (`pg_trgm` extension)
  - External search service (Elasticsearch, Meilisearch)

---

## Caching Strategy

### Current State: NO CACHING

**Finding:** The project has no caching library installed.

**Checked:**
- No `Cachex` dependency in mix.exs
- No `con_cache` dependency in mix.exs
- No `:cache` module or usage patterns in code

### Recommendations for Caching

1. **Install Cachex or con_cache**
   ```elixir
   # mix.exs
   {:cachex, "~> 3.6"}
   ```

2. **Cache Frequently Accessed Data:**
   - **KBE codes** (`Payments.list_kbe_codes/0`) - rarely changes
   - **KNP codes** (`Payments.list_knp_codes/0`) - rarely changes
   - **Banks** (`Payments.list_banks/0`) - rarely changes
   - **Units of measurements** (`Core.list_units_of_measurements/0`) - rarely changes

3. **Cache User Company**
   - `Companies.get_company_by_user_id/1` is called frequently

4. **Cache Invalidation Strategy:**
   - Time-based (TTL) for reference data
   - Event-based for user/company data
   - Consider `:ets` for simple read-heavy caches

---

## Background Jobs

### Current State: NO BACKGROUND JOB PROCESSOR

**Finding:** The project does not use Oban or any other background job library.

**Checked:**
- No `Oban` dependency in mix.exs
- No job worker modules in the codebase

### Impact

1. **PDF Generation** is synchronous
   - **File:** `/home/biba/codes/e-doc/edoc_api/lib/edoc_api/documents/act_pdf.ex`
   - Blocks HTTP request while generating PDF

2. **Email Sending** (if implemented) would be synchronous

### Recommendations

1. **Install Oban for background jobs:**
   ```elixir
   # mix.exs
   {:oban, "~> 2.17"}
   ```

2. **Move to Background Jobs:**
   - PDF generation for invoices, contracts, acts
   - Email notifications
   - Any cleanup/maintenance tasks

---

## Critical Issues

1. **Unpaginated Lists in HTML Controllers**
   - `InvoicesController.index/2` loads all invoices
   - `ActsController.index/2` loads all acts
   - `BuyerHTMLController` loads all buyers
   - **Risk:** Memory exhaustion and slow page loads as data grows

2. **No Database Index on invoices.status**
   - Queries filtering by status (draft, issued, paid) perform full table scans

3. **No Database Index on contracts.status**
   - Query `where([c], c.company_id == ^company_id and c.status == "issued")` has no index support

4. **Missing Caching Layer**
   - Reference data (KBE/KNP codes, banks) fetched from database on every request
   - User/company lookups not cached

5. **Bulk Operations in Loops**
   - Act items and invoice items inserted one-by-one instead of bulk insert

6. **Leading Wildcard Searches**
   - Buyer search uses `ilike(b.name, ^query)` with `%query%` pattern
   - Cannot use indexes; slow with large datasets

---

## Recommendations

### Priority 1 (Immediate)

1. **Add Pagination to All List Views**
   - HTML controllers should pass `limit` and `offset` parameters
   - Add navigation controls for page browsing

2. **Add Status Indexes**
   ```elixir
   create(index(:invoices, [:status]))
   create(index(:contracts, [:status]))
   create(index(:contracts, [:company_id, :status]))
   ```

3. **Add Composite Index for User Invoices**
   ```elixir
   create(index(:invoices, [:user_id, :inserted_at]))
   ```

### Priority 2 (Short-term)

4. **Implement Reference Data Caching**
   - Cache KBE codes, KNP codes, banks with long TTL (1 hour+)
   - Cache company lookups by user_id with medium TTL (5 minutes)

5. **Convert Bulk Inserts to Use `insert_all`**
   - For invoice items and act items
   - Requires changeset validation to be done before insert

6. **Optimize Buyer Search**
   - Add trigram index for full-text search
   - Or migrate to dedicated search service

### Priority 3 (Long-term)

7. **Install Oban for Background Jobs**
   - Move PDF generation to background jobs
   - Add job queue monitoring

8. **Add Query Logging and Monitoring**
   - Use `EctoDevLoggers` in development
   - Set up telemetry for slow query detection

9. **Database Connection Pool Tuning**
   - Review pool size in `config/dev.exs` and `config/prod.exs`
   - Consider connection pool per "domain" if needed

10. **Consider Read Replicas**
    - If read load increases, direct read queries to replicas

---

## Migration Examples

### Add Missing Indexes

```elixir
# priv/repo/migrations/TIMESTAMP_add_performance_indexes.exs
defmodule EdocApi.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Status filters
    create(index(:invoices, [:status]))
    create(index(:contracts, [:status]))

    # Composite for user invoices with sort
    create(index(:invoices, [:user_id, :inserted_at]),
      name: :invoices_user_id_inserted_at_desc_index
    )

    # Contract status queries
    create(index(:contracts, [:company_id, :status]))

    # Acts queries
    create(index(:acts, [:user_id, :inserted_at]))
  end
end
```

### Add Trigram Index for Search

```elixir
# priv/repo/migrations/TIMESTAMP_add_trigram_extension.exs
defmodule EdocApi.Repo.Migrations.AddTrigramExtension do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    create(index(:buyers, [:name], using: :gin, opclass: :gin_trgm_ops))
  end

  def down do
    drop(index(:buyers, [:name]))
    execute("DROP EXTENSION IF NOT EXISTS pg_trgm")
  end
end
```

---

## Summary

| Category | Issues Found | Severity |
|----------|--------------|----------|
| N+1 Queries | 8 | Medium |
| Missing Indexes | 4 | High |
| No Pagination | 3+ | High |
| No Caching | 1 (entire layer) | Medium |
| No Background Jobs | 1 (entire layer) | Low |
| Inefficient Search | 1 | Medium |

**Total Recommendations:** 10 actionable items across 3 priority levels.
