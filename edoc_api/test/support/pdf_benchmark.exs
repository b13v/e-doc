#!/usr/bin/env elixir

# PDF Performance Benchmark Script
#
# Usage:
#   mix run test/support/pdf_benchmark.exs
#
# This script benchmarks PDF generation for large documents.

# Start the app if not already running
Application.ensure_all_started(:edoc_api)

alias EdocApi.{Core, Invoicing, Acts}
alias EdocApiWeb.PdfTemplates
alias EdocApi.Documents.{ContractPdf, InvoicePdf, ActPdf}

require Logger

defmodule PdfBenchmark do
  @moduledoc false

  @doc """
  Benchmark PDF generation for a contract with 100 items.
  """
  def benchmark_contract(user_id, _company_id, buyer_id, item_count \\ 100) do
    Logger.info("Creating contract with #{item_count} items...")

    # Create a contract with many items
    items =
      Enum.map(1..item_count, fn i ->
        %{
          name: "Товар #{i}",
          unit: "шт",
          qty: :rand.uniform(10),
          unit_price: :rand.uniform(10000) / 100,
          vat_rate: 12
        }
      end)

    contract_attrs = %{
      buyer_id: buyer_id,
      number: "TEST-#{System.unique_integer()}",
      issue_date: Date.utc_today()
    }

    {:ok, contract} = Core.create_contract_for_user(user_id, contract_attrs, items)

    # Contract is already preloaded from create_contract_for_user

    # Benchmark HTML rendering
    {html_time, html} = :timer.tc(fn -> PdfTemplates.contract_html(contract) end)
    html_ms = html_time / 1000
    Logger.info("HTML rendering: #{Float.round(html_ms, 2)}ms")

    # Benchmark PDF generation
    {pdf_time, result} = :timer.tc(fn -> ContractPdf.render(html) end)
    pdf_ms = pdf_time / 1000

    case result do
      {:ok, pdf_binary} ->
        pdf_size_kb = byte_size(pdf_binary) / 1024
        Logger.info("PDF generation: #{Float.round(pdf_ms, 2)}ms")
        Logger.info("PDF size: #{Float.round(pdf_size_kb, 2)}KB")
        Logger.info("Total: #{Float.round(html_ms + pdf_ms, 2)}ms")

        # Get memory info
        memory_info = :erlang.memory()
        total_mb = memory_info[:total] / 1_048_576
        process_mb = memory_info[:processes] / 1_048_576
        system_mb = memory_info[:system] / 1_048_576

        Logger.info(
          "Memory: total=#{Float.round(total_mb, 2)}MB, processes=#{Float.round(process_mb, 2)}MB, system=#{Float.round(system_mb, 2)}MB"
        )

        %{
          status: :success,
          item_count: item_count,
          html_time_ms: html_ms,
          pdf_time_ms: pdf_ms,
          total_time_ms: html_ms + pdf_ms,
          pdf_size_kb: pdf_size_kb,
          memory_total_mb: total_mb,
          memory_processes_mb: process_mb,
          memory_system_mb: system_mb,
          meets_threshold: html_ms + pdf_ms < 5000
        }

      {:error, reason} ->
        Logger.error("PDF generation failed: #{inspect(reason)}")
        %{status: :error, reason: reason}
    end
  end

  @doc """
  Benchmark PDF generation for an invoice with 100 items.
  """
  def benchmark_invoice(user_id, company_id, buyer, item_count \\ 100) do
    Logger.info("Creating invoice with #{item_count} items...")

    # Create an invoice with many items
    items =
      Enum.map(1..item_count, fn i ->
        %{
          name: "Товар #{i}",
          unit: "шт",
          qty: :rand.uniform(10),
          unit_price: :rand.uniform(10000) / 100,
          vat_rate: 12
        }
      end)

    invoice_attrs = %{
      "service_name" => "Benchmark Services",
      "issue_date" => Date.utc_today(),
      "currency" => "KZT",
      "buyer_name" => buyer.name,
      "buyer_bin_iin" => buyer.bin_iin,
      "buyer_address" => buyer.address || "Buyer Address",
      "vat_rate" => 12,
      "items" => items
    }

    {:ok, invoice} = Invoicing.create_invoice_for_user(user_id, company_id, invoice_attrs)

    # Invoice should already be preloaded

    # Benchmark HTML rendering
    {html_time, html} = :timer.tc(fn -> PdfTemplates.invoice_html(invoice) end)
    html_ms = html_time / 1000
    Logger.info("HTML rendering: #{Float.round(html_ms, 2)}ms")

    # Benchmark PDF generation
    {pdf_time, result} = :timer.tc(fn -> InvoicePdf.render(html) end)
    pdf_ms = pdf_time / 1000

    case result do
      {:ok, pdf_binary} ->
        pdf_size_kb = byte_size(pdf_binary) / 1024
        Logger.info("PDF generation: #{Float.round(pdf_ms, 2)}ms")
        Logger.info("PDF size: #{Float.round(pdf_size_kb, 2)}KB")
        Logger.info("Total: #{Float.round(html_ms + pdf_ms, 2)}ms")

        %{
          status: :success,
          item_count: item_count,
          html_time_ms: html_ms,
          pdf_time_ms: pdf_ms,
          total_time_ms: html_ms + pdf_ms,
          pdf_size_kb: pdf_size_kb,
          meets_threshold: html_ms + pdf_ms < 5000
        }

      {:error, reason} ->
        Logger.error("PDF generation failed: #{inspect(reason)}")
        %{status: :error, reason: reason}
    end
  end

  @doc """
  Benchmark PDF generation for an act with 100 items.
  """
  def benchmark_act(user_id, company_id, contract_id, item_count \\ 100) do
    Logger.info("Creating act with #{item_count} items...")

    # Create an act with many items
    items =
      Enum.map(1..item_count, fn i ->
        %{
          name: "Товар/Услуга #{i}",
          unit: "шт",
          qty: :rand.uniform(10),
          unit_price: :rand.uniform(10000) / 100,
          vat_rate: 12
        }
      end)

    act_attrs = %{
      "contract_id" => contract_id,
      "issue_date" => Date.utc_today(),
      "items" => items
    }

    {:ok, act} = Acts.create_act_for_user(user_id, company_id, act_attrs)

    # Act should already be preloaded

    # Benchmark HTML rendering
    {html_time, html} = :timer.tc(fn -> PdfTemplates.act_html(act) end)
    html_ms = html_time / 1000
    Logger.info("HTML rendering: #{Float.round(html_ms, 2)}ms")

    # Benchmark PDF generation
    {pdf_time, result} = :timer.tc(fn -> ActPdf.render(html) end)
    pdf_ms = pdf_time / 1000

    case result do
      {:ok, pdf_binary} ->
        pdf_size_kb = byte_size(pdf_binary) / 1024
        Logger.info("PDF generation: #{Float.round(pdf_ms, 2)}ms")
        Logger.info("PDF size: #{Float.round(pdf_size_kb, 2)}KB")
        Logger.info("Total: #{Float.round(html_ms + pdf_ms, 2)}ms")

        %{
          status: :success,
          item_count: item_count,
          html_time_ms: html_ms,
          pdf_time_ms: pdf_ms,
          total_time_ms: html_ms + pdf_ms,
          pdf_size_kb: pdf_size_kb,
          meets_threshold: html_ms + pdf_ms < 5000
        }

      {:error, reason} ->
        Logger.error("PDF generation failed: #{inspect(reason)}")
        %{status: :error, reason: reason}
    end
  end

  @doc """
  Run all benchmarks with warmup.
  """
  def run_all do
    Logger.info("=== PDF Performance Benchmark ===")
    Logger.info("Threshold: < 5000ms for 100 items")

    # Create test user
    user = create_test_user()

    if is_nil(user) do
      Logger.error("Failed to create test user.")
      exit(:shutdown)
    end

    Logger.info("Using test user: #{user.email}")

    # Create test company and buyer
    Logger.info("Creating test company and buyer...")

    {:ok, company, _warnings} =
      EdocApi.Companies.upsert_company_for_user(user.id, %{
        name: "PDF Benchmark Company",
        bin_iin: "060215385673",
        legal_form: "Товарищество с ограниченной ответственностью",
        city: "Almaty",
        address: "Test Address",
        phone: "+7 (777) 123 45 67",
        representative_name: "Test Director",
        representative_title: "Director",
        basis: "Charter",
        email: "benchmark@example.com"
      })

    # Ensure company has a bank account (required for invoices)
    ensure_company_bank_account(company)

    {:ok, buyer} =
      EdocApi.Buyers.create_buyer_for_company(company.id, %{
        name: "PDF Benchmark Buyer",
        bin_iin: "060215385673",
        legal_address: "Buyer Address, Almaty"
      })

    # Warmup - generate a small PDF first
    Logger.info("\n--- Warmup ---")
    benchmark_contract(user.id, company.id, buyer.id, 5)

    # Run benchmarks
    Logger.info("\n=== Contract Benchmark (100 items) ===")
    contract_result = benchmark_contract(user.id, company.id, buyer.id, 100)

    Logger.info("\n=== Invoice Benchmark (100 items) ===")
    invoice_result = benchmark_invoice(user.id, company.id, buyer, 100)

    # For act, we need a contract first
    {:ok, contract} =
      EdocApi.Core.create_contract_for_user(
        user.id,
        %{
          buyer_id: buyer.id,
          number: "ACT-TEST-#{System.unique_integer()}",
          issue_date: Date.utc_today()
        },
        [%{name: "Test", unit: "шт", qty: 1, unit_price: 100, vat_rate: 12}]
      )

    Logger.info("\n=== Act Benchmark (100 items) ===")
    act_result = benchmark_act(user.id, company.id, contract.id, 100)

    # Summary
    Logger.info("\n=== Summary ===")
    print_result("Contract", contract_result)
    print_result("Invoice", invoice_result)
    print_result("Act", act_result)

    all_pass =
      contract_result[:meets_threshold] and
        invoice_result[:meets_threshold] and
        act_result[:meets_threshold]

    if all_pass do
      Logger.info("✅ All benchmarks PASSED (< 5000ms)")
    else
      Logger.warning("⚠️ Some benchmarks FAILED (> 5000ms)")
    end

    all_pass
  end

  defp print_result(name, result) do
    if result[:status] == :success do
      status = if result[:meets_threshold], do: "✅ PASS", else: "⚠️ FAIL"
      Logger.info("#{name}: #{Float.round(result[:total_time_ms], 2)}ms #{status}")
    else
      Logger.error("#{name}: FAILED - #{inspect(result[:reason])}")
    end
  end

  defp create_test_user do
    alias EdocApi.Accounts
    alias EdocApi.{Repo, Companies, Buyers}
    import Ecto.Query

    email = "pdf_benchmark_#{System.unique_integer([:positive])}@example.com"

    attrs = %{
      "email" => email,
      "password" => "TestPassword123!",
      "legal_terms_accepted" => "true"
    }

    case Accounts.register_user(attrs) do
      {:ok, user} ->
        Logger.info("Created test user: #{email}")
        user

      {:error, _changeset} ->
        # User might already exist from previous run, try to find an existing user
        case Accounts.User |> limit(1) |> Repo.one() do
          nil ->
            Logger.error("Failed to create user and no existing users found")
            nil

          user ->
            Logger.info("Using existing user: #{user.email}")
            user
        end
    end
  end

  defp ensure_company_bank_account(company) do
    alias EdocApi.{Repo, Core}
    import Ecto.Query

    # Check if company has a default bank account
    existing =
      Core.CompanyBankAccount
      |> where([a], a.company_id == ^company.id and a.is_default == true)
      |> Repo.one()

    if existing do
      :ok
    else
      # Create a bank first
      suffix = Integer.to_string(System.unique_integer([:positive]))
      bic = "BIC#{String.slice(suffix, 0, 8)}"
      bank = Repo.insert!(%Core.Bank{name: "Benchmark Bank #{suffix}", bic: bic})

      # Create KBE code
      kbe_code =
        System.unique_integer([:positive])
        |> rem(100)
        |> Integer.to_string()
        |> String.pad_leading(2, "0")

      kbe =
        case Repo.get_by(Core.KbeCode, code: kbe_code) do
          nil -> Repo.insert!(%Core.KbeCode{code: kbe_code, description: "KBE #{kbe_code}"})
          existing -> existing
        end

      # Create KNP code
      knp_code =
        System.unique_integer([:positive])
        |> rem(1000)
        |> Integer.to_string()
        |> String.pad_leading(3, "0")

      knp =
        case Repo.get_by(Core.KnpCode, code: knp_code) do
          nil -> Repo.insert!(%Core.KnpCode{code: knp_code, description: "KNP #{knp_code}"})
          existing -> existing
        end

      # Create bank account
      Repo.insert!(%Core.CompanyBankAccount{
        company_id: company.id,
        bank_id: bank.id,
        kbe_code_id: kbe.id,
        knp_code_id: knp.id,
        label: "Default Account",
        iban: "KZ#{System.unique_integer()}#{String.duplicate("0", 20)}",
        is_default: true
      })

      :ok
    end
  end
end

# Run benchmarks
PdfBenchmark.run_all()
