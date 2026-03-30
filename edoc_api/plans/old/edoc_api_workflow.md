**I want you to produce a detailed implementation plan (not code yet) for the following end-to-end workflow in my Phoenix (Elixir) app (edoc_api). Please be practical and structure the plan so I can execute it in small steps.**

**WORKFLOW REQUIREMENTS:**

1) Done: Seller onboarding:
   Done: \- New Seller signs up at http://localhost:4000/signup using email + password.
   Done: \- After signup, show a page saying an email verification link will be sent.
   Done: \- Only after email verification, Seller can sign in at http://localhost:4000/signin.

2) Done: Seller setup after login:
   Done: \- After login, Seller lands on http://localhost:4000/company.
   Done: \- Seller fills company data (name, legal form, BIN/IIN, address, email, and other fields already present in existing tables).
   Done: \- On the same page, Seller enters bank accounts (one or multiple).

3) Done: Buyer management (missing today):
   Done: \- After company + bank accounts are filled, Seller must create their first Buyer (counterparty).
   Done: \- The system currently does NOT have a Buyer table; we must add it.
   Done: \- Buyer fields are similar to company fields (name, legal form, BIN/IIN, address, email, etc.).
   Done: \- After creating one Buyer, Seller can add additional Buyers from the same page.

4) Two business flows:

4.1) Partial: Flow A — Contract first:
     Done: \- Seller creates a Contract with a selected Buyer from the Buyer list.
     Done: \- Contract draft is generated from a HEEx template already present.
     Done: \- The template auto-fills Seller + Buyer fields.
     Done: \- Seller fills Contract Appendix 1 items (line items)
     Done: \- After review by Seller + Buyer (assume Buyer review is out-of-scope for now unless needed), Seller marks Contract as "issued".
     Missing: \- Later when Seller creates an Invoice and selects Buyer from a dropdown.
     Missing: \- Invoice items are pulled from Contract Appendix 1 items.
     Missing: \- Invoice PDF “Basis” prints: “Basis: Contract №… from …”.

4.2) Missing: Flow B — No contract:
     Missing: \- Seller creates an Invoice directly.
     Missing: \- Seller selects Buyer from dropdown.
     Missing: \- Seller fills invoice items manually, but still via HEEx template-driven editing (not just plain forms).
     Missing: \- PDF prints a reasonable “Basis” value for invoices "Без Договора".

PLANNING OUTPUT FORMAT (STRICT):

A) Assumptions & scope boundaries (max 10 bullets)
B) Workflow orchestration:
   - State machines/statuses (contract: draft/issued, invoice: draft/issued)
   - What gets snapshotted at issue-time and why
   - Preloads/query patterns needed for PDF correctness
C) Implementation roadmap:
   - Break into small steps in recommended order
   - For each step: goal, files/modules likely touched, acceptance criteria, and quick verification steps
D) Risks & mitigations (security, data integrity, UX pitfalls)

RULES:
\- Plan only (no code diffs).
\- Keep it grounded in Phoenix/Ecto conventions.
\- Prefer incremental delivery
\- Highlight any unknowns and propose the simplest default choices.
\- Stop after section D.
