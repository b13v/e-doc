# /company/billing Dark-Mode Contrast Follow-up

## Summary

Apply a focused dark-mode contrast follow-up on tenant `/company/billing` for the two elements that still remain visually weak after the previous pass:

- the three top summary-card headings
- the starter upgrade card ("Upgrade to Basic")

All other billing-page dark-mode treatment remains unchanged.

## Problem

The previous contrast cleanup did not make two areas strong enough in actual UI use:

- The top summary-card headings are still too muted in dark mode.
- The upgrade card still blends into the dark background, and its content does not read as clearly as it should.

The rest of the page is acceptable and should not be churned further.

## Goals

- Make the three summary-card headings clearly readable in dark mode.
- Make the upgrade card visually distinct and readable in dark mode.
- Keep the fix tightly scoped to the still-broken elements only.

## Non-Goals

- No billing logic changes.
- No localization changes.
- No changes to the remainder of the billing page unless required by these two fixes.
- No admin billing changes.

## Proposed Approach

Update the tenant billing template with stronger explicit dark-mode classes for:

1. Summary-card heading labels
2. Upgrade-card surface, border, heading, and body copy

Prefer direct HEEx class changes instead of CSS overrides so the behavior stays local and easy to audit.

## UI Rules

### Summary Cards

- Replace the current muted dark heading class with a clearly bright label color.
- Keep the existing card layout and value styling.

Recommended direction:

- `dark:text-white` for the small heading labels

### Upgrade Card

- Keep blue semantic meaning.
- Increase dark-mode surface contrast and border visibility so the card separates from the page background.
- Make heading and body text bright enough to read immediately.

Recommended direction:

- stronger border: `dark:border-sky-500`
- stronger surface: `dark:bg-sky-800/60`
- heading/body: `dark:text-white` or equivalent high-contrast light text

## Testing

Add or revise the controller rendering test for `/company/billing` so it asserts:

- summary headings render the brighter dark-mode class
- the upgrade card renders the stronger dark border/surface classes
- old weak upgrade-card dark class is absent

The test should be narrow and should target only the elements still reported as broken.

## Risks

- Over-brightening the labels could slightly reduce subtle hierarchy.

## Mitigation

- Keep the change limited to the still-reported elements.
- Leave the rest of the page untouched.
