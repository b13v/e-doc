# Billing Admin Operating Guide

This guide describes the day-to-day billing operations for platform admins.

## 1) Daily Checklist

1. Open `/admin/billing/clients`.
2. Review dashboard cards:
- Active clients
- Trial clients
- Overdue clients
- Suspended clients
- Monthly collected revenue
- Upcoming renewals
3. Review operational lists:
- Invoices due soon
- Unpaid invoices
- Recently reactivated clients
4. Open `/admin/billing/invoices` and process pending payment reviews.

## 2) Sending Billing Invoices

1. Open `/admin/billing/clients/:id`.
2. Create renewal or upgrade invoice from **Admin Actions**.
3. Open `/admin/billing/invoices`.
4. Attach Kaspi link and send the invoice.

Expected result:
- Billing invoice status becomes `sent`.
- Action is audit logged in `billing_audit_events`.

## 3) Confirming or Rejecting Payments

1. Open `/admin/billing/invoices`.
2. Find pending payment review.
3. Click confirm or reject.

Confirm flow:
- Payment becomes `confirmed`.
- Billing invoice becomes `paid`.
- Subscription is activated/updated for the invoice period.
- Action is audit logged with actor and timestamp.

Reject flow:
- Payment becomes `rejected`.
- Billing invoice remains unpaid.
- Action is audit logged with actor and timestamp.

## 4) Subscription Interventions

Use `/admin/billing/clients/:id` for manual interventions:
- Suspend subscription
- Reactivate subscription
- Extend grace period
- Schedule plan changes
- Update extra seats

All actions are written to billing audit events.

## 5) Incident Procedure: Overdue/Suspended Spike

1. Check `Overdue clients` and `Suspended clients` cards.
2. Sort unpaid invoices by due date and amount.
3. For high-value overdue clients, use manual outreach.
4. Confirm payments as evidence arrives.
5. Reactivate subscriptions only after payment confirmation.

## 6) Audit Queries (Reference)

Recent admin actions:

```sql
select inserted_at, action, company_id, actor_user_id, subject_type, subject_id, metadata
from billing_audit_events
where action like 'admin_%'
order by inserted_at desc
limit 100;
```

Recent subscription status transitions:

```sql
select inserted_at, company_id, subject_id as subscription_id, metadata
from billing_audit_events
where action = 'subscription_status_changed'
order by inserted_at desc
limit 100;
```
