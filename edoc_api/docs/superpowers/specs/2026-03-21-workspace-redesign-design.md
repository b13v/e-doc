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

### Page header pattern

Overview pages should share a common page-header pattern:

- title
- one-line explanatory support text
- primary action on the right
- optional supporting context region below or beside the header

This pattern should be reusable across invoices, buyers, and later pages.

## Overview Page Redesign

## Invoices

### Primary goal

Make the invoices screen feel like the central daily ledger view.

### Layout

The page should use a two-part structure:

- primary area: invoice table
- secondary area: light contextual summary, such as draft count, issued count, paid count, or readiness cues

This secondary region should stay narrow and quiet. It should support the page, not compete with the table.

### Table behavior

The table should be visually calmer and easier to scan:

- stronger first column
- quieter supporting columns
- restrained hover states
- secondary row actions visually reduced until hover/focus
- status badges kept compact

The current header-to-cell structure also needs correction so the columns accurately match their data.

### Empty state

The empty state should feel like part of the same system, not a fallback afterthought. It should keep one clear next action and avoid oversized empty chrome.

## Buyers

### Primary goal

Make buyers feel like a usable relationship ledger rather than a generic CRUD table.

### Layout

The page should mirror the invoices rhythm so the workspace feels coherent:

- strong page header
- primary table/list area
- one supporting context area instead of a detached callout block

### Table behavior

- keep buyer name as the dominant row content
- reduce the noise of inline actions
- keep legal form and secondary info visually subordinate
- support quick scanning across buyer identity, city, and contact information

### Empty state

The empty state should feel cleaner and more intentional, with less “default illustration card” energy.

## Interaction Model

This first pass should not change routes or business logic. It should improve perception and usability through layout and interaction hierarchy only.

Expected interaction refinements:

- clearer hover and focus affordances
- better primary-vs-secondary action distinction
- improved row action discoverability without constant clutter
- consistent header actions across pages

Optional motion should stay minimal:

- subtle page-header entrance
- gentle hover reveal on row actions
- no ornamental animation

## Architecture And Implementation Shape

The redesign should be implemented as a shell-and-overview refactor, not a full app rewrite.

Primary files:

- `lib/edoc_api_web/components/layouts.ex`
- `lib/edoc_api_web/components/core_components.ex`
- `lib/edoc_api_web/controllers/invoices_html/index.html.heex`
- `lib/edoc_api_web/controllers/buyer_html/index.html.heex`

Possible supporting work:

- small reusable view helpers for page headers, support panels, or summary strips
- localized copy refinements only where needed to support the new structure

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

## Follow-On Work

If this phase succeeds, the next likely redesign phases are:

1. company and trust/settings flows
2. contract and invoice creation/editing flows
3. broader design-system rollout to remaining pages
