# Admin Billing Client Page Dark-Mode Contrast

## Problem

The admin billing client detail page at `/admin/billing/clients/:id` has several dark-mode contrast failures:

- the top four summary-pane headings are too muted to read comfortably
- labels in the `Admin Actions` pane are too low-contrast
- `Invoice History` content is too dim
- `Payment History` content is too dim
- `Submitted payments` uses the same weak label pattern and should be aligned while touching the page

The issue is visual only. Behavior, wording, routing, and business logic should remain unchanged.

## Goals

- Make all affected headings, labels, and row text clearly readable in dark mode.
- Keep the fix local to `/admin/billing/clients/:id`.
- Add regression coverage so the page does not drift back to weak dark-mode classes.

## Non-Goals

- No admin billing workflow changes.
- No localization changes.
- No global dark-theme refactor.
- No styling changes to unrelated admin billing pages.

## Recommended Approach

Update the HEEx template classes in the affected sections directly rather than adding page-specific CSS overrides in the layout.

This keeps the fix explicit, local, and easy to maintain.

## Design

### 1. Summary Panes

In the top four summary cards:

- replace weak dark-mode heading text classes with higher-contrast classes
- keep the card structure and values unchanged

The affected headings are:

- `Plan`
- `Subscription`
- `Users`
- `Documents`

### 2. Admin Actions Pane

In the `Admin Actions` section:

- brighten form labels in dark mode
- ensure `select`, `input[type=date]`, and text inputs use readable dark-mode text color
- keep button colors and actions unchanged

This applies to:

- `Renewal plan`
- `Upgrade plan`
- `Schedule downgrade`
- `Grace until`
- `Suspend reason`
- the passive helper text in the `Reactivate` card

### 3. Invoice and Payment History

In `Invoice History` and `Payment History`:

- ensure section headings remain high-contrast
- ensure row content inside the history cards uses readable dark-mode text

### 4. Submitted Payments Alignment

`Submitted payments` uses the same low-contrast label treatment as the other billing sections. While touching this page, align its label contrast with the stronger dark-mode pattern so the page is visually consistent.

## Testing

Add a controller regression test for `/admin/billing/clients/:id` that:

- reproduces the current issue by checking for the weak dark-mode classes in the affected sections
- is then updated to assert the stronger dark-mode classes after the fix

Verification should include:

- focused admin billing controller tests
- full `mix test`

## Acceptance Criteria

- In dark mode, the top four summary-pane headings are clearly readable.
- In dark mode, the `Admin Actions` labels and controls are clearly readable.
- In dark mode, `Invoice History`, `Payment History`, and `Submitted payments` content is clearly readable.
- No workflow or copy changes are introduced.
- Regression tests cover the updated dark-mode classes.
