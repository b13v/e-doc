#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# create_roadmap_issues.sh
#
# What it does:
# 1) Ensures milestones exist
# 2) Ensures a few standard labels exist (status/*, priority/*, estimate/*)
# 3) Creates GitHub Issues for each CSV row via `gh issue create`
# 4) Auto-closes items with Status="Cancelled"
#
# Usage:
#   chmod +x create_roadmap_issues.sh
#   ./create_roadmap_issues.sh OWNER/REPO
#
# Example:
#   ./create_roadmap_issues.sh biba/edoc-api
#
# Requirements:
#   - gh auth login (already done)
#   - gh installed
#   - python3 installed
# ==========================================


REPO="${1:-}"
if [[ -z "${REPO}" ]]; then
  echo "ERROR: Missing repo. Usage: $0 OWNER/REPO" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh not found. Install GitHub CLI first." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found." >&2
  exit 1
fi

echo "==> Checking gh auth…"
gh auth status >/dev/null

echo "==> Using repo: ${REPO}"
OWNER="${REPO%/*}"
NAME="${REPO#*/}"

ensure_label() {
  local label="$1"
  local color="${2:-ededed}"
  local desc="${3:-}"

  if gh label list -R "$REPO" --limit 2000 | awk '{print $1}' | grep -Fxq "$label"; then
    return 0
  fi

  echo "==> Creating label: $label"
  if [[ -n "$desc" ]]; then
    gh label create "$label" -R "$REPO" --color "$color" --description "$desc" >/dev/null
  else
    gh label create "$label" -R "$REPO" --color "$color" >/dev/null
  fi
}

ensure_milestone() {
  local title="$1"

  local exists
  exists="$(
    gh api -H "Accept: application/vnd.github+json" \
      "/repos/${OWNER}/${NAME}/milestones?state=all&per_page=100" \
      --paginate \
      | python3 - "$title" <<'PY'
import sys, json
title = sys.argv[1]
data = json.load(sys.stdin)
print("1" if any(m.get("title") == title for m in data) else "0")
PY
  )"

  if [[ "$exists" == "1" ]]; then
    return 0
  fi

  echo "==> Creating milestone: $title"
  gh api -X POST -H "Accept: application/vnd.github+json" \
    "/repos/${OWNER}/${NAME}/milestones" \
    -f title="$title" >/dev/null
}

echo "==> Ensuring standard labels…"
ensure_label "status/Ready"     "2da44e" "Project status: Ready"
ensure_label "status/Backlog"   "9e6a03" "Project status: Backlog"
ensure_label "status/Blocked"   "d1242f" "Project status: Blocked"
ensure_label "status/Cancelled" "57606a" "Project status: Cancelled"

ensure_label "priority/P0" "d1242f" "Priority: P0"
ensure_label "priority/P1" "9e6a03" "Priority: P1"
ensure_label "priority/P2" "8250df" "Priority: P2"
ensure_label "priority/P3" "57606a" "Priority: P3"

ensure_label "estimate/0d" "57606a" "Estimate: 0d"
ensure_label "estimate/1d" "0e8a16" "Estimate: 1d"
ensure_label "estimate/2d" "1d76db" "Estimate: 2d"
ensure_label "estimate/3d" "5319e7" "Estimate: 3d"
ensure_label "estimate/4d" "b60205" "Estimate: 4d"
ensure_label "estimate/5d" "fbca04" "Estimate: 5d"

