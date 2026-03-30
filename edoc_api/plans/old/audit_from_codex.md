**Next Steps**
1. Done - Fix JWT handling for browser flows and remove token from DOM.
2. Done - Require `JWT_SECRET` in prod and remove email verification token exposure/logging.
3. Done - Add login/signup rate limiting and unify API error responses.

**What Changed**
1. Removed JWT usage from HTML/HTMX flows and switched to authenticated HTML endpoints for issue/PDF actions.
2. Enforced `JWT_SECRET` in production and removed verification token exposure in UI/logging.
3. Added rate limiting for `/v1/auth/signup` and `/v1/auth/login`, and standardized auth error responses via `ErrorMapper`.
4. Self-hosted HTMX, pinned Tailwind CDN version, and tightened CSP script/style sources.
5. Added a reusable flash error summary component to normalize form error feedback.
6. Normalized API error envelopes with `request_id` and aligned auth/rate-limit errors with `ErrorMapper`.

**Security**
1. Done: JWT secret now required via `JWT_SECRET` in prod; dev default kept in config. `config/runtime.exs`, `config/config.exs`.
2. Done: JWT no longer rendered into HTML or stored client-side for browser flows; HTML uses session auth. `lib/edoc_api_web/controllers/session_controller.ex`, `lib/edoc_api_web/components/core_components.ex`, `lib/edoc_api_web/controllers/invoice_html/*.heex`.
3. Done: Email verification token removed from redirects/UI; only sent by email. `lib/edoc_api_web/controllers/signup_controller.ex`, `lib/edoc_api_web/controllers/verification_pending_controller.ex`, `lib/edoc_api_web/controllers/verification_pending_html/new.html.heex`.
4. Done: Email sending no longer logs full email struct; only recipient and delivery result. `lib/edoc_api/email_sender.ex`.
5. Done: Added rate limiting for `/v1/auth/login` and `/v1/auth/signup`. `lib/edoc_api_web/router.ex`, `lib/edoc_api_web/plugs/rate_limit.ex`.
6. Done: `force_ssl` and secure cookies set for prod with `same_site` configuration. `lib/edoc_api_web/endpoint.ex`, `config/runtime.exs`, `config/prod.exs`.
7. Done: Self-hosted HTMX, pinned Tailwind CDN version, and tightened CSP to remove `unpkg` and restrict script/style sources. `lib/edoc_api_web/components/layouts.ex`, `lib/edoc_api_web.ex`, `config/runtime.exs`, `priv/static/vendor/htmx.min.js`.

**API Handling**
1. Done: API signup/resend now send verification emails and return accurate responses. `lib/edoc_api_web/controllers/auth_controller.ex`, `lib/edoc_api/email_sender.ex`.
2. Done: `auth_status` moved to authenticated pipeline. `lib/edoc_api_web/router.ex`, `lib/edoc_api_web/controllers/auth_controller.ex`.
3. Done (API): Normalized auth and rate-limit error responses to use `ErrorMapper`, and added a shared error envelope with `request_id`. `lib/edoc_api_web/error_mapper.ex`, `lib/edoc_api_web/plugs/authenticate.ex`, `lib/edoc_api_web/plugs/rate_limit.ex`, `lib/edoc_api_web/controllers/auth_controller.ex`.
4. Done: Added pagination with metadata to buyers/invoices/contracts list endpoints. `lib/edoc_api_web/controllers/*_controller.ex`, `lib/edoc_api_web/controller_helpers.ex`, `lib/edoc_api/*`.
5. Done (API): Error envelopes now include `request_id` and normalized `message/details` fields. `lib/edoc_api_web/error_mapper.ex`.

**UI**
1. Done: Verification token is not displayed in UI; page instructs to check email. `lib/edoc_api_web/controllers/verification_pending_html/new.html.heex`.
2. Done: HTML/HTMX flows use session auth and HTML endpoints without JWT in DOM. `lib/edoc_api_web/components/core_components.ex`, `lib/edoc_api_web/controllers/invoice_html/*.heex`.
3. Done: Added a reusable flash error summary component and applied it across HTML forms for consistent feedback. `lib/edoc_api_web/components/core_components.ex`, `lib/edoc_api_web/controllers/*_html/*.heex`.
4. Done: Self-hosted HTMX and tightened CSP; Tailwind CDN pinned to a fixed version. `lib/edoc_api_web/components/layouts.ex`, `lib/edoc_api_web.ex`, `config/runtime.exs`.
