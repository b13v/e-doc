import Config

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: EdocApi.Finch

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Secure cookies in production
config :edoc_api, :secure_cookies, true

# Configure Oban for background jobs in production
config :edoc_api, Oban,
  repo: EdocApi.Repo,
  queues: [default: 10, pdf_generation: 5, billing: 1],
  plugins: [
    Oban.Plugins.Pruner,
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", EdocApi.ObanWorkers.BillingLifecycleWorker,
        args: %{"action" => "generate_renewal_invoices"}},
       {"15 3 * * *", EdocApi.ObanWorkers.BillingLifecycleWorker,
        args: %{"action" => "process_overdue_billing"}},
       {"30 3 * * *", EdocApi.ObanWorkers.BillingLifecycleWorker,
        args: %{"action" => "process_grace_expirations"}},
       {"45 3 * * *", EdocApi.ObanWorkers.BillingLifecycleWorker,
        args: %{"action" => "send_billing_reminders"}}
     ]}
  ]

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