CSV_DATA=$(cat <<'CSV'
"Title","Status","Priority","Labels","Milestone","Assignee","Estimate","Body"
"SEC-001 Externalize hardcoded secrets and salts","Ready","P0","security,config,p0","M1 Security Baseline","unassigned","2d","Move JWT/session secrets and signing salts to runtime env configuration. AC: No hardcoded secrets in tracked configs; app fails fast when required env vars are missing. Files: config/config.exs; config/dev.exs; config/test.exs; config/runtime.exs; lib/edoc_api_web/endpoint.ex."
"SEC-002 Add filter_parameters for sensitive logs","Ready","P0","security,logging,p0","M1 Security Baseline","unassigned","1d","Add Phoenix filter_parameters for password/token/secret/csrf and similar fields. AC: Sensitive request values are redacted in logs. Files: config/config.exs."
"SEC-003 Remove inspect(reason) from client-facing errors","Ready","P0","security,api,p0","M1 Security Baseline","unassigned","2d","Replace inspect(reason) leakage with sanitized user-safe messages. AC: API responses never expose internal structs/modules. Files: lib/edoc_api_web/controllers/auth_controller.ex; lib/edoc_api_web/controllers/buyers_controller.ex; lib/edoc_api_web/error_mapper.ex."
"SEC-004 Tighten CSP and add missing security headers","Ready","P0","security,headers,p0","M1 Security Baseline","unassigned","2d","Strengthen CSP and add missing headers. AC: x-content-type-options; x-frame-options; referrer-policy; permissions-policy are present; CSP is stricter. Files: config/runtime.exs; lib/edoc_api_web/endpoint.ex."
"SEC-005 Add request body size limits","Ready","P0","security,dos,p0","M1 Security Baseline","unassigned","1d","Set parser/request body limits to reduce oversized payload abuse. AC: Oversized requests are rejected consistently. Files: lib/edoc_api_web/endpoint.ex."
"AUTH-006 Short access TTL + refresh token rotation/revocation","Ready","P0","auth,tokens,p0","M2 Auth and Session Hardening","unassigned","3d","Introduce short-lived access tokens and rotating refresh tokens with revocation. AC: Access TTL reduced; refresh tokens are single-use and revocable. Files: lib/edoc_api/auth/token.ex; lib/edoc_api/accounts.ex; lib/edoc_api/accounts/user.ex; priv/repo/migrations/*_add_refresh_tokens.exs."
"AUTH-007 Progressive lockout for failed logins","Ready","P0","auth,security,p0","M2 Auth and Session Hardening","unassigned","2d","Add progressive lockout/backoff after repeated login failures. AC: Failure thresholds enforce lock windows and block brute force. Files: lib/edoc_api/accounts.ex; priv/repo/migrations/*_add_login_attempt_fields.exs."
"AUTH-008 Prevent email enumeration in auth flows","Ready","P0","auth,privacy,p0","M2 Auth and Session Hardening","unassigned","1d","Normalize responses for signup/login/resend-verification to avoid account existence leaks. AC: Public responses do not reveal whether email exists. Files: lib/edoc_api_web/controllers/auth_controller.ex; lib/edoc_api_web/controllers/signup_controller.ex."
"AUTH-009 Renew session on login + align verified-user checks","Backlog","P1","auth,session,p1","M2 Auth and Session Hardening","unassigned","2d","Renew session on successful login and align verification checks between session and JWT plugs. AC: configure_session(renew: true); unverified users blocked consistently. Files: lib/edoc_api_web/controllers/session_controller.ex; lib/edoc_api_web/plugs/authenticate.ex; lib/edoc_api_web/plugs/authenticate_session.ex."
"AUTH-010 Ensure request_id in error and key success responses","Backlog","P1","api,observability,p1","M2 Auth and Session Hardening","unassigned","1d","Ensure request_id is consistently returned in error payloads and key success responses. AC: request tracing available end-to-end. Files: lib/edoc_api_web/error_mapper.ex; lib/edoc_api_web/controllers/*."
"RATE-011 Expand rate limiting to sensitive/costly routes","Backlog","P0","rate-limit,security,p0","M3 Abuse and PDF Hardening","unassigned","1d","Extend rate limiting to verify/resend and expensive document routes. AC: Endpoint-specific limits cover abuse-prone routes. Files: lib/edoc_api_web/router.ex."
"RATE-012 Pure OTP distributed limiter (Mnesia + ETS fallback)","Backlog","P1","rate-limit,security,otp,elixir-only,p1","M3 Abuse and PDF Hardening","unassigned","3d","Implement distributed limiter using only Elixir/Erlang tech. AC: No Redis/external dependency; ETS single-node mode; Mnesia clustered mode; standard RateLimit and Retry-After headers. Files: lib/edoc_api_web/plugs/rate_limit.ex; config/runtime.exs; config/dev.exs."
"PDF-014 Harden wkhtmltopdf execution path","Backlog","P0","pdf,security,p0","M3 Abuse and PDF Hardening","unassigned","2d","Add binary precheck, timeout, cleanup, and safe error mapping around PDF generation. AC: Missing binary/timeouts handled safely without internal leakage. Files: lib/edoc_api/pdf.ex."
"PDF-015 Add secure headers for PDF responses","Backlog","P1","pdf,headers,p1","M3 Abuse and PDF Hardening","unassigned","1d","Harden PDF responses with security and cache-control headers. AC: nosniff + private/no-store behavior for sensitive docs. Files: lib/edoc_api_web/controllers/invoice_controller.ex; lib/edoc_api_web/controllers/acts_controller.ex."
"VAL-016 Enable BIN/IIN checksum validation","Backlog","P1","validation,domain,p1","M4 Validation and Correctness","unassigned","1d","Enable and enforce BIN/IIN checksum verification. AC: Checksum-invalid values are rejected. Files: lib/edoc_api/validators/bin_iin.ex."
"VAL-017 Add checksum-aware IBAN validation","Backlog","P1","validation,payments,p1","M4 Validation and Correctness","unassigned","1d","Upgrade IBAN validator from regex-only to checksum-aware validation. AC: Invalid checksums fail validation reliably. Files: lib/edoc_api/validators/iban.ex."
"VAL-018 Add UUID param validation plug","Backlog","P1","validation,api,p1","M4 Validation and Correctness","unassigned","1d","Add route-level UUID validation for ID parameters. AC: Malformed IDs fail fast with consistent 400. Files: lib/edoc_api_web/plugs/validate_uuid.ex; lib/edoc_api_web/router.ex."
"COR-019 Make default bank account switch atomic","Backlog","P1","correctness,concurrency,p1","M4 Validation and Correctness","unassigned","2d","Fix race condition in default bank account switching. AC: No transient no-default state under concurrency. Files: lib/edoc_api/payments.ex."
"COR-020 Make contract item updates atomic with Ecto.Multi","Backlog","P1","correctness,transactions,p1","M4 Validation and Correctness","unassigned","2d","Refactor contract update flow to all-or-nothing transaction. AC: No partial data loss when insert/update fails. Files: lib/edoc_api/core.ex."
"COR-021 Replace direct delete with scoped ownership-safe delete","Backlog","P1","security,correctness,p1","M4 Validation and Correctness","unassigned","1d","Replace direct delete path with ownership-scoped delete query. AC: Unauthorized deletion blocked even under TOCTOU edge cases. Files: lib/edoc_api_web/controllers/companies_controller.ex."
"API-022 Standardize error envelope and status policy","Backlog","P1","api,consistency,p1","M5 API and Performance Foundations","unassigned","2d","Unify error payload format and status code policy across API. AC: Consistent {error,message,details,request_id} and status semantics. Files: lib/edoc_api_web/error_mapper.ex; lib/edoc_api_web/controllers/*."
"API-023 Add full pagination metadata","Backlog","P1","api,pagination,p1","M5 API and Performance Foundations","unassigned","1d","Add total_count/total_pages/has_next/has_prev metadata to collection responses. AC: Pagination contract consistent across list endpoints. Files: lib/edoc_api_web/controllers/invoice_controller.ex; lib/edoc_api_web/controllers/buyers_controller.ex; serializers."
"API-024 Add missing endpoints (invoice update, contract delete, buyer patch)","Backlog","P2","api,features,p2","M5 API and Performance Foundations","unassigned","2d","Implement key missing API capabilities with authorization and validation. AC: Endpoints added and fully tested for success/failure paths. Files: lib/edoc_api_web/router.ex; lib/edoc_api_web/controllers/invoice_controller.ex; lib/edoc_api_web/controllers/contract_controller.ex; lib/edoc_api_web/controllers/buyers_controller.ex."
"API-025 Add OpenAPI docs + version/deprecation policy","Backlog","P2","api,docs,p2","M5 API and Performance Foundations","unassigned","2d","Add machine-readable API docs and version/deprecation strategy. AC: OpenAPI output generated and policy documented. Files: API doc modules/router/docs."
"PERF-026 Add missing status/sort/composite indexes","Backlog","P1","performance,database,p1","M5 API and Performance Foundations","unassigned","1d","Add indexes for frequent filters/sorts. AC: indexes on invoices.status; contracts.status; contracts(company_id,status); invoices(user_id,inserted_at). Files: priv/repo/migrations/*_add_status_and_sort_indexes.exs."
"PERF-027 Add pagination to HTML list controllers","Backlog","P1","performance,web,p1","M5 API and Performance Foundations","unassigned","2d","Paginate HTML controllers to avoid unbounded list loads. AC: invoices/acts/buyers HTML views no longer fetch all records by default. Files: lib/edoc_api_web/controllers/invoices_controller.ex; lib/edoc_api_web/controllers/acts_controller.ex; lib/edoc_api_web/controllers/buyer_html_controller.ex."
"PERF-028 Reduce N+1 preloads and looped inserts","Backlog","P1","performance,queries,p1","M5 API and Performance Foundations","unassigned","3d","Optimize preload/query patterns and convert safe loops to bulk insert operations. AC: Reduced query count/latency without behavior changes. Files: lib/edoc_api/invoicing.ex; lib/edoc_api/acts.ex."
"CACHE-029 Add caching for reference data and frequent lookups","Backlog","P2","performance,caching,elixir-only,p2","M6 Caching Async and Test Closure","unassigned","2d","Introduce Elixir-native caching for low-churn reference data and hot lookups. AC: TTL/invalidation strategy for KBE/KNP/banks/units and company-by-user lookups. Files: mix.exs; lib/edoc_api/application.ex; lib/edoc_api/payments.ex; lib/edoc_api/companies.ex."
"ASYNC-030 Add Oban and move PDF/email off request path","Backlog","P2","infra,async,elixir-only,p2","M6 Caching Async and Test Closure","unassigned","3d","Use Oban for async PDF/email processing. AC: jobs run with retries, visibility, and failure handling outside request cycle. Files: mix.exs; config/runtime.exs; lib/edoc_api/workers/*; lib/edoc_api/pdf.ex; lib/edoc_api/documents/act_pdf.ex; lib/edoc_api/email_sender.ex."
"TEST-031 Add authentication and authorization test suites","Backlog","P0","tests,security,p0","M6 Caching Async and Test Closure","unassigned","3d","Create missing auth/authz tests for controllers/plugs/token/verification lifecycle. AC: Critical auth flows and abuse cases covered. Files: test/edoc_api_web/controllers/auth_controller_test.exs; test/edoc_api/accounts_test.exs; test/edoc_api/email_verification_test.exs; test/edoc_api_web/plugs/authenticate_test.exs."
"TEST-032 Add companies/payments/acts test suites","Backlog","P1","tests,coverage,p1","M6 Caching Async and Test Closure","unassigned","3d","Close test gaps for companies/payments/acts contexts and controllers. AC: Core business and authorization paths covered with passing tests. Files: test/edoc_api/companies_test.exs; test/edoc_api/payments_test.exs; test/edoc_api/acts_test.exs; controller tests."
"TEST-033 Enable async controller tests + coverage gates","Backlog","P1","tests,ci,p1","M6 Caching Async and Test Closure","unassigned","2d","Enable async where safe and enforce coverage thresholds in CI. AC: Faster test runtime and CI fails below critical coverage baseline. Files: controller test files; mix.exs; CI workflow."
"ARCH-034 Extract Contracts context from Core","Backlog","P2","architecture,contexts,p2","M7 Architecture and Modernization","unassigned","4d","Extract contract logic from Core into dedicated Contracts context. AC: Context ownership boundaries are cleaner with unchanged behavior. Files: lib/edoc_api/core.ex; lib/edoc_api/contracts.ex; contract controllers."
"ARCH-035 Extract invoice numbering module","Backlog","P2","architecture,invoicing,p2","M7 Architecture and Modernization","unassigned","3d","Move invoice numbering/recycling logic to a dedicated module. AC: Invoicing context reduced and numbering logic independently testable. Files: lib/edoc_api/invoicing.ex; lib/edoc_api/invoice_numbering.ex."
"ARCH-036 Slim fat HTML controllers and remove duplicates","Backlog","P2","architecture,web,p2","M7 Architecture and Modernization","unassigned","3d","Extract form prep/business orchestration from HTML controllers and remove duplicate clauses. AC: Lower controller complexity with no behavior regressions. Files: lib/edoc_api_web/controllers/invoices_controller.ex."
"OBS-037 Add audit logging and security telemetry","Backlog","P2","observability,security,p2","M7 Architecture and Modernization","unassigned","3d","Implement structured audit logs and telemetry for sensitive events. AC: Auth/document/payment events captured with request/user metadata and alertable metrics. Files: lib/edoc_api/audit_log.ex; lib/edoc_api_web/telemetry.ex; related hooks."
"DEP-038 Apply patch/minor dependency updates","Backlog","P2","dependencies,maintenance,p2","M7 Architecture and Modernization","unassigned","2d","Apply safe patch/minor upgrades identified by dependency audit. AC: Full test suite passes after lockfile update. Files: mix.exs; mix.lock."
"DEP-039 Execute major framework/language upgrade track","Blocked","P3","dependencies,upgrade,p3","M7 Architecture and Modernization","unassigned","5d","Plan and execute major Phoenix/Gettext/Telemetry/Elixir upgrades in controlled branch. AC: CI green, compatibility fixes complete, rollout/rollback notes prepared. Files: mix.exs; mix.lock; config/*."
"RATE-013 Add Redis limiter backend with ETS fallback","Cancelled","P1","rate-limit,infra,p1","M3 Abuse and PDF Hardening","unassigned","0d","Cancelled by architecture decision: no Redis or external limiter backend; project stays pure Elixir/OTP."
CSV
)

