# Billing Scheduled Change Dark Contrast Design

## Problem

In dark mode, the pale-green `Scheduled plan change` cards on billing-related pages are not readable. The low-contrast text affects:

- tenant `/company/billing`
- platform admin `/admin/billing/clients/:id`
- any same-pattern scheduled-plan informational card already rendered in billing surfaces, including `/company`

The current issue is not billing logic. It is a dark-theme presentation failure.

## Goal

Make every billing-related emerald `Scheduled plan change` card clearly readable in dark mode while keeping:

- current wording
- current behavior
- current green informational meaning

## Recommended Approach

Use explicit scheduled-change hook classes plus layout-level dark-theme overrides.

This codebase already resolves several dark-mode billing/admin contrast issues through `html[data-theme="dark"]` selectors in the root layout. The scheduled-change cards should follow the same pattern instead of relying only on template-local `dark:text-*` utilities.

## Scope

Apply the fix to all billing-related scheduled-change emerald cards currently present:

1. tenant billing page `/company/billing`
2. admin billing client detail `/admin/billing/clients/:id`
3. company settings `/company` scheduled-change notice, because it is the same plan-change informational surface and should stay visually consistent

## Design

### Hook classes

Add dedicated hook classes for scheduled-change cards:

- card container
- title
- body copy
- label text
- value text

These hooks should be applied consistently across the affected templates.

### Dark-mode styling

In the root layout dark-theme CSS, add explicit overrides for the scheduled-change hooks so that:

- the emerald card background remains visibly distinct from the page background
- the border remains readable
- title text is high-contrast
- body copy is high-contrast
- labels are high-contrast
- values are high-contrast

The dark-mode fix should be centralized there rather than duplicated ad hoc in templates.

### Non-goals

This change does not:

- alter billing or subscription behavior
- change copy or localization
- refactor billing cards into new shared components
- restyle non-emerald billing surfaces unless they already use this same scheduled-change pattern

## Testing

Write failing tests first.

### Tenant billing page

Add coverage proving `/company/billing` scheduled-change markup includes the dedicated hook classes and the rendered page includes the matching dark-mode override selectors.

### Admin client billing page

Add coverage proving `/admin/billing/clients/:id` scheduled-change markup includes the dedicated hook classes and the rendered page includes the matching dark-mode override selectors.

### Company page

If the same scheduled-change card is present there, extend `/company` regression coverage so it stays aligned with the shared scheduled-change pattern.

## Acceptance Criteria

- In dark mode, all billing-related emerald `Scheduled plan change` cards have readable text.
- Tenant `/company/billing` scheduled-change card is readable.
- Admin `/admin/billing/clients/:id` scheduled-change card is readable.
- Any matching `/company` scheduled-change notice uses the same contrast pattern.
- Tests cover the shared hook-based dark-mode rendering path.
