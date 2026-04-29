defmodule EdocApiWeb.Layouts do
  @moduledoc """
  Layouts for rendering HTML pages with htmx support.
  """
  use EdocApiWeb, :html

  @doc """
  The root layout wraps the entire HTML document.
  """
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html
      lang={assigns[:locale] || "ru"}
      class="[scrollbar-gutter:stable]"
      data-theme-lock={assigns[:theme_lock]}
    >
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <meta name="color-scheme" content="light dark" />
        <title><%= assigns[:page_title] || "EdocAPI" %></title>
        <script>
          (function() {
            var root = document.documentElement;
            var themeLock = root.getAttribute("data-theme-lock");
            var storageKey = "edoc_theme";
            var preferred = null;

            if (themeLock === "dark" || themeLock === "light") {
              preferred = themeLock;
            } else {
              try {
                preferred = window.localStorage.getItem(storageKey);
              } catch (_error) {
                preferred = null;
              }
            }

            if (preferred !== "dark" && preferred !== "light") {
              preferred =
                window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches
                  ? "dark"
                  : "light";
            }

            root.classList.toggle("dark", preferred === "dark");
            root.setAttribute("data-theme", preferred);
            root.style.colorScheme = preferred;
          })();
        </script>
        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}></script>

        <!-- htmx (self-hosted) -->
        <script defer phx-track-static type="text/javascript" src={~p"/vendor/htmx.min.js"}></script>

        <!-- HTMX CSRF Token Configuration -->
        <script>
          document.addEventListener("DOMContentLoaded", function() {
            var csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
            if (csrfToken) {
              document.body.addEventListener('htmx:configRequest', function(evt) {
                evt.detail.headers['x-csrf-token'] = csrfToken;
              });
            }
          });

          function getSavedTheme() {
            try {
              return window.localStorage.getItem('edoc_theme');
            } catch (_error) {
              return null;
            }
          }

          function setSavedTheme(theme) {
            try {
              window.localStorage.setItem('edoc_theme', theme);
            } catch (_error) {}
          }

          function resolveSystemTheme() {
            return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
              ? 'dark'
              : 'light';
          }

          function updateThemeToggleUi(theme) {
            var nextLabel = theme === 'dark' ? 'Light' : 'Dark';
            var nextAria = theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode';

            document.querySelectorAll('[data-theme-toggle]').forEach(function(button) {
              button.setAttribute('aria-label', nextAria);
              button.setAttribute('data-theme-current', theme);

              var label = button.querySelector('[data-theme-label]');
              if (label) label.textContent = nextLabel;
            });
          }

          function applyWorkspaceTheme(theme) {
            var root = document.documentElement;
            root.classList.toggle('dark', theme === 'dark');
            root.setAttribute('data-theme', theme);
            root.style.colorScheme = theme;
            updateThemeToggleUi(theme);
          }

          window.toggleWorkspaceTheme = function() {
            var current = document.documentElement.classList.contains('dark') ? 'dark' : 'light';
            var next = current === 'dark' ? 'light' : 'dark';
            applyWorkspaceTheme(next);
            setSavedTheme(next);
          };

          document.addEventListener('DOMContentLoaded', function() {
            var themeLock = document.documentElement.getAttribute('data-theme-lock');
            if (themeLock === 'dark' || themeLock === 'light') {
              applyWorkspaceTheme(themeLock);
              return;
            }

            var stored = getSavedTheme();
            var initial = stored === 'dark' || stored === 'light' ? stored : resolveSystemTheme();
            applyWorkspaceTheme(initial);
          });

          if (window.matchMedia) {
            var media = window.matchMedia('(prefers-color-scheme: dark)');
            var onThemeMediaChange = function(event) {
              var themeLock = document.documentElement.getAttribute('data-theme-lock');
              if (themeLock === 'dark' || themeLock === 'light') return;

              var stored = getSavedTheme();
              if (stored === 'dark' || stored === 'light') return;
              applyWorkspaceTheme(event.matches ? 'dark' : 'light');
            };

            if (media.addEventListener) {
              media.addEventListener('change', onThemeMediaChange);
            } else if (media.addListener) {
              media.addListener(onThemeMediaChange);
            }
          }

          function positionWorkspaceOverlay(detailsEl, menuSelector, placement) {
            var menu = detailsEl.querySelector(menuSelector);
            var summary = detailsEl.querySelector('summary');

            if (!menu || !summary) return;

            if (!detailsEl.open) {
              menu.classList.add('hidden');
              return;
            }

            menu.classList.remove('hidden');

            requestAnimationFrame(function() {
              var triggerRect = summary.getBoundingClientRect();
              var menuRect = menu.getBoundingClientRect();
              var gutter = 12;
              var gap = 8;
              var left = Math.min(
                Math.max(gutter, triggerRect.right - menuRect.width),
                window.innerWidth - menuRect.width - gutter
              );
              var maxTop = Math.max(gutter, window.innerHeight - menuRect.height - gutter);
              var top;

              if (placement === 'below') {
                top = Math.min(maxTop, Math.max(gutter, triggerRect.bottom + gap));
              } else {
                top = Math.max(gutter, triggerRect.top - menuRect.height - gap);
              }

              menu.style.left = left + 'px';
              menu.style.top = top + 'px';
            });
          }

          function closeWorkspaceOverlay(detailsEl, menuSelector) {
            detailsEl.open = false;

            var menu = detailsEl.querySelector(menuSelector);
            if (menu) menu.classList.add('hidden');
          }

          window.positionWorkspaceRowActions = function(detailsEl) {
            positionWorkspaceOverlay(detailsEl, '[data-row-actions-menu]', 'above');
          };

          window.positionWorkspaceSendMenu = function(detailsEl) {
            positionWorkspaceOverlay(detailsEl, '[data-send-menu-panel]', 'below');
          };

          document.addEventListener('click', function(event) {
            document.querySelectorAll('details[data-row-actions-root][open]').forEach(function(detailsEl) {
              if (detailsEl.contains(event.target)) return;

              closeWorkspaceOverlay(detailsEl, '[data-row-actions-menu]');
            });

            document.querySelectorAll('details[data-send-menu-root][open]').forEach(function(detailsEl) {
              if (detailsEl.contains(event.target)) return;

              closeWorkspaceOverlay(detailsEl, '[data-send-menu-panel]');
            });
          });

          window.addEventListener('resize', function() {
            document.querySelectorAll('details[data-row-actions-root][open]').forEach(function(detailsEl) {
              window.positionWorkspaceRowActions(detailsEl);
            });

            document.querySelectorAll('details[data-send-menu-root][open]').forEach(function(detailsEl) {
              window.positionWorkspaceSendMenu(detailsEl);
            });
          });
        </script>

        <!-- Tailwind CSS from CDN (pinned version) -->
        <script>
          window.tailwind = window.tailwind || {};
          window.tailwind.config = {
            ...(window.tailwind.config || {}),
            darkMode: "class"
          };
        </script>
        <script src="https://cdn.tailwindcss.com/3.4.14"></script>

        <style>
          /* Custom styles for htmx */
          [hx-indicator] { display: none; }
          [hx-indicator].htmx-request { display: inline; }
          .htmx-indicator { display: none; }
          .htmx-request .htmx-indicator { display: inline; }
          .htmx-request.htmx-indicator { display: inline; }

          :root {
            --ui-page: #f7faf9;
            --ui-surface: #fbfdfc;
            --ui-surface-hover: #eef4f2;
            --ui-surface-muted: #e3ecea;
            --ui-text-primary: #1f2a28;
            --ui-text-secondary: #5f6f6b;
            --ui-text-muted: #8a9a96;
            --ui-border: #d6e2df;
            --ui-border-subtle: #e4eeec;
            --ui-accent: #11a99a;
            --ui-accent-strong: #07867b;
            --ui-accent-soft: #dff6f2;
            --ui-danger: #be123c;
            --ui-warning: #c75a17;
            --ui-shadow: 0 16px 40px -28px rgba(16, 60, 50, 0.36);
            --ui-shadow-sm: 0 1px 2px rgba(16, 60, 50, 0.08);
            --workspace-surface-bg: var(--ui-surface);
            --workspace-surface-border: var(--ui-border);
            --workspace-text-strong: var(--ui-text-primary);
            --workspace-text-muted: var(--ui-text-secondary);
            --workspace-support-bg: var(--ui-surface);
            --workspace-support-border: var(--ui-border);
            --workspace-table-head-bg: var(--ui-surface-muted);
            --workspace-table-heading: var(--ui-text-secondary);
            --workspace-table-row-hover: var(--ui-surface-hover);
            --workspace-shell-shadow: var(--ui-shadow-sm);
          }

          html[data-theme="light"] {
            color-scheme: light;
          }

          html[data-theme="dark"] {
            color-scheme: dark;
            /* dark-mode tokens with deep teal surfaces instead of pure black */
            --ui-page: #0f1f1c;
            --ui-surface: #132824;
            --ui-surface-hover: #1a3732;
            --ui-surface-muted: #203f39;
            --ui-text-primary: #f0fbf8;
            --ui-text-secondary: #c3d8d3;
            --ui-text-muted: #91aaa4;
            --ui-border: #31564f;
            --ui-border-subtle: #25463f;
            --ui-accent: #3dd6c6;
            --ui-accent-strong: #76eadf;
            --ui-accent-soft: #123d37;
            --ui-danger: #fb7185;
            --ui-warning: #fdba74;
            --ui-shadow: 0 18px 50px -28px rgba(0, 0, 0, 0.7);
            --ui-shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.45);
            --workspace-surface-bg: var(--ui-surface);
            --workspace-surface-border: var(--ui-border);
            --workspace-text-strong: var(--ui-text-primary);
            --workspace-text-muted: var(--ui-text-secondary);
            --workspace-support-bg: var(--ui-surface);
            --workspace-support-border: var(--ui-border);
            --workspace-table-head-bg: var(--ui-surface-muted);
            --workspace-table-heading: var(--ui-text-primary);
            --workspace-table-row-hover: var(--ui-surface-hover);
            --workspace-shell-shadow: var(--ui-shadow-sm);
          }

          html[data-theme="dark"] body[data-workspace-theme-root] {
            background-color: var(--ui-page);
            color: var(--ui-text-primary);
          }

          body[data-workspace-theme-root] {
            background:
              radial-gradient(circle at top left, rgba(17, 169, 154, 0.12), transparent 28rem),
              var(--ui-page);
            color: var(--ui-text-primary);
          }

          .ui-surface {
            background-color: var(--ui-page);
            color: var(--ui-text-primary);
          }

          .ui-card {
            background-color: var(--ui-surface);
            border-color: var(--ui-border);
            color: var(--ui-text-primary);
            box-shadow: var(--ui-shadow-sm);
          }

          .ui-card-muted {
            background-color: var(--ui-surface-muted);
            border-color: var(--ui-border);
            color: var(--ui-text-primary);
          }

          .ui-text-primary { color: var(--ui-text-primary); }
          .ui-text-secondary { color: var(--ui-text-secondary); }
          .ui-text-muted { color: var(--ui-text-muted); }

          .ui-table {
            background-color: var(--ui-surface);
            border-color: var(--ui-border);
            color: var(--ui-text-primary);
            box-shadow: var(--ui-shadow-sm);
          }

          .ui-table thead,
          .ui-table-head {
            background-color: var(--ui-surface-muted);
          }

          .ui-table tbody tr:nth-child(even) {
            background-color: color-mix(in srgb, var(--ui-surface-hover) 42%, transparent);
          }

          .ui-table-row {
            color: var(--ui-text-primary);
            transition: background-color 150ms ease, color 150ms ease;
          }

          .ui-table-row:hover {
            background-color: var(--ui-surface-hover);
          }

          .ui-input {
            background-color: var(--ui-surface);
            border-color: var(--ui-border);
            color: var(--ui-text-primary);
            box-shadow: var(--ui-shadow-sm);
          }

          .ui-input::placeholder {
            color: var(--ui-text-muted);
          }

          .ui-input:focus {
            border-color: var(--ui-accent);
            outline: 2px solid color-mix(in srgb, var(--ui-accent) 26%, transparent);
            outline-offset: 1px;
          }

          .ui-button-primary,
          .ui-button-secondary,
          .ui-button-danger,
          .ui-button-warning {
            border-radius: 9999px;
            transition:
              background-color 150ms ease,
              border-color 150ms ease,
              box-shadow 150ms ease,
              color 150ms ease;
          }

          .ui-button-primary {
            background-color: var(--ui-accent);
            color: #ffffff;
          }

          .ui-button-primary:hover {
            background-color: var(--ui-accent-strong);
            box-shadow: var(--ui-shadow);
          }

          .ui-button-secondary {
            background-color: var(--ui-surface);
            border: 1px solid var(--ui-border);
            color: var(--ui-text-primary);
          }

          .ui-button-secondary:hover {
            background-color: var(--ui-surface-hover);
            box-shadow: var(--ui-shadow-sm);
          }

          .ui-button-danger {
            background-color: var(--ui-danger);
            color: #ffffff;
          }

          .ui-button-warning {
            background-color: var(--ui-warning);
            color: #ffffff;
          }

          html[data-theme="dark"] .bg-white,
          html[data-theme="dark"] .bg-gray-50,
          html[data-theme="dark"] .bg-stone-50 {
            background-color: #0f172a;
          }

          html[data-theme="dark"] .text-gray-900,
          html[data-theme="dark"] .text-slate-900 {
            color: #f8fafc;
          }

          html[data-theme="dark"] .text-gray-700,
          html[data-theme="dark"] .text-gray-600,
          html[data-theme="dark"] .text-gray-500,
          html[data-theme="dark"] .text-slate-700,
          html[data-theme="dark"] .text-slate-600,
          html[data-theme="dark"] .text-slate-500 {
            color: #cbd5e1;
          }

          html[data-theme="dark"] .workspace-public-nav-link {
            color: #e2e8f0;
          }

          html[data-theme="dark"] .workspace-public-nav-link:hover {
            color: #ffffff;
          }

          .workspace-app-header {
            background-color: color-mix(in srgb, var(--ui-surface) 94%, transparent);
            border-color: var(--ui-border);
          }

          html[data-theme="dark"] .workspace-app-header {
            background-color: color-mix(in srgb, var(--ui-surface) 94%, transparent);
            border-color: var(--ui-border-subtle);
          }

          .workspace-shell-panel {
            background-color: color-mix(in srgb, var(--ui-surface) 88%, transparent);
            border-color: var(--ui-border);
            color: var(--ui-text-primary);
          }

          html[data-theme="dark"] .workspace-shell-panel {
            background-color: color-mix(in srgb, var(--ui-surface) 90%, transparent);
            border-color: var(--ui-border);
            color: var(--ui-text-primary);
          }

          html[data-theme="dark"] .border-gray-200,
          html[data-theme="dark"] .border-stone-200 {
            border-color: #334155;
          }

          html[data-theme="dark"] .ring-stone-200,
          html[data-theme="dark"] .ring-slate-200 {
            --tw-ring-color: #334155;
          }

          html[data-theme="dark"] .workspace-nav-link-inactive {
            color: #e2e8f0;
          }

          html[data-theme="dark"] .workspace-nav-link-inactive:hover {
            color: #ffffff;
          }

          html[data-theme="dark"] .workspace-locale-inactive {
            color: #e2e8f0;
          }

          html[data-theme="dark"] .workspace-locale-inactive:hover {
            color: #ffffff;
          }

          html[data-theme="dark"] .workspace-account-email {
            color: #e2e8f0;
          }

          html[data-theme="dark"] .workspace-account-logout {
            color: #e2e8f0;
          }

          html[data-theme="dark"] .workspace-account-logout:hover {
            color: #000000;
          }

          html[data-theme="dark"] .admin-billing-card-heading,
          html[data-theme="dark"] .admin-billing-table-heading,
          html[data-theme="dark"] .admin-billing-invoice-table-heading {
            color: #ffffff !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .admin-billing-invoice-action-cell,
          html[data-theme="dark"] .admin-billing-invoice-action-cell span {
            color: #ffffff !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .admin-billing-client-summary-heading,
          html[data-theme="dark"] .admin-billing-client-label,
          html[data-theme="dark"] .admin-billing-client-table-heading,
          html[data-theme="dark"] .admin-billing-client-meta-label,
          html[data-theme="dark"] .admin-billing-client-history-text,
          html[data-theme="dark"] .admin-billing-client-history-text span {
            color: #ffffff !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .workspace-support-panel {
            background-color: var(--workspace-support-bg);
            border-color: var(--workspace-support-border);
            color: var(--workspace-text-strong);
          }

          html[data-theme="dark"] .workspace-support-panel h2 {
            color: var(--workspace-text-strong);
          }

          html[data-theme="dark"] .workspace-support-panel p,
          html[data-theme="dark"] .workspace-support-panel dt {
            color: var(--workspace-text-muted);
          }

          html[data-theme="dark"] .workspace-support-panel dd {
            color: var(--workspace-text-strong);
          }

          html[data-theme="dark"] .workspace-support-panel .workspace-status-badge {
            color: #000000;
          }

          html[data-theme="dark"] .auth-form-card {
            background-color: #0f172a !important;
            border-color: #475569 !important;
            color: #f8fafc !important;
            --tw-ring-color: rgba(148, 163, 184, 0.55) !important;
          }

          html[data-theme="dark"] .auth-form-copy,
          html[data-theme="dark"] .auth-form-title,
          html[data-theme="dark"] .auth-form-label,
          html[data-theme="dark"] .auth-form-helper,
          html[data-theme="dark"] .auth-form-divider-chip,
          html[data-theme="dark"] .auth-form-divider-line {
            color: #f8fafc !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .auth-form-copy,
          html[data-theme="dark"] .auth-form-helper {
            color: #cbd5e1 !important;
          }

          html[data-theme="dark"] .auth-form-divider-line {
            border-color: #475569 !important;
          }

          html[data-theme="dark"] .auth-form-divider-chip {
            background-color: #0f172a !important;
            color: #e2e8f0 !important;
          }

          html[data-theme="dark"] .auth-form-input {
            background-color: #020617 !important;
            color: #f8fafc !important;
            border-color: #475569 !important;
            caret-color: #f8fafc;
            --tw-ring-color: #475569 !important;
          }

          html[data-theme="dark"] .auth-form-input::placeholder {
            color: #94a3b8 !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .auth-form-input:-webkit-autofill,
          html[data-theme="dark"] .auth-form-input:-webkit-autofill:hover,
          html[data-theme="dark"] .auth-form-input:-webkit-autofill:focus {
            -webkit-text-fill-color: #f8fafc !important;
            box-shadow: 0 0 0 1000px #020617 inset !important;
          }

          html[data-theme="dark"] .auth-form-link {
            color: #93c5fd !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .auth-form-link:hover {
            color: #bfdbfe !important;
          }

          html[data-theme="dark"] .auth-form-submit {
            background-color: #2563eb !important;
            color: #ffffff !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .auth-form-submit:hover {
            background-color: #1d4ed8 !important;
          }

          html[data-theme="dark"] .about-section-card {
            background-color: #0f172a !important;
            border-color: #475569 !important;
            color: #f8fafc !important;
          }

          html[data-theme="dark"] .about-section-title {
            color: #ffffff !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .about-cta-card {
            background-color: #082f49 !important;
            border-color: rgba(125, 211, 252, 0.6) !important;
            color: #f8fafc !important;
          }

          html[data-theme="dark"] .about-cta-title,
          html[data-theme="dark"] .about-cta-copy {
            color: #f8fafc !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .about-cta-copy {
            color: #e0f2fe !important;
          }

          html[data-theme="dark"] .about-cta-primary-link {
            background-color: #2563eb !important;
            color: #ffffff !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .about-cta-primary-link:hover {
            background-color: #1d4ed8 !important;
          }

          html[data-theme="dark"] .about-cta-secondary-link {
            background-color: #f8fafc !important;
            border-color: #bae6fd !important;
            color: #0f172a !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .about-cta-secondary-link:hover {
            background-color: #e0f2fe !important;
            color: #020617 !important;
          }

          html[data-theme="dark"] .overdue-upgrade-card {
            background-color: #020617 !important;
            border-color: #94a3b8 !important;
          }

          html[data-theme="dark"] .overdue-upgrade-text {
            color: #ffffff !important;
            opacity: 1 !important;
            filter: none !important;
            text-shadow: 0 1px 2px rgba(0, 0, 0, 0.45);
          }

          html[data-theme="dark"] .company-billing-summary-heading {
            color: #ffffff !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .company-billing-upgrade-card {
            background-color: rgba(7, 89, 133, 0.7) !important;
            border-color: #7dd3fc !important;
          }

          html[data-theme="dark"] .company-billing-upgrade-title,
          html[data-theme="dark"] .company-billing-upgrade-copy {
            color: #ffffff !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] .billing-scheduled-change-card {
            background-color: rgba(6, 95, 70, 0.72) !important;
            border-color: #6ee7b7 !important;
            color: #ffffff !important;
          }

          html[data-theme="dark"] .billing-scheduled-change-title,
          html[data-theme="dark"] .billing-scheduled-change-copy,
          html[data-theme="dark"] .billing-scheduled-change-label,
          html[data-theme="dark"] .billing-scheduled-change-value {
            color: #ffffff !important;
            opacity: 1 !important;
          }

          html[data-theme="dark"] [data-row-actions-menu],
          html[data-theme="dark"] [data-send-menu-panel] {
            background-color: #334155;
            border-color: #94a3b8;
          }

          html[data-theme="dark"] [data-row-actions-menu] .text-sky-700,
          html[data-theme="dark"] [data-send-menu-panel] .text-sky-700 {
            color: #7dd3fc;
          }

          html[data-theme="dark"] [data-row-actions-menu] .text-emerald-700,
          html[data-theme="dark"] [data-send-menu-panel] .text-emerald-700 {
            color: #86efac;
          }

          html[data-theme="dark"] [data-row-actions-menu] .text-rose-700,
          html[data-theme="dark"] [data-send-menu-panel] .text-rose-700 {
            color: #fda4af;
          }

          html[data-theme="dark"] [data-row-actions-menu] .text-slate-700,
          html[data-theme="dark"] [data-send-menu-panel] .text-slate-700 {
            color: #e2e8f0;
          }

          html[data-theme="dark"] [data-row-actions-menu] :is(button, a):hover,
          html[data-theme="dark"] [data-send-menu-panel] :is(button, a):hover,
          html[data-theme="dark"] [data-row-actions-menu] .send-menu-item:hover,
          html[data-theme="dark"] [data-send-menu-panel] .send-menu-item:hover {
            background-color: #475569;
          }

          .workspace-table-shell {
            border-color: var(--workspace-surface-border);
            background-color: var(--workspace-surface-bg);
            box-shadow: var(--workspace-shell-shadow);
            border-radius: 1.5rem;
          }

          .workspace-table-head-surface {
            background-color: var(--workspace-table-head-bg);
          }

          html[data-theme="dark"] .workspace-table-head-surface {
            background-color: var(--workspace-table-head-bg);
          }

          .workspace-table-heading {
            color: var(--workspace-table-heading);
          }

          html[data-theme="dark"] .workspace-table-heading {
            color: var(--workspace-table-heading);
          }

          .workspace-table-row { transition: background-color 150ms ease, color 150ms ease; }

          .workspace-table-row:hover {
            background-color: var(--workspace-table-row-hover);
            color: var(--workspace-text-strong);
          }

          html[data-theme="dark"] .workspace-table-row:hover {
            background-color: var(--workspace-table-row-hover);
            color: var(--workspace-text-strong);
          }

          html[data-theme="dark"] .workspace-document-shell {
            background-color: #0f172a;
            border-color: #334155;
            color: #f8fafc;
          }

          html[data-theme="dark"] .workspace-document-shell h1,
          html[data-theme="dark"] .workspace-document-shell h2,
          html[data-theme="dark"] .workspace-document-shell h3,
          html[data-theme="dark"] .workspace-document-shell h4,
          html[data-theme="dark"] .workspace-document-shell p,
          html[data-theme="dark"] .workspace-document-shell a,
          html[data-theme="dark"] .workspace-document-shell span,
          html[data-theme="dark"] .workspace-document-shell dt,
          html[data-theme="dark"] .workspace-document-shell dd {
            color: #f8fafc;
          }

          html[data-theme="dark"] .workspace-document-preview-surface {
            background-color: #ffffff;
            border-color: #94a3b8;
            color: #0f172a;
          }

          html[data-theme="dark"] .workspace-document-preview-surface .invoice-doc,
          html[data-theme="dark"] .workspace-document-preview-surface .contract-doc,
          html[data-theme="dark"] .workspace-document-preview-surface .act-doc {
            color: #000000;
          }

          html[data-theme="dark"] .workspace-document-preview-surface .invoice-doc *,
          html[data-theme="dark"] .workspace-document-preview-surface .contract-doc *,
          html[data-theme="dark"] .workspace-document-preview-surface .act-doc * {
            color: inherit;
          }

          .workspace-detail-shell {
            border-color: var(--workspace-surface-border);
            background-color: var(--workspace-surface-bg);
            color: var(--workspace-text-strong);
          }

          .workspace-preview-title {
            color: var(--workspace-text-strong);
          }

          .workspace-overview-term {
            color: var(--workspace-text-muted);
          }

          .workspace-overview-value {
            color: var(--workspace-text-strong);
          }

          .workspace-action-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            border-radius: 9999px;
            padding: 0.5rem 1rem;
            font-size: 0.875rem;
            font-weight: 600;
            line-height: 1.25rem;
            transition: background-color 150ms ease, border-color 150ms ease, color 150ms ease;
          }

          .workspace-action-btn-secondary {
            border: 1px solid #cbd5e1;
            background-color: #ffffff;
            color: #334155;
          }

          .workspace-action-btn-secondary:hover {
            border-color: #94a3b8;
            color: #0f172a;
          }

          .workspace-action-btn-success {
            background-color: #059669;
            color: #ffffff;
          }

          .workspace-action-btn-success:hover {
            background-color: #047857;
          }

          .workspace-action-btn-primary {
            background-color: #0284c7;
            color: #ffffff;
          }

          .workspace-action-btn-primary:hover {
            background-color: #0369a1;
            box-shadow: 0 10px 24px -12px rgba(15, 23, 42, 0.55);
          }

          .workspace-action-btn-danger {
            background-color: #be123c;
            color: #ffffff;
          }

          .workspace-action-btn-danger:hover {
            background-color: #9f1239;
            box-shadow: 0 10px 24px -12px rgba(15, 23, 42, 0.55);
          }

          .workspace-action-btn-neutral {
            background-color: #0f172a;
            color: #ffffff;
          }

          .workspace-action-btn-neutral:hover {
            background-color: #1e293b;
            box-shadow: 0 10px 24px -12px rgba(15, 23, 42, 0.55);
          }

          .workspace-action-btn-warning {
            background-color: #ea580c;
            color: #ffffff;
          }

          .workspace-action-btn-warning:hover {
            background-color: #c2410c;
            box-shadow: 0 10px 24px -12px rgba(15, 23, 42, 0.55);
          }

          .workspace-action-btn-yellow {
            background-color: #facc15;
            color: #111827;
          }

          .workspace-action-btn-yellow:hover {
            background-color: #eab308;
            box-shadow: 0 10px 24px -12px rgba(15, 23, 42, 0.35);
          }

          html[data-theme="dark"] .workspace-action-btn-secondary {
            border-color: #475569;
            background-color: #0f172a;
            color: #e2e8f0;
          }

          html[data-theme="dark"] .workspace-action-btn-secondary:hover {
            border-color: #64748b;
            color: #f8fafc;
          }

          html[data-theme="dark"] .company-team-row {
            transition: background-color 150ms ease, color 150ms ease;
          }

          html[data-theme="dark"] .company-team-row:hover {
            background-color: #1e293b;
            color: #f8fafc;
          }

          html[data-theme="dark"] .company-bank-row {
            transition: background-color 150ms ease, color 150ms ease;
          }

          html[data-theme="dark"] .company-bank-row:hover {
            background-color: #1e293b;
            color: #f8fafc;
          }

          html[data-theme="dark"] .company-member-warning {
            background-color: #0f172a;
            border-color: #334155;
            color: #f8fafc;
          }

          .workspace-form input:not([type="checkbox"]):not([type="radio"]):not([type="hidden"]),
          .workspace-form select,
          .workspace-form textarea {
            background-color: var(--ui-surface);
            border-color: var(--ui-border);
            color: var(--ui-text-primary);
            transition:
              background-color 150ms ease,
              border-color 150ms ease,
              box-shadow 150ms ease,
              color 150ms ease;
          }

          .workspace-form label {
            color: var(--ui-text-secondary);
          }

          html[data-theme="dark"] .workspace-form label {
            color: var(--ui-text-secondary);
          }

          .workspace-form-mode-surface {
            background-color: var(--ui-accent-soft);
            border-color: color-mix(in srgb, var(--ui-accent) 46%, var(--ui-border));
          }

          .workspace-form-items-surface {
            background-color: var(--ui-surface-hover);
          }

          .workspace-form-static-value,
          .workspace-form-currency-readonly {
            background-color: var(--ui-surface-muted);
            border-color: var(--ui-border);
            color: var(--ui-text-primary);
          }

          html[data-theme="dark"] .workspace-form-mode-surface {
            background-color: var(--ui-accent-soft);
            border-color: var(--ui-border);
          }

          html[data-theme="dark"] .workspace-form-mode-option,
          html[data-theme="dark"] .workspace-form-items-heading {
            color: var(--ui-text-primary);
          }

          html[data-theme="dark"] .workspace-form-items-surface {
            background-color: var(--ui-surface-hover);
          }

          html[data-theme="dark"] .workspace-form-static-value {
            background-color: var(--ui-surface-muted);
            border-color: var(--ui-border);
            color: var(--ui-text-primary);
          }

          html[data-theme="dark"] .workspace-form-currency-readonly {
            background-color: var(--ui-surface-muted);
            border-color: var(--ui-border);
            color: var(--ui-text-primary);
          }

          html[data-theme="dark"] .workspace-form-item-label {
            color: var(--ui-text-secondary);
          }

          html[data-theme="dark"] .workspace-form input:not([type="checkbox"]):not([type="radio"]):not([type="hidden"]),
          html[data-theme="dark"] .workspace-form select,
          html[data-theme="dark"] .workspace-form textarea {
            background-color: var(--ui-surface);
            border-color: var(--ui-border);
            color: var(--ui-text-primary);
          }

          html[data-theme="dark"] .workspace-form input::placeholder,
          html[data-theme="dark"] .workspace-form textarea::placeholder {
            color: #94a3b8;
          }
        </style>
      </head>
      <body
        data-workspace-theme-root
        class="ui-surface bg-gray-50 text-gray-800 antialiased transition-colors dark:bg-slate-950 dark:text-slate-100"
      >
        {@inner_content}
      </body>
    </html>
    """
  end

  @doc """
  Public navigation for unauthenticated users
  """
  def public_nav(assigns) do
    assigns =
      assigns
      |> Map.put_new(:nav_context, :public)
      |> Map.put_new(:current_path, "/")
      |> Map.put(:public_mobile_cta, public_mobile_cta(assigns[:current_path] || "/"))

    ~H"""
    <div data-public-nav-desktop class="hidden items-center gap-4 lg:flex">
      <a href="/" class="workspace-public-nav-link font-medium text-gray-600 hover:text-gray-900 dark:text-slate-100 dark:hover:text-white"><%= gettext("Home") %></a>
      <a href="/about" class="workspace-public-nav-link font-medium text-gray-600 hover:text-gray-900 dark:text-slate-100 dark:hover:text-white"><%= gettext("About") %></a>
      <%= locale_switcher(assigns) %>
      <%= theme_switcher(assigns, :desktop) %>
      <%= if @current_path != "/login" do %>
        <a href="/login" class="rounded-full border border-stone-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm transition hover:border-stone-300 hover:text-slate-900 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100 dark:hover:border-slate-600 dark:hover:text-white">
          <%= gettext("Sign In") %>
        </a>
      <% end %>
      <%= if @current_path != "/signup" do %>
        <a href="/signup" class="rounded-full bg-blue-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-blue-700 dark:bg-blue-500 dark:hover:bg-blue-400">
          <%= gettext("Sign Up") %>
        </a>
      <% end %>
    </div>

    <div data-public-nav-mobile class="flex items-center gap-2 lg:hidden">
      <%= if @public_mobile_cta do %>
        <a
          href={@public_mobile_cta.path}
          class="inline-flex h-11 items-center rounded-full bg-blue-600 px-4 text-sm font-semibold text-white shadow-sm transition hover:bg-blue-700 dark:bg-blue-500 dark:hover:bg-blue-400"
        >
          <%= @public_mobile_cta.label %>
        </a>
      <% end %>

      <details class="group relative">
        <summary class="flex h-11 w-11 cursor-pointer list-none items-center justify-center rounded-full border border-stone-200 bg-white text-slate-700 shadow-sm transition hover:border-stone-300 hover:text-slate-900 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-100 dark:hover:border-slate-600 dark:hover:text-white">
          <span class="sr-only"><%= gettext("Menu") %></span>
          <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round">
            <path d="M4 7h16" />
            <path d="M4 12h16" />
            <path d="M4 17h16" />
          </svg>
        </summary>

        <div
          data-public-mobile-menu-panel
          class="absolute right-0 top-full z-50 mt-3 w-72 rounded-[28px] border border-stone-200 bg-white/95 p-4 shadow-2xl ring-1 ring-black/5 backdrop-blur dark:border-slate-700 dark:bg-slate-950/95 dark:ring-white/10"
        >
          <nav class="space-y-1">
            <a href="/" class="block rounded-2xl px-3 py-3 text-sm font-medium text-slate-700 transition hover:bg-stone-100 hover:text-slate-900 dark:text-slate-100 dark:hover:bg-slate-800 dark:hover:text-white">
              <%= gettext("Home") %>
            </a>
            <a href="/about" class="block rounded-2xl px-3 py-3 text-sm font-medium text-slate-700 transition hover:bg-stone-100 hover:text-slate-900 dark:text-slate-100 dark:hover:bg-slate-800 dark:hover:text-white">
              <%= gettext("About") %>
            </a>
          </nav>

          <div class="mt-4 grid grid-cols-2 gap-2">
            <%= if @current_path != "/login" do %>
              <a href="/login" class="inline-flex items-center justify-center rounded-2xl border border-stone-200 px-3 py-2.5 text-sm font-semibold text-slate-700 transition hover:bg-stone-100 hover:text-slate-900 dark:border-slate-700 dark:text-slate-100 dark:hover:bg-slate-800 dark:hover:text-white">
                <%= gettext("Sign In") %>
              </a>
            <% end %>
            <%= if @current_path != "/signup" do %>
              <a href="/signup" class="inline-flex items-center justify-center rounded-2xl bg-blue-600 px-3 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-700 dark:bg-blue-500 dark:hover:bg-blue-400">
                <%= gettext("Sign Up") %>
              </a>
            <% end %>
          </div>

          <div class="mt-4 border-t border-stone-200 pt-4 dark:border-slate-700">
            <%= locale_switcher(assigns) %>
            <%= theme_switcher(assigns, :mobile) %>
          </div>
        </div>
      </details>
    </div>
    """
  end

  @doc """
  Authenticated user navigation
  """
  def auth_nav(assigns) do
    assigns = Map.put_new(assigns, :current_section, nil)
    assigns = Map.put_new(assigns, :nav_context, :workspace)

    ~H"""
    <div class="flex w-full flex-col items-stretch gap-3 lg:flex-row lg:items-center lg:justify-end">
      <nav class="hidden items-center gap-2 lg:flex" aria-label={gettext("Menu")}>
        <%= for {section, path} <- workspace_sections() do %>
          <% active? = section == @current_section %>
          <a
            href={path}
            aria-current={if active?, do: "page", else: nil}
            class={nav_link_class(active?)}
          >
            <%= section_label(section) %>
          </a>
        <% end %>
      </nav>

      <details class="workspace-shell-panel rounded-2xl bg-white/80 ring-1 ring-stone-200 dark:bg-slate-900/80 dark:ring-slate-700 lg:hidden">
        <summary class="flex cursor-pointer list-none items-center justify-between px-4 py-3 text-sm font-semibold text-slate-900 dark:text-slate-100">
          <span><%= section_label(@current_section) %></span>
          <span class="text-slate-400 dark:text-slate-500">+</span>
        </summary>
        <div class="border-t border-stone-200 px-3 py-3 dark:border-slate-700">
          <div class="space-y-1">
            <%= for {section, path} <- workspace_sections() do %>
              <a
                href={path}
                aria-current={if section == @current_section, do: "page", else: nil}
                class={[
                  "block rounded-xl px-3 py-2 text-sm",
                  if(
                    section == @current_section,
                    do: "bg-stone-100 font-semibold text-slate-900 dark:bg-slate-800 dark:text-slate-100",
                    else: "workspace-nav-link-inactive text-slate-700 hover:text-slate-900 dark:text-slate-100 dark:hover:text-white"
                  )
                ]}
              >
                <%= section_label(section) %>
              </a>
            <% end %>
          </div>
          <div class="mt-3 border-t border-stone-200 pt-3 dark:border-slate-700">
            <%= locale_switcher(assigns) %>
            <%= theme_switcher(assigns, :mobile) %>
            <a href="/settings" class="workspace-account-email mt-3 block text-sm text-slate-700 dark:text-slate-100">
              <%= @current_user.email %>
            </a>
            <form method="post" action="/logout" class="mt-3">
              <input type="hidden" name="_method" value="delete" />
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
              <button
                type="submit"
                class="workspace-account-logout w-full rounded-xl border border-stone-200 px-3 py-2 text-left text-sm font-medium text-slate-700 hover:text-slate-900 dark:border-slate-700 dark:text-slate-100 dark:hover:text-white"
              >
                <%= gettext("Logout") %>
              </button>
            </form>
          </div>
        </div>
      </details>

      <div class="hidden items-center gap-3 lg:flex">
        <%= locale_switcher(assigns) %>
        <%= theme_switcher(assigns, :desktop) %>
        <div class="workspace-shell-panel flex items-center gap-3 rounded-full bg-white/85 px-3 py-2 text-sm shadow-sm ring-1 ring-stone-200 dark:bg-slate-900/85 dark:ring-slate-700">
          <a href="/settings" class="workspace-account-email text-slate-700 dark:text-slate-100"><%= @current_user.email %></a>
          <form method="post" action="/logout">
            <input type="hidden" name="_method" value="delete" />
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <button type="submit" class="workspace-account-logout font-medium text-slate-700 hover:text-slate-900 dark:text-slate-100 dark:hover:text-white">
              <%= gettext("Logout") %>
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Platform admin navigation for backoffice pages.
  """
  def admin_nav(assigns) do
    assigns =
      assigns
      |> Map.put_new(:current_path, "/admin/billing/clients")
      |> Map.put_new(:nav_context, :admin)

    ~H"""
    <div class="flex w-full flex-col items-stretch gap-3 lg:flex-row lg:items-center lg:justify-end">
      <nav class="hidden items-center gap-2 lg:flex" aria-label="Admin menu">
        <%= for {section, path, label} <- admin_sections() do %>
          <% active? = admin_section_active?(section, @current_path) %>
          <a
            href={path}
            aria-current={if active?, do: "page", else: nil}
            class={admin_nav_link_class(active?)}
          >
            <%= label %>
          </a>
        <% end %>
      </nav>

      <details class="rounded-2xl bg-white/80 ring-1 ring-stone-200 dark:bg-slate-900/80 dark:ring-slate-700 lg:hidden">
        <summary class="flex cursor-pointer list-none items-center justify-between px-4 py-3 text-sm font-semibold text-slate-900 dark:text-slate-100">
          <span>Admin</span>
          <span class="text-slate-400 dark:text-slate-500">+</span>
        </summary>
        <div class="border-t border-stone-200 px-3 py-3 dark:border-slate-700">
          <div class="space-y-1">
            <%= for {section, path, label} <- admin_sections() do %>
              <% active? = admin_section_active?(section, @current_path) %>
              <a
                href={path}
                aria-current={if active?, do: "page", else: nil}
                class={[
                  "block rounded-xl px-3 py-2 text-sm",
                  if(
                    active?,
                    do: "bg-stone-100 font-semibold text-slate-900 dark:bg-slate-800 dark:text-slate-100",
                    else: "text-black hover:text-black dark:text-slate-100 dark:hover:text-white"
                  )
                ]}
              >
                <%= label %>
              </a>
            <% end %>
          </div>
          <div class="mt-3 border-t border-stone-200 pt-3 dark:border-slate-700">
            <%= locale_switcher(assigns) %>
            <%= theme_switcher(assigns, :mobile) %>
            <a href="/settings" class="workspace-account-email mt-3 block text-sm text-black dark:text-slate-100">
              <%= @current_user.email %>
            </a>
            <form method="post" action="/logout" class="mt-3">
              <input type="hidden" name="_method" value="delete" />
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
              <button
                type="submit"
                class="workspace-account-logout w-full rounded-xl border border-stone-200 px-3 py-2 text-left text-sm font-medium text-black dark:border-slate-700 dark:text-slate-100 dark:hover:text-white"
              >
                <%= gettext("Logout") %>
              </button>
            </form>
          </div>
        </div>
      </details>

      <div class="hidden items-center gap-3 lg:flex">
        <%= locale_switcher(assigns) %>
        <%= theme_switcher(assigns, :desktop) %>
        <div class="flex items-center gap-3 rounded-full bg-white/85 px-3 py-2 text-sm shadow-sm ring-1 ring-stone-200 dark:bg-slate-900/85 dark:ring-slate-700">
          <a href="/settings" class="workspace-account-email text-black dark:text-slate-100"><%= @current_user.email %></a>
          <form method="post" action="/logout">
            <input type="hidden" name="_method" value="delete" />
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <button type="submit" class="workspace-account-logout font-medium text-black hover:text-black dark:text-slate-100 dark:hover:text-white">
              <%= gettext("Logout") %>
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  The app layout includes the header and main content area.
  """
  def app(assigns) do
    public_guest? = is_nil(assigns[:current_user])

    assigns = Map.put(assigns, :public_guest?, public_guest?)

    ~H"""
    <header class="workspace-app-header relative z-50 ui-card border-b border-stone-200 bg-stone-50/95 backdrop-blur dark:border-slate-800 dark:bg-slate-900/95">
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div class={[
          "py-4",
          if(
            @public_guest?,
            do: "flex items-center justify-between gap-4",
            else: "flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between"
          )
        ]}>
          <div class="flex items-center">
            <%= brand_logo(assigns) %>
          </div>
          <%= if assigns[:current_user] && assigns[:nav_context] == :admin do %>
            <%= admin_nav(assigns) %>
          <% else %>
            <%= if assigns[:current_user] do %>
            <%= auth_nav(assigns) %>
            <% else %>
              <%= public_nav(assigns) %>
            <% end %>
          <% end %>
        </div>
      </div>
    </header>

    <main class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      {@inner_content}
    </main>
    """
  end

  defp brand_logo(assigns) do
    assigns =
      assigns
      |> Map.put_new(:nav_context, :workspace)
      |> Map.put(:home_path, if(assigns[:nav_context] == :admin, do: "/admin/billing", else: "/"))

    ~H"""
    <a href={@home_path} class="inline-flex items-center gap-2 text-xl font-extrabold text-[#0066cc] dark:text-sky-400">
      <span class="flex h-10 w-10 items-center justify-center rounded-[10px] bg-gradient-to-br from-[#0066cc] to-[#00a651] text-white shadow-sm">
        <svg
          class="h-5 w-5"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M9 3h6l4 4v14H9a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Z" />
          <path d="M15 3v4h4" />
          <path d="M11 12h6" />
          <path d="M11 16h6" />
        </svg>
      </span>
      <span>Edocly</span>
    </a>
    """
  end

  defp locale_switcher(assigns) do
    assigns =
      Map.merge(assigns, %{
        current_path: assigns[:current_path] || "/",
        locale: assigns[:locale] || "ru",
        nav_context: assigns[:nav_context] || :workspace
      })

    ~H"""
    <div class="inline-flex items-center rounded-full bg-stone-100 p-1 ring-1 ring-stone-200 dark:bg-slate-800 dark:ring-slate-700">
      <a
        href={locale_path("kk", @current_path)}
        class={[
          "workspace-locale-inactive rounded-full px-2.5 py-1 text-xs font-semibold uppercase tracking-wide",
          if(
            @locale == "kk",
            do:
              if(
                @nav_context == :public,
                do: "bg-white text-slate-900 shadow-sm dark:bg-slate-900 dark:text-white",
                else: "bg-white text-slate-900 shadow-sm dark:bg-slate-900 dark:text-slate-100"
              ),
            else:
              if(
                @nav_context == :public,
                do: "text-slate-600 hover:text-slate-900 dark:text-white dark:hover:text-white",
                else: "text-slate-700 hover:text-slate-900 dark:text-slate-100 dark:hover:text-white"
              )
          )
        ]}
      >
        Қаз
      </a>
      <a
        href={locale_path("ru", @current_path)}
        class={[
          "workspace-locale-inactive rounded-full px-2.5 py-1 text-xs font-semibold uppercase tracking-wide",
          if(
            @locale == "ru",
            do:
              if(
                @nav_context == :public,
                do: "bg-white text-slate-900 shadow-sm dark:bg-slate-900 dark:text-white",
                else: "bg-white text-slate-900 shadow-sm dark:bg-slate-900 dark:text-slate-100"
              ),
            else:
              if(
                @nav_context == :public,
                do: "text-slate-600 hover:text-slate-900 dark:text-white dark:hover:text-white",
                else: "text-slate-700 hover:text-slate-900 dark:text-slate-100 dark:hover:text-white"
              )
          )
        ]}
      >
        Рус
      </a>
    </div>
    """
  end

  defp section_label(:invoices), do: gettext("Invoices")
  defp section_label(:buyers), do: gettext("Buyers")
  defp section_label(:contracts), do: gettext("Contracts")
  defp section_label(:acts), do: gettext("Acts")
  defp section_label(:company), do: gettext("Company")

  defp section_label(_), do: gettext("Menu")

  defp theme_switcher(assigns, mode) do
    assigns = Map.put(assigns, :mobile?, mode == :mobile)

    ~H"""
    <button
      type="button"
      data-theme-toggle
      data-theme-current="light"
      onclick="window.toggleWorkspaceTheme && window.toggleWorkspaceTheme()"
      aria-label="Switch to dark mode"
      class={[
        "inline-flex items-center justify-center rounded-full border border-stone-200 bg-white px-3 py-2 text-sm font-medium text-slate-600 shadow-sm transition hover:text-slate-900 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300 dark:hover:text-slate-100",
        if(@mobile?, do: "mt-3 w-full justify-between rounded-xl")
      ]}
    >
      <span data-theme-label class="font-semibold">Dark</span>
    </button>
    """
  end

  defp nav_link_class(active?) do
    if active? do
      "inline-flex items-center rounded-full bg-white px-3 py-2 text-sm font-semibold text-slate-900 shadow-sm ring-1 ring-slate-200 dark:bg-slate-900 dark:text-slate-100 dark:ring-slate-700"
    else
      "workspace-nav-link-inactive inline-flex items-center rounded-full px-3 py-2 text-sm font-medium text-slate-700 hover:text-slate-900 dark:text-slate-100 dark:hover:text-white"
    end
  end

  defp admin_nav_link_class(active?) do
    if active? do
      "inline-flex items-center rounded-full bg-slate-900 px-3 py-2 text-sm font-semibold text-white shadow-sm ring-1 ring-slate-900 dark:bg-slate-100 dark:text-slate-950 dark:ring-slate-100"
    else
      "inline-flex items-center rounded-full px-3 py-2 text-sm font-medium text-black hover:bg-white/70 hover:text-black dark:text-slate-100 dark:hover:bg-slate-800 dark:hover:text-white"
    end
  end

  defp workspace_sections do
    [
      {:invoices, "/invoices"},
      {:contracts, "/contracts"},
      {:acts, "/acts"},
      {:buyers, "/buyers"},
      {:company, "/company"}
    ]
  end

  defp admin_sections do
    [
      {:clients, "/admin/billing/clients", "Clients"},
      {:billing_invoices, "/admin/billing/invoices", "Billing invoices"}
    ]
  end

  defp admin_section_active?(:billing_invoices, current_path) do
    String.starts_with?(current_path, "/admin/billing/invoices")
  end

  defp admin_section_active?(:clients, current_path) do
    current_path in ["/admin", "/admin/billing"] or
      String.starts_with?(current_path, "/admin/billing/clients")
  end

  defp public_mobile_cta("/login"), do: %{path: "/signup", label: gettext("Sign Up")}
  defp public_mobile_cta("/signup"), do: %{path: "/login", label: gettext("Sign In")}
  defp public_mobile_cta(_current_path), do: %{path: "/signup", label: gettext("Sign Up")}

  defp locale_path(locale, current_path) do
    "/locale/#{locale}?return_to=#{URI.encode_www_form(current_path)}"
  end
end