echo "==> Parsing CSV + creating milestones + issues…"

TSV_LINES="$(
  python3 - <<'PY' <<<"$CSV_DATA"
import csv, io, sys
data = sys.stdin.read()
f = io.StringIO(data)
r = csv.DictReader(f)
for row in r:
    title = (row.get("Title") or "").strip()
    status = (row.get("Status") or "").strip()
    priority = (row.get("Priority") or "").strip()
    labels = (row.get("Labels") or "").strip()
    milestone = (row.get("Milestone") or "").strip()
    assignee = (row.get("Assignee") or "").strip()
    estimate = (row.get("Estimate") or "").strip()
    body = (row.get("Body") or "").strip()
    print("\t".join([title, status, priority, labels, milestone, assignee, estimate, body]))
PY
)"

while IFS=$'\t' read -r title status priority labels milestone assignee estimate body; do
  [[ -z "$title" ]] && continue

  if [[ -n "$milestone" ]]; then
    ensure_milestone "$milestone"
  fi

  label_csv="$labels,status/${status},priority/${priority},estimate/${estimate}"
  label_csv="$(echo "$label_csv" | tr -d ' ' | sed 's/,,*/,/g; s/^,//; s/,$//')"

  full_body=$(
    cat <<EOF
**Status:** ${status}
**Priority:** ${priority}
**Estimate:** ${estimate}

${body}
EOF
  )

  echo "==> Creating issue: $title"
  issue_url="$(
    gh issue create -R "$REPO" \
      --title "$title" \
      --body "$full_body" \
      --label "$label_csv" \
      ${milestone:+--milestone "$milestone"}
  )"

  issue_number="${issue_url##*/}"

  if [[ "$status" == "Cancelled" ]]; then
    echo "==> Closing cancelled issue #$issue_number"
    gh issue close -R "$REPO" "$issue_number" >/dev/null
  fi
done <<< "$TSV_LINES"

echo "==> Done. Issues created in ${REPO}"
