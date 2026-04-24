# `/company` Billing Button Localization Design

## Problem

The `/company` page still contains tenant-facing billing entry buttons in English:

- the subscription-card button labeled `Billing`
- the outstanding-invoice banner CTA labeled `Open billing`

This is inconsistent with the rest of the tenant workspace, which is expected to be localized in Russian and Kazakh.

## Goal

Localize both `/company` page entry points to `/company/billing` so they render consistent Russian and Kazakh labels.

## Success Criteria

- The subscription-card billing button on `/company` is localized in Russian and Kazakh.
- The outstanding-invoice banner CTA on `/company` is localized in Russian and Kazakh.
- Both `/company` links use the same wording on the same page.
- No `/company/billing` route, logic, or layout behavior changes.

## Scope

In scope:

- `lib/edoc_api_web/controllers/companies_html/edit.html.heex`
- `test/edoc_api_web/controllers/companies_controller_test.exs`
- existing gettext catalogs only if a new key becomes necessary

Out of scope:

- `/company/billing` page content
- admin billing pages
- billing logic or controller behavior
- non-billing copy on `/company`

## Recommended Approach

Reuse the existing `gettext("Billing")` key for both `/company` links.

- Replace the hardcoded `Billing` label in the subscription card with `gettext("Billing")`.
- Replace the banner CTA label `gettext("Open billing")` with `gettext("Billing")`.
- Keep both links pointing to `/company/billing`.

This is the smallest correct change and keeps the page terminology consistent without introducing duplicate translation keys.

## UX Behavior

On `/company`:

- the header-side billing button should show the localized equivalent of `Billing`
- the outstanding-invoice banner CTA should show the same localized label
- both links should still navigate to `/company/billing`

## Architecture

This is a template-only localization change.

- No controller changes are required.
- No billing domain changes are required.
- Existing `Billing` translation entries in Russian and Kazakh should be reused.

## Testing Strategy

Update `/company` page tests to prove:

- Russian locale renders the billing button label in Russian
- Kazakh locale renders the billing button label in Kazakh
- the outstanding-invoice banner CTA uses the same localized label when outstanding invoices exist

Assertions should target stable localized substrings and the `/company/billing` href.

## Risks

- Existing tests may currently assert the older `Open billing` text and will need to be updated.
- The shared `Billing` translation key must remain appropriate for both button placements on the page.

## Acceptance

The work is complete when:

1. `/company` shows no English billing entry labels in Russian or Kazakh locales.
2. Both `/company` billing links use the same localized wording.
3. Relevant `/company` controller tests pass.
