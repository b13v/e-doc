# Edocly Workspace Redesign Design

## Goal

Refine the signed-in Edocly workspace so it feels calm, trustworthy, and premium without changing routes or core workflows. The first pass should improve the shared shell and daily overview screens, especially invoices and buyers.

## Product Direction

- Workspace priority: signed-in product first
- Visual direction: Ledger Calm
- Tone: premium but restrained
- Initial scope: daily overview pages
- Change tolerance: moderate layout changes, same routes and workflows

This redesign should move the product away from generic Tailwind admin patterns and toward a document-first workspace with stronger hierarchy and less visual noise.

## Design Principles

### 1. Calm ledger, not dashboard

The product should feel like a steady document workspace, not a busy operations console. The interface should prefer whitespace, alignment, and typography over heavy cards, color blocks, and decorative chrome.

### 2. Brand through restraint

Brand presence should come from consistency, not loud decoration. Edocly should feel premium through a cohesive shell, deliberate navigation, controlled use of blue, and cleaner surface rhythm.

### 3. One dominant working surface per page

Each overview page should have:

- one primary working area
- one supporting context area
- one clear primary action

Pages should not feel like stacked unrelated widgets.

### 4. Fewer visible decisions at once

Secondary actions should recede until needed. Inline links, repeated shadows, and competing controls should be reduced so scanning becomes easier.

## Visual System

### Color and surfaces

- Base background: soft off-white or warm gray instead of flat cold gray
- Main surface: white
- Secondary surface: very light stone or blue-tinted neutral
- Primary action: restrained Edocly blue
- Dividers: soft gray lines instead of strong borders
- Status colors: keep semantic colors, but avoid making them dominate the page

The result should feel more editorial and premium than the current default utility styling.

### Typography

- Page titles should be more prominent and cleaner
- Supporting copy should be quieter and shorter
- Table headers should be readable but less shouty
- Metadata should sit in muted text instead of competing with primary content

Typography should carry more of the hierarchy so the layout can rely less on boxed containers.

### Components and chrome

- No card wrapper by default
- Keep cards only where the card itself defines a bounded interaction
- Use subtle section separation with spacing and dividers
- Keep buttons visually consistent across header actions, row actions, and empty states
- Use stronger active states in navigation and quieter inactive states

## Shared Shell

### Header and navigation

The shared signed-in shell should be refactored from a flat row of equally weighted links into a clearer workspace header.

Required changes:

- strengthen active navigation state
- reduce visual weight of inactive links
- compress the locale switcher
- move user email and logout into a more compact account area
- keep the Edocly brand visible, but not oversized

The shell should read as a stable product frame before the user engages with any page content.

### Responsive shell rules

The shell behavior must be explicit so the redesign does not become desktop-only.

- Desktop: brand at left, primary nav in the center/right flow, account cluster at the far right
- Tablet: nav spacing compresses before typography does
- Mobile: nav collapses into a compact menu trigger that opens a vertical disclosure panel; account and locale controls move into that opened panel
- Active section must remain visible in all breakpoints
- On mobile, the collapsed nav trigger should include the current section label when `current_section` is present
- When `current_section` is absent on untouched signed-in pages, the trigger should use a generic localized `Menu` label
- Locale switcher and account actions must remain reachable without hover

Hover-only interaction is not acceptable for navigation-critical actions.

### Page header pattern

Overview pages should share a common page-header pattern:

- title
- one-line explanatory support text
- primary action on the right
- optional supporting context region below or beside the header

This pattern should be reusable across invoices, buyers, and later pages.

### Reusable units and ownership

The redesign should introduce a small set of reusable presentation units in `lib/edoc_api_web/components/core_components.ex`.

Required units:

- `workspace_page_header`
  - responsibility: shared header structure for overview pages
  - inputs: title, support copy, primary action slot, optional secondary content slot
  - consumers: invoices index, buyers index, later overview pages
