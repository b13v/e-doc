# /company Billing Button Wording

## Summary

Refine the two `/company` billing-related buttons so they use context-specific wording instead of the same generic billing label.

## Problem

The `/company` page currently uses the same wording for two different billing entry points:

- the top alert call to action for unpaid invoices
- the billing button in the subscription header

These actions serve different user intents:

- one is an immediate payment action
- the other is a navigation button to review subscription details

Using the same wording weakens clarity.

## Goals

- Make the top alert CTA read as an action to pay.
- Make the subscription-header button read as a navigation action to view subscription details.
- Provide the same behavior in Russian and Kazakh.

## Non-Goals

- No route changes.
- No billing logic changes.
- No admin billing wording changes.
- No changes to other pages.

## Proposed Approach

Keep both links pointing to `/company/billing`, but replace the shared generic label with two new localized labels:

- top alert CTA: `Pay`
- subscription-header button: `Subscription details`

## UI Rules

### Top Alert CTA

- Russian: `Оплатить`
- Kazakh: localized equivalent for payment action

### Subscription Header Button

- Russian: `Детали подписки`
- Kazakh: localized equivalent for subscription details

## Testing

Update `/company` controller rendering coverage so it asserts:

- Russian page renders `Оплатить` and `Детали подписки`
- Kazakh page renders the two new localized labels
- the old shared generic label is not used for these two buttons

## Risks

- Minimal risk. This is a wording-only refactor with localized string additions.

## Mitigation

- Keep the change limited to the `/company` page template and gettext catalog entries.
