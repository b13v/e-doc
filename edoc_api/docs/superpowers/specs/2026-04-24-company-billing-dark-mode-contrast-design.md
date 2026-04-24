# /company/billing Dark-Mode Contrast Normalization

## Summary

Normalize dark-mode contrast on the tenant billing page so all cards, labels, helper copy, and action sections remain clearly readable. The change is page-scoped to `/company/billing` and does not alter billing logic, routing, or admin billing pages.

## Problem

The tenant billing page currently uses mixed dark-mode contrast rules:

- The three summary-card headings use weak muted text in dark mode and become hard to read.
- The starter upgrade card uses a very dark blue surface that does not separate clearly from the page background.
- Similar muted text appears elsewhere on the page, so fixing only the reported headings would leave the page visually inconsistent.

The result is a dark-mode billing page with low information hierarchy and poor legibility.

## Goals

- Make all tenant `/company/billing` cards and sections readable in dark mode.
- Keep a consistent dark-mode contrast system across the full page.
- Preserve existing semantic color meaning:
  - red for blocked and overdue states
  - amber for reminders
  - blue for starter-to-basic upgrade
- Keep the change limited to tenant billing UI and related tests.

## Non-Goals

- No billing workflow or permission changes.
- No localization changes.
- No admin billing UI changes.
- No global design-system refactor outside `/company/billing`.

## Proposed Approach

Update the tenant billing template to use a single stronger dark-mode contrast pattern across:

- summary cards
- upgrade card
- outstanding invoice list
- Kaspi payment link block
- payment instruction block
- helper labels and small metadata text
- input text and placeholders where needed

The implementation should prefer direct HEEx class normalization over page-specific CSS overrides so the page remains easy to reason about.

## UI Rules

### Summary Cards

- Replace weak dark-mode label text with a clearly readable high-contrast label color.
- Keep values in bright high-contrast text.
- Preserve existing card layout and spacing.

### Upgrade Card

- Keep the blue semantic treatment, but move to a visibly separated dark-mode surface and border.
- Ensure the heading and body copy remain readable against that surface.
- Keep the action button styling unchanged unless contrast requires a minor adjustment.

### Outstanding Invoice Blocks

- Normalize labels, metadata, and helper copy to the same stronger dark-mode text scale used above.
- Ensure nested blocks retain visible separation from the surrounding card.

### Payment Sections

- Ensure headings, explanatory copy, input text, and placeholders remain readable in dark mode.
- Preserve existing red, amber, green, and blue semantic actions.

## Testing

Add or update controller-level rendering coverage for `/company/billing` in dark mode:

- Assert the page contains the stronger dark-mode classes for summary-card headings.
- Assert the page no longer contains the weak dark-mode classes that caused the current issue.
- Assert the starter upgrade card renders with the new stronger dark-mode surface/text treatment.

The test should verify rendered HTML only; no browser test is required for this refactor.

## Risks

- Over-correcting the page into overly bright dark-mode styling could flatten hierarchy.
- Partial replacement of classes could leave the page inconsistent if some nested labels still use old muted classes.

## Mitigation

- Normalize the entire `/company/billing` template in one pass.
- Use one consistent dark-mode label/body/surface pattern instead of ad hoc per-section tweaks.
- Add regression coverage for the rendered template so future changes do not reintroduce weak classes.