- `workspace_support_panel`
  - responsibility: quiet contextual region beside or below a primary working surface
  - inputs: heading, optional subtitle, list/body slot
  - consumers: invoices index, buyers index
- `workspace_empty_state`
  - responsibility: cleaner empty-state presentation with one primary action
  - inputs: title, support text, action label, action href
  - consumers: invoices index, buyers index
- `workspace_row_actions`
  - responsibility: consistent row-action presentation across overview tables
  - inputs: always-visible primary action descriptor, list of secondary action descriptors, responsive mode
  - phase-1 scope: support only the action transports already needed by invoices and buyers overview pages
  - action descriptor shape:
    - `label`
    - `transport` (`link`, `form`, or `htmx_delete`)
    - `method` (`get`, `post`, or `delete`)
    - target field (`href`, `action`, or `hx_delete`)
    - optional `_method` override for form-based non-GET/POST actions
    - optional `confirm_text`
    - optional visibility already resolved by the page before passing the descriptor
    - `htmx_delete` additionally requires:
      - `row_dom_id`
      - fixed component contract: target `#row_dom_id`, swap `outerHTML`
      - fixed success behavior for this phase: preserve the current invoice-delete behavior after successful delete
  - fixed behavior in this phase:
    - `link` renders a normal anchor
    - `form` renders a normal form/button pair, including optional hidden `_method`
    - `htmx_delete` renders the existing delete interaction pattern used on invoice rows with a fixed component-owned HTMX rendering contract
  - desktop behavior: primary action visible inline, secondary actions visually quieter
  - mobile/touch behavior: compact overflow/menu trigger that reveals the row actions in a touch-friendly list
  - consumers: invoices index, buyers index

These units should remain presentational only. They must not own business logic, determine visibility rules, or fetch data. Pages/controllers decide which actions exist; the component only renders the passed descriptors consistently.

### Shell interface contract

The active navigation state should be driven by an explicit `current_section` assign passed from touched controllers into the shared shell.

First-pass scope in this redesign:

- the invoices overview route in `lib/edoc_api_web/controllers/invoices_controller.ex` passes `current_section: :invoices`
- the buyers overview route in `lib/edoc_api_web/controllers/buyer_html_controller.ex` passes `current_section: :buyers`
- untouched signed-in pages may omit the assign in this phase

When `current_section` is absent, the shell should render with no active-highlight state rather than guessing.

Expected future section values after broader rollout:

- `:invoices`
- `:buyers`
- `:contracts`
- `:acts`
- `:company`

The shell should not infer active state through brittle text matching in templates.

The shell owns the localized section-label mapping for these section atoms using gettext. Controllers pass only the section atom; layouts/components resolve the human-readable label.

## Overview Page Redesign

## Invoices

### Primary goal

Make the invoices screen feel like the central daily ledger view.

### Layout

The page should use a two-part structure:

- primary area: invoice table
- secondary area: light contextual summary with exact first-pass content:
  - draft invoice count
  - issued invoice count
  - paid invoice count
  - short static note reinforcing that invoices depend on ready buyer and company data

Support-count rule for this phase:

- count only `draft`, `issued`, and `paid`
- any other statuses are excluded from the summary counts

This secondary region should stay narrow and quiet. It should support the page, not compete with the table.

No new backend data contract is required in this phase for the support panel. If only the invoice list is currently available, the page may derive counts from the already-rendered collection and show the static support note.

### Table behavior

The table should be visually calmer and easier to scan:

- stronger first column
- quieter supporting columns
- restrained hover states
- secondary row actions visually reduced until hover/focus
- status badges kept compact

The current header-to-cell structure also needs correction so the columns accurately match their data.

Final first-pass invoice table schema:

- column 1: `Number`
  - source: `invoice.number` or localized `Draft`
  - treatment: dominant row link
- column 2: `Buyer`
  - source: `invoice.buyer_name`
  - treatment: standard secondary text
- column 3: `Issue date`
  - source: `invoice.issue_date`
  - treatment: quiet date text in the app’s existing localized date format
  - fallback: localized em dash / neutral placeholder (`-`) when `issue_date` is absent
