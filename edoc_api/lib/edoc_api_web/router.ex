defmodule EdocApiWeb.Router do
  use EdocApiWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :auth_api do
    plug(:accepts, ["json", "pdf"])
    plug(EdocApiWeb.Plugs.Authenticate)
  end

  # HTML/htmx pipelines
  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(EdocApiWeb.Plugs.HtmxDetect)
    plug(EdocApiWeb.Plugs.HtmxLayout)
  end

  pipeline :auth_browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(EdocApiWeb.Plugs.HtmxDetect)
    plug(EdocApiWeb.Plugs.AuthenticateSession)
    plug(EdocApiWeb.Plugs.HtmxLayout)
  end

  # Public API
  scope "/v1", EdocApiWeb do
    pipe_through(:api)

    get("/health", HealthController, :index)

    post("/auth/signup", AuthController, :signup)
    post("/auth/login", AuthController, :login)
    get("/auth/verify", AuthController, :verify_email)
    post("/auth/resend-verification", AuthController, :resend_verification)
    get("/auth/status", AuthController, :auth_status)
  end

  # Protected API (JWT required)
  scope "/v1", EdocApiWeb do
    pipe_through(:auth_api)

    get("/company", CompanyController, :show)
    put("/company", CompanyController, :upsert)
    get("/buyers", BuyersController, :index)
    get("/buyers/:id", BuyersController, :show)
    post("/buyers", BuyersController, :create)
    put("/buyers/:id", BuyersController, :update)
    delete("/buyers/:id", BuyersController, :delete)
    get("/invoices", InvoiceController, :index)
    post("/invoices", InvoiceController, :create)
    get("/invoices/:id", InvoiceController, :show)
    put("/invoices/:id", InvoiceController, :update)
    get("/contracts", ContractController, :index)
    post("/contracts", ContractController, :create)
    get("/contracts/:id", ContractController, :show)
    get("/contracts/:id/pdf", ContractController, :pdf)
    post("/contracts/:id/issue", ContractController, :issue)

    get("/invoices/:id/pdf", InvoiceController, :pdf)
    post("/invoices/:id/issue", InvoiceController, :issue)
    # get "/invoices/:id/pdf/download", InvoiceController, :download_pdf
    get("/dicts/banks", DictController, :banks)
    get("/dicts/kbe", DictController, :kbe)
    get("/dicts/knp", DictController, :knp)
    get("/company/bank-accounts", CompanyBankAccountController, :index)
    post("/company/bank-accounts", CompanyBankAccountController, :create)
    put("/company/bank-accounts/:id/set-default", CompanyBankAccountController, :set_default)
  end

  # HTML/htmx UI routes
  scope "/", EdocApiWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
    get("/about", AboutController, :index)
    get("/login", SessionController, :new)
    post("/login", SessionController, :create)
    delete("/logout", SessionController, :delete)
    get("/signup", SignupController, :new)
    post("/signup", SignupController, :create)
    get("/verify-email-pending", VerificationPendingController, :new)
    get("/verify-email", VerificationPendingController, :verify)
  end

  scope "/", EdocApiWeb do
    pipe_through(:auth_browser)

    get("/invoices", InvoicesController, :index)
    get("/invoices/new", InvoicesController, :new)
    post("/invoices", InvoicesController, :create)
    get("/invoices/:id", InvoicesController, :show)
    get("/invoices/:id/edit", InvoicesController, :edit)
    put("/invoices/:id", InvoicesController, :update)
    get("/invoices/:id/pdf", InvoicesController, :pdf)
    post("/invoices/:id/issue", InvoicesController, :issue)
    delete("/invoices/:id", InvoicesController, :delete)
    post("/invoices/from-contract/:contract_id", InvoicesController, :create_from_contract)
    get("/contracts", ContractHTMLController, :index)
    get("/contracts/new", ContractHTMLController, :new)
    post("/contracts", ContractHTMLController, :create)
    get("/contracts/:id", ContractHTMLController, :show)
    get("/contracts/:id/edit", ContractHTMLController, :edit)
    put("/contracts/:id", ContractHTMLController, :update)
    get("/contracts/:id/pdf", ContractHTMLController, :pdf)
    post("/contracts/:id/issue", ContractHTMLController, :issue)

    # Buyer management routes
    get("/buyers", BuyerHTMLController, :index)
    get("/buyers/new", BuyerHTMLController, :new)
    post("/buyers", BuyerHTMLController, :create)
    get("/buyers/:id/edit", BuyerHTMLController, :edit)
    put("/buyers/:id", BuyerHTMLController, :update)
    delete("/buyers/:id", BuyerHTMLController, :delete)

    # Company management routes
    get("/company/setup", CompaniesController, :setup)
    post("/company/setup", CompaniesController, :create_setup)
    get("/company", CompaniesController, :edit)
    put("/company", CompaniesController, :update)
    post("/company/bank-accounts", CompaniesController, :add_bank_account)
    put("/company/bank-accounts/:id/set-default", CompaniesController, :set_default_bank_account)
    delete("/company/bank-accounts/:id", CompaniesController, :delete_bank_account)
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
