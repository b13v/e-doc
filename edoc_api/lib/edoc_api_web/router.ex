defmodule EdocApiWeb.Router do
  use EdocApiWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(EdocApiWeb.Plugs.ApiVersion, version: "v1")
  end

  pipeline :auth_api do
    plug(:accepts, ["json", "pdf"])
    plug(EdocApiWeb.Plugs.Authenticate)
    plug(EdocApiWeb.Plugs.ValidateUuid)
  end

  pipeline :auth_credentials_rate_limit do
    plug(EdocApiWeb.Plugs.RateLimit,
      limit: 5,
      window_seconds: 60,
      action: "auth_credentials",
      subject: :ip
    )
  end

  pipeline :auth_verify_rate_limit do
    plug(EdocApiWeb.Plugs.RateLimit,
      limit: 20,
      window_seconds: 60,
      action: "auth_verify",
      subject: :ip
    )
  end

  pipeline :auth_resend_rate_limit do
    plug(EdocApiWeb.Plugs.RateLimit,
      limit: 5,
      window_seconds: 60,
      action: "auth_resend_verification",
      subject: :ip
    )
  end

  pipeline :auth_refresh_rate_limit do
    plug(EdocApiWeb.Plugs.RateLimit,
      limit: 10,
      window_seconds: 60,
      action: "auth_refresh",
      subject: :ip
    )
  end

  pipeline :password_reset_rate_limit do
    plug(EdocApiWeb.Plugs.RateLimit,
      limit: 5,
      window_seconds: 60,
      action: "password_reset_request",
      subject: :ip
    )
  end

  pipeline :api_mutation_rate_limit do
    plug(EdocApiWeb.Plugs.RateLimit,
      limit: 30,
      window_seconds: 60,
      action: "api_mutation",
      subject: :user_or_ip
    )
  end

  pipeline :api_pdf_rate_limit do
    plug(EdocApiWeb.Plugs.RateLimit,
      limit: 10,
      window_seconds: 60,
      action: "api_pdf",
      subject: :user_or_ip
    )
  end

  pipeline :public_document do
    plug(:accepts, ["html", "pdf"])

    plug(EdocApiWeb.Plugs.RateLimit,
      limit: 30,
      window_seconds: 60,
      action: "public_document",
      subject: :ip
    )
  end

  # HTML/htmx pipelines
  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(EdocApiWeb.Plugs.SetLocale)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(EdocApiWeb.Plugs.HtmxDetect)
    plug(EdocApiWeb.Plugs.HtmxLayout)
  end

  pipeline :auth_browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(EdocApiWeb.Plugs.SetLocale)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(EdocApiWeb.Plugs.HtmxDetect)
    plug(EdocApiWeb.Plugs.AuthenticateSession)
    plug(EdocApiWeb.Plugs.NoStoreBrowserCache)
    plug(EdocApiWeb.Plugs.HtmxLayout)
  end

  pipeline :platform_admin_browser do
    plug(EdocApiWeb.Plugs.RequirePlatformAdmin)
  end

  pipeline :auth_browser_json do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(EdocApiWeb.Plugs.AuthenticateSession)
  end

  # Public API
  scope "/v1", EdocApiWeb do
    pipe_through(:api)

    get("/health", HealthController, :index)
  end

  scope "/v1", EdocApiWeb do
    pipe_through([:api, :auth_verify_rate_limit])

    get("/auth/verify", AuthController, :verify_email)
  end

  scope "/v1", EdocApiWeb do
    pipe_through([:api, :auth_resend_rate_limit])

    post("/auth/resend-verification", AuthController, :resend_verification)
  end

  scope "/v1", EdocApiWeb do
    pipe_through([:api, :auth_credentials_rate_limit])

    post("/auth/signup", AuthController, :signup)
    post("/auth/login", AuthController, :login)
  end

  scope "/v1", EdocApiWeb do
    pipe_through([:api, :auth_refresh_rate_limit])

    post("/auth/refresh", AuthController, :refresh)
  end

  # Protected API (JWT required) - read operations
  scope "/v1", EdocApiWeb do
    pipe_through(:auth_api)

    get("/auth/status", AuthController, :auth_status)
    get("/company", CompanyController, :show)
    get("/buyers", BuyersController, :index)
    get("/buyers/:id", BuyersController, :show)
    get("/invoices", InvoiceController, :index)
    get("/invoices/:id", InvoiceController, :show)
    get("/contracts", ContractController, :index)
    get("/contracts/:id", ContractController, :show)
    get("/dicts/banks", DictController, :banks)
    get("/dicts/kbe", DictController, :kbe)
    get("/dicts/knp", DictController, :knp)
    get("/company/bank-accounts", CompanyBankAccountController, :index)
  end

  # Protected API (JWT required) - mutating operations
  scope "/v1", EdocApiWeb do
    pipe_through([:auth_api, :api_mutation_rate_limit])

    put("/company", CompanyController, :upsert)
    put("/company/subscription", CompanyController, :update_subscription)
    post("/buyers", BuyersController, :create)
    put("/buyers/:id", BuyersController, :update)
    delete("/buyers/:id", BuyersController, :delete)
    post("/invoices", InvoiceController, :create)
    put("/invoices/:id", InvoiceController, :update)
    post("/contracts", ContractController, :create)
    post("/contracts/:id/issue", ContractController, :issue)
    post("/contracts/:id/sign", ContractController, :sign)
    post("/invoices/:id/issue", InvoiceController, :issue)
    post("/invoices/:id/pay", InvoiceController, :pay)
    post("/documents/:type/:id/send-email", DocumentDeliveryController, :send_email)
    post("/documents/:type/:id/share/:channel", DocumentDeliveryController, :share)
    post("/company/bank-accounts", CompanyBankAccountController, :create)
    put("/company/bank-accounts/:id/set-default", CompanyBankAccountController, :set_default)
  end

  # Protected API (JWT required) - expensive PDF operations
  scope "/v1", EdocApiWeb do
    pipe_through([:auth_api, :api_pdf_rate_limit])

    get("/contracts/:id/pdf", ContractController, :pdf)
    get("/contracts/:id/pdf/status", ContractController, :pdf_status)
    get("/invoices/:id/pdf", InvoiceController, :pdf)
    get("/invoices/:id/pdf/status", InvoiceController, :pdf_status)
  end

  # HTML/htmx UI routes
  scope "/", EdocApiWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
    get("/locale/:locale", LocaleController, :update)
    get("/about", AboutController, :index)
    get("/login", SessionController, :new)
    get("/password/forgot", PasswordResetController, :new)
    get("/password/reset", PasswordResetController, :edit)
    post("/login", SessionController, :create)
    delete("/logout", SessionController, :delete)
    get("/signup", SignupController, :new)
    post("/signup", SignupController, :create)
    get("/verify-email-pending", VerificationPendingController, :new)
    get("/verify-email", VerificationPendingController, :verify)
  end

  scope "/", EdocApiWeb do
    pipe_through([:browser, :password_reset_rate_limit])

    post("/password/forgot", PasswordResetController, :create)
  end

  scope "/", EdocApiWeb do
    pipe_through(:browser)

    post("/password/reset", PasswordResetController, :update)
  end

  scope "/", EdocApiWeb do
    pipe_through(:auth_browser)

    get("/documents/:type/:id/send/email", DocumentDeliveryHTMLController, :email_form)
    post("/documents/:type/:id/send/email", DocumentDeliveryHTMLController, :send_email)
    post("/documents/:type/:id/share/:channel", DocumentDeliveryHTMLController, :share)
    get("/invoices", InvoicesController, :index)
    get("/invoices/new", InvoicesController, :new)
    get("/invoices/overdue", InvoicesController, :overdue)
    post("/invoices", InvoicesController, :create)
    get("/invoices/:id", InvoicesController, :show)
    get("/invoices/:id/edit", InvoicesController, :edit)
    put("/invoices/:id", InvoicesController, :update)
    get("/invoices/:id/pdf", InvoicesController, :pdf)
    post("/invoices/:id/issue", InvoicesController, :issue)
    post("/invoices/:id/pay", InvoicesController, :pay)
    delete("/invoices/:id", InvoicesController, :delete)
    get("/acts", ActsController, :index)
    get("/acts/new", ActsController, :new)
    post("/acts", ActsController, :create)
    get("/acts/:id", ActsController, :show)
    get("/acts/:id/edit", ActsController, :edit)
    put("/acts/:id", ActsController, :update)
    get("/acts/:id/pdf", ActsController, :pdf)
    post("/acts/:id/issue", ActsController, :issue)
    post("/acts/:id/sign", ActsController, :sign)
    delete("/acts/:id", ActsController, :delete)
    get("/invoices/from-contract/:contract_id", InvoicesController, :create_from_contract)
    post("/invoices/from-contract/:contract_id", InvoicesController, :create_from_contract)
    get("/contracts", ContractHTMLController, :index)
    get("/contracts/new", ContractHTMLController, :new)
    post("/contracts", ContractHTMLController, :create)
    get("/contracts/:id", ContractHTMLController, :show)
    get("/contracts/:id/edit", ContractHTMLController, :edit)
    put("/contracts/:id", ContractHTMLController, :update)
    delete("/contracts/:id", ContractHTMLController, :delete)
    get("/contracts/:id/pdf", ContractHTMLController, :pdf)
    post("/contracts/:id/issue", ContractHTMLController, :issue)
    post("/contracts/:id/sign", ContractHTMLController, :sign)

    # Buyer management routes
    get("/buyers", BuyerHTMLController, :index)
    get("/buyers/new", BuyerHTMLController, :new)
    get("/buyers/:id", BuyerHTMLController, :show)
    post("/buyers", BuyerHTMLController, :create)
    get("/buyers/:id/edit", BuyerHTMLController, :edit)
    put("/buyers/:id", BuyerHTMLController, :update)
    delete("/buyers/:id", BuyerHTMLController, :delete)

    # Company management routes
    get("/company/setup", CompaniesController, :setup)
    post("/company/setup", CompaniesController, :create_setup)
    get("/company", CompaniesController, :edit)
    get("/company/billing", BillingHTMLController, :show)
    post("/company/billing/upgrade-invoices", BillingHTMLController, :create_upgrade_invoice)
    post("/company/billing/invoices/:id/payments", BillingHTMLController, :create_payment)
    get("/settings", SettingsController, :edit)
    put("/settings/profile", SettingsController, :update_profile)
    put("/settings/password", SettingsController, :update_password)
    put("/company", CompaniesController, :update)
    post("/company/subscription", CompaniesController, :update_subscription)
    post("/company/memberships", CompaniesController, :invite_member)
    delete("/company/memberships/:id", CompaniesController, :remove_member)
    post("/company/bank-accounts", CompaniesController, :add_bank_account)
    get("/company/bank-accounts/:id", CompanyBankAccountHTMLController, :show)
    get("/company/bank-accounts/:id/edit", CompanyBankAccountHTMLController, :edit)
    put("/company/bank-accounts/:id", CompanyBankAccountHTMLController, :update)
    put("/company/bank-accounts/:id/set-default", CompaniesController, :set_default_bank_account)
    delete("/company/bank-accounts/:id", CompaniesController, :delete_bank_account)
  end

  scope "/admin", EdocApiWeb do
    pipe_through([:auth_browser, :platform_admin_browser])

    get("/", AdminBillingController, :index)
    get("/billing", AdminBillingController, :index)
    get("/billing/clients", AdminBillingController, :clients)
    get("/billing/clients/:id", AdminBillingController, :client)
    post("/billing/clients/:id/notes", AdminBillingController, :add_note)
    get("/billing/invoices", AdminBillingController, :invoices)
    post("/billing/invoices/:id/send", AdminBillingController, :send_invoice)
    post("/billing/invoices/:id/payments", AdminBillingController, :create_payment)
    post("/billing/payments/:id/confirm", AdminBillingController, :confirm_payment)
    post("/billing/payments/:id/reject", AdminBillingController, :reject_payment)

    post(
      "/billing/subscriptions/:id/renewal-invoices",
      AdminBillingController,
      :create_renewal_invoice
    )

    post(
      "/billing/subscriptions/:id/upgrade-invoices",
      AdminBillingController,
      :create_upgrade_invoice
    )

    post("/billing/subscriptions/:id/suspend", AdminBillingController, :suspend_subscription)

    post(
      "/billing/subscriptions/:id/reactivate",
      AdminBillingController,
      :reactivate_subscription
    )

    post("/billing/subscriptions/:id/grace-period", AdminBillingController, :extend_grace_period)
    post("/billing/subscriptions/:id/schedule-upgrade", AdminBillingController, :schedule_upgrade)

    post(
      "/billing/subscriptions/:id/schedule-change",
      AdminBillingController,
      :schedule_plan_change
    )
  end

  scope "/", EdocApiWeb do
    pipe_through(:auth_browser_json)

    get("/contracts/:id/prefill", ContractHTMLController, :prefill)
  end

  scope "/", EdocApiWeb do
    pipe_through(:public_document)

    get("/public/docs/:token", PublicDocumentController, :show)
    get("/public/docs/:token/pdf", PublicDocumentController, :pdf)
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:edoc_api, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through([:fetch_session, :protect_from_forgery])

      live_dashboard("/dashboard", metrics: EdocApiWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