- column 4: `Total`
  - source: formatted `invoice.total`
  - treatment: right-aligned or visually emphasized numeric value
- column 5: `Status`
  - source: `invoice.status`
  - treatment: compact status badge
- column 6: `Actions`
  - desktop: `View` always visible; state-dependent secondary actions (`Paid`, `Edit`, `Delete`) visually quieter
  - mobile/touch: actions must not rely on hover; use one compact overflow/menu trigger per row that reveals the row actions in a touch-friendly list

No extra invoice columns should be added in this phase.

### Empty state

The empty state should feel like part of the same system, not a fallback afterthought. It should keep one clear next action and avoid oversized empty chrome.

### Primary action

The primary action remains `New Invoice`. No additional top-level invoice CTA should compete with it in this phase.

In this phase, `New Invoice` remains a single primary button linking to the existing invoice creation entry point. It should not become a split button or disclosure menu.

## Buyers

### Primary goal

Make buyers feel like a usable relationship ledger rather than a generic CRUD table.

### Layout

The page should mirror the invoices rhythm so the workspace feels coherent:

- strong page header
- primary table/list area
- one supporting context area instead of a detached callout block

The buyers support region should contain exact first-pass content:

- total buyer count
- short reminder that buyers are used for contracts and invoices
- one contextual link to contracts as a downstream action, but only when at least one buyer exists

This replaces the current detached callout pattern with a built-in page support surface.

### Table behavior

- keep buyer name as the dominant row content
- reduce the noise of inline actions
- keep legal form and secondary info visually subordinate
- support quick scanning across buyer identity, city, and contact information

On touch and small screens, secondary row actions must not rely on hover. The fallback can be always-visible compact actions or a simple overflow/menu pattern, but the actions must remain directly usable.

For this phase, buyers should use the same compact per-row overflow/menu trigger pattern as invoices on mobile/touch screens.

Final first-pass buyers table schema:

- column 1: `Name`
  - source: `buyer.name`
  - treatment: dominant row text
  - secondary line: `buyer.legal_form` when present, visually muted
- column 2: `BIN/IIN`
  - source: `buyer.bin_iin`
  - treatment: standard ledger-style identifier text
- column 3: `City`
  - source: `buyer.city`
  - fallback: `-`
- column 4: `Email`
  - source: `buyer.email`
  - fallback: `-`
- column 5: `Actions`
  - desktop: `View` always visible as the primary action; `Edit` and `Delete` present inline as quieter secondary actions
  - mobile/touch: one compact overflow/menu trigger per row using the shared `workspace_row_actions` pattern

No extra buyers columns should be added in this phase.

### Empty state

The empty state should feel cleaner and more intentional, with less “default illustration card” energy.

In the zero-buyers state, the page should expose only the primary `Add Buyer` action. The downstream contracts link should not appear in that state.

The existing secondary footer navigation back to company should be removed from the buyers overview in this phase so the page keeps one clear support region and one clear primary action.

### Primary action

The primary action remains `Add Buyer`. It should be the only prominent action in the page header.

### Acceptance focus for buyers

The redesigned buyers page should be considered complete for this phase when:

- the buyer name remains the strongest row element
- the support region replaces the detached blue callout
- actions are clearer but less noisy than the current inline-link row
- empty and populated states feel like the same design system

## Interaction Model

This first pass should not change routes or business logic. It should improve perception and usability through layout and interaction hierarchy only.

Expected interaction refinements:

- clearer hover and focus affordances
- better primary-vs-secondary action distinction
- improved row action discoverability without constant clutter
- consistent header actions across pages

### Shared feedback states

The visual system update must also cover shared feedback behavior on touched screens:

- flash success and error messages
- table row action feedback consistency
- empty and normal overview states on redesigned pages

This phase does not include redesigning create/edit form validation states. Feedback-state work is limited to the shared shell and the touched overview surfaces.

Ownership:

- shared flash presentation styling belongs in `lib/edoc_api_web/components/core_components.ex`
- page-specific placement remains the responsibility of each overview page template

Concrete phase-1 feedback acceptance:

- invoice row delete actions continue to present consistent confirmation and success behavior within the redesigned table
- invoice pay form actions and buyer delete form actions use the redesigned button treatment and preserve existing submission behavior
- flash success and error surfaces on invoices and buyers match the new visual system

Interaction implementation constraint for this phase:

- the mobile shell menu and overview row-action overflow may use only minimal JavaScript already shipped with the app or small inline behavior consistent with current patterns
- this phase does not introduce a new client-side framework or interaction system

Optional motion should stay minimal:

- subtle page-header entrance
- gentle hover reveal on row actions
- no ornamental animation

Motion is stretch work for this phase, not an acceptance requirement.

## Architecture And Implementation Shape

The redesign should be implemented as a shell-and-overview refactor, not a full app rewrite.

Primary files:

- `lib/edoc_api_web/components/layouts.ex`
- `lib/edoc_api_web/components/core_components.ex`
- `lib/edoc_api_web/controllers/invoices_html/index.html.heex`
- `lib/edoc_api_web/controllers/buyer_html/index.html.heex`
- `lib/edoc_api_web/controllers/invoices_controller.ex`
- `lib/edoc_api_web/controllers/buyer_html_controller.ex`

Overview invoice target in this phase:

- `lib/edoc_api_web/controllers/invoices_controller.ex`
- `lib/edoc_api_web/controllers/invoices_html/index.html.heex`

Possible supporting work:

- small reusable view helpers for page headers, support panels, or summary strips
- localized copy refinements only where needed to support the new structure

### Localization constraint

All new or revised UI copy introduced by this redesign must continue to flow through the existing gettext localization system. The redesign must not hardcode new visible English strings on localized surfaces.

## Non-Goals

This first pass should not include:

- route changes
- new business workflows
- full redesign of create/edit forms
- dashboard KPI expansion
- dramatic information architecture changes across the whole app

Those can follow after the shell and overview system is stable.

## Risks And Controls

### Risk: visual polish without enough structural change

If the work only changes colors and spacing, the app will still feel like the same generic admin interface.

Control:

- allow moderate layout changes in the shared shell and overview pages
- explicitly reduce card saturation
- establish a reusable page-header and support-region pattern

### Risk: overcorrecting into a dashboard

If too many summaries, stats, and badges are added, the product will drift away from the chosen Ledger Calm direction.

Control:

- keep secondary context narrow
- avoid stat mosaics
- let the table stay dominant

### Risk: inconsistency between redesigned and untouched pages

The first pass touches only some screens, so differences may become visible.

Control:

- start with shell patterns and reusable components first
- apply the same page-header rhythm across both invoices and buyers

## Validation

Success for this phase means:

- the signed-in shell feels noticeably more deliberate and premium
- invoices and buyers pages are easier to scan
- action hierarchy is clearer
- the app feels less like a generic Tailwind CRUD surface
- existing workflows and routes continue to work unchanged

### Acceptance checklist

- normal state: invoices and buyers pages render the new shell/header/support rhythm correctly
- empty state: invoices and buyers empty states feel visually integrated and still expose one clear next action
- responsive state: header/nav and support regions remain usable on mobile widths without hover dependence
- feedback state: flash/error surfaces on touched pages match the new visual system
- localization state: all revised visible copy remains translatable in the existing gettext flow

### Acceptance focus for invoices

The redesigned invoices page should be considered complete for this phase when:

- the table columns map correctly to number, buyer, issue date, total, status, and actions
- the support region shows the defined counts and static support note without needing new backend endpoints
- desktop and mobile row actions follow the shared `workspace_row_actions` pattern
- empty and populated states feel like the same design system

## Follow-On Work

If this phase succeeds, the next likely redesign phases are:

1. company and trust/settings flows
2. contract and invoice creation/editing flows
3. broader design-system rollout to remaining pages
