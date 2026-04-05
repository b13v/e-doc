defmodule EdocApi.Invoicing do
  import Ecto.Query, warn: false
  require Logger

  alias EdocApi.Repo
  alias EdocApi.RepoHelpers
  alias EdocApi.Errors
  alias EdocApi.Currencies
  alias EdocApi.Companies
  alias EdocApi.Monetization
  alias EdocApi.Payments
  alias EdocApi.Core.Company
  alias EdocApi.Core.Contract
  alias EdocApi.Core.Invoice
  alias EdocApi.Core.InvoiceBankSnapshot
  alias EdocApi.Core.InvoiceItem
  alias EdocApi.Core.InvoiceCounter
  alias EdocApi.Core.InvoiceRecycledNumber
  alias EdocApi.Core.CompanyBankAccount
  alias EdocApi.InvoiceStatus
  alias EdocApi.ContractStatus

  def get_invoice_for_user(user_id, invoice_id) do
    Invoice
    |> where([i], i.id == ^invoice_id and i.user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil -> nil
      invoice -> preload_invoice(invoice)
    end
  end

  def list_issued_contracts_for_user(user_id) when is_binary(user_id) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        []

      %Company{id: company_id} ->
        Contract
        |> where([c], c.company_id == ^company_id and c.status == "issued")
        |> order_by([c], desc: c.inserted_at)
        |> Repo.all()
        |> Repo.preload([:buyer])
    end
  end

  def get_issued_contract_for_user(user_id, contract_id)
      when is_binary(user_id) and is_binary(contract_id) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        {:error, :company_required}

      %Company{id: company_id} ->
        Contract
        |> where(
          [c],
          c.company_id == ^company_id and c.id == ^contract_id and c.status == "issued"
        )
        |> Repo.one()
        |> case do
          nil ->
            {:error, :not_found}

          contract ->
            {:ok, Repo.preload(contract, [:buyer, :contract_items, :bank_account])}
        end
    end
  end

  def build_invoice_from_contract(user_id, contract_id)
      when is_binary(user_id) and is_binary(contract_id) do
    with {:ok, contract} <- get_issued_contract_for_user(user_id, contract_id) do
      bank_accounts = Payments.list_company_bank_accounts_for_user(user_id)
      selected_bank_account_id = resolve_contract_bank_account_id(contract, bank_accounts)

      buyer = contract.buyer

      prefill_items =
        Enum.map(contract.contract_items || [], fn item ->
          %{
            "code" => item.code || "",
            "name" => item.name || "",
            "qty" => normalize_qty_for_invoice(item.qty),
            "unit_price" => decimal_to_string(item.unit_price)
          }
        end)

      {:ok,
       %{
         selected_contract_id: contract.id,
         selected_buyer_id: buyer && buyer.id,
         selected_bank_account_id: selected_bank_account_id,
         buyer_address: (buyer && buyer.address) || "",
         prefill_items: prefill_items
       }}
    end
  end

  def list_invoices_for_user(user_id, opts \\ []) do
    Invoice
    |> where([i], i.user_id == ^user_id)
    |> order_by([i], desc: i.inserted_at)
    |> apply_pagination(opts)
    |> Repo.all()
    |> Repo.preload([
      :items,
      :bank_snapshot,
      :contract,
      :company,
      :kbe_code,
      :knp_code,
      bank_account: [:bank, :kbe_code, :knp_code]
    ])
  end

  def count_invoices_for_user(user_id) when is_binary(user_id) do
    Invoice
    |> where([i], i.user_id == ^user_id)
    |> Repo.aggregate(:count, :id)
  end

  def issue_invoice_for_user(user_id, invoice_id) do
    RepoHelpers.transaction(fn ->
      invoice =
        RepoHelpers.fetch_or_abort(
          from(i in Invoice, where: i.user_id == ^user_id and i.id == ^invoice_id),
          :invoice
        )

      invoice = preload_invoice(invoice)

      case do_issue_invoice(invoice) do
        {:ok, inv} ->
          case Monetization.consume_document_quota(
                 inv.company_id,
                 "invoice",
                 inv.id,
                 "invoice_issued"
               ) do
            {:ok, _quota} ->
              {:ok, inv}

            {:error, :quota_exceeded, details} ->
              RepoHelpers.abort({:business_rule, %{rule: :quota_exceeded, details: details}})
          end

        {:error, reason} ->
          RepoHelpers.abort({:business_rule, %{rule: reason}})

        {:error, reason, details} ->
          RepoHelpers.abort({:business_rule, %{rule: reason, details: details}})
      end
    end)
  end

  def pay_invoice_for_user(user_id, invoice_id) do
    RepoHelpers.transaction(fn ->
      invoice =
        RepoHelpers.fetch_or_abort(
          from(i in Invoice, where: i.user_id == ^user_id and i.id == ^invoice_id),
          :invoice
        )
        |> preload_invoice()

      cond do
        InvoiceStatus.is_paid?(invoice) ->
          RepoHelpers.abort(
            {:business_rule, %{rule: :already_paid, details: %{invoice_id: invoice.id}}}
          )

        not InvoiceStatus.is_issued?(invoice) ->
          RepoHelpers.abort(
            {:business_rule,
             %{
               rule: :cannot_mark_paid,
               details: %{invoice_id: invoice.id, status: invoice.status}
             }}
          )

        not contract_ready_for_progression?(invoice) ->
          RepoHelpers.abort(
            {:business_rule,
             %{
               rule: :contract_must_be_signed_to_pay_invoice,
               details: contract_progression_details(invoice)
             }}
          )

        true ->
          case update_invoice_status(invoice, InvoiceStatus.paid()) do
            {:ok, inv} ->
              {:ok, preload_invoice(inv)}

            {:error, %Ecto.Changeset{} = changeset} ->
              RepoHelpers.abort({:validation, %{changeset: changeset}})
          end
      end
    end)
  end

  def create_invoice_for_user(user_id, company_id, attrs) do
    items_attrs = normalize_items(Map.get(attrs, "items") || Map.get(attrs, :items) || [])

    bank_account_id =
      attrs
      |> fetch_optional_value("bank_account_id", :bank_account_id)
      |> normalize_blank_to_nil()

    kbe_code_id =
      attrs
      |> fetch_optional_value("kbe_code_id", :kbe_code_id)
      |> normalize_blank_to_nil()

    knp_code_id =
      attrs
      |> fetch_optional_value("knp_code_id", :knp_code_id)
      |> normalize_blank_to_nil()

    case Monetization.ensure_document_creation_allowed(company_id) do
      {:ok, _quota} ->
        RepoHelpers.transaction(fn ->
          RepoHelpers.check_or_abort(items_attrs != [], :items_required)

          {prepared_items, subtotal} = prepare_items_and_subtotal!(items_attrs)

          # ✅ AUTONUMBER: если number не передан — генерим только цифры
          raw_number = Map.get(attrs, "number") || Map.get(attrs, :number)

          number =
            cond do
              is_nil(raw_number) ->
                next_invoice_number!(company_id)

              is_binary(raw_number) and String.trim(raw_number) == "" ->
                next_invoice_number!(company_id)

              true ->
                raw_number
            end

          # ---- SELLER from Company / Bank Account -----
          company = Repo.get!(Company, company_id)

          # Get bank account (explicit or default)
          bank_account = get_bank_account_for_invoice(company_id, bank_account_id)

          bank_account = Repo.preload(bank_account, [:bank, :kbe_code, :knp_code])

          seller_attrs = %{
            "seller_name" => company.name,
            "seller_bin_iin" => company.bin_iin,
            "seller_address" => format_company_address(company),
            "seller_iban" => bank_account.iban
          }

          invoice_attrs =
            attrs
            |> Map.drop(["items", :items, "subtotal", :subtotal, "vat", :vat, "total", :total])
            |> Map.merge(seller_attrs)
            |> Map.put("subtotal", subtotal)
            |> Map.put("number", number)
            |> maybe_put_bank_account_id(bank_account)
            |> maybe_put_kbe_code_id(kbe_code_id || bank_account.kbe_code_id)
            |> maybe_put_knp_code_id(knp_code_id || bank_account.knp_code_id)

          invoice_changeset = Invoice.changeset(%Invoice{}, invoice_attrs, user_id, company_id)

          {:ok, invoice} = RepoHelpers.insert_or_abort(invoice_changeset)

          Enum.each(prepared_items, fn item_attrs ->
            cs =
              %InvoiceItem{}
              |> InvoiceItem.changeset(Map.put(item_attrs, "invoice_id", invoice.id))

            RepoHelpers.insert_or_abort(cs)
          end)

          {:ok, preload_invoice(invoice)}
        end)

      {:error, :quota_exceeded, details} ->
        {:error, :business_rule, %{rule: :quota_exceeded, details: details}}
    end
  end

  def contract_ready_for_progression?(%{contract_id: nil}), do: true
  def contract_ready_for_progression?(%{contract: %Contract{} = contract}), do: ContractStatus.is_signed?(contract)
  def contract_ready_for_progression?(%{contract_id: _contract_id}), do: false
  def contract_ready_for_progression?(_invoice), do: true

  def update_invoice_for_user(user_id, invoice_id, attrs) do
    RepoHelpers.transaction(fn ->
      invoice =
        RepoHelpers.fetch_or_abort(
          from(i in Invoice, where: i.user_id == ^user_id and i.id == ^invoice_id),
          :invoice
        )

      # Only allow updates on draft invoices
      unless InvoiceStatus.is_draft?(invoice) do
        RepoHelpers.abort(
          {:business_rule,
           %{rule: :invoice_already_issued, invoice_id: invoice.id, status: invoice.status}}
        )
      end

      items_attrs = normalize_items(Map.get(attrs, "items") || Map.get(attrs, :items) || [])

      bank_account_id =
        attrs
        |> fetch_optional_value("bank_account_id", :bank_account_id)
        |> normalize_blank_to_nil()

      kbe_code_id =
        attrs
        |> fetch_optional_value("kbe_code_id", :kbe_code_id)
        |> normalize_blank_to_nil()

      knp_code_id =
        attrs
        |> fetch_optional_value("knp_code_id", :knp_code_id)
        |> normalize_blank_to_nil()

      # Handle bank account if specified
      bank_account =
        case bank_account_id do
          nil -> nil
          _id -> get_bank_account_for_invoice(invoice.company_id, bank_account_id)
        end

      if bank_account_id && bank_account == nil do
        RepoHelpers.abort({:not_found, %{resource: :bank_account}})
      end

      # Handle items if provided
      new_subtotal =
        if items_attrs != [] do
          {prepared_items, subtotal} = prepare_items_and_subtotal!(items_attrs)

          # Delete existing items
          InvoiceItem
          |> where([ii], ii.invoice_id == ^invoice_id)
          |> Repo.delete_all()

          # Insert new items
          Enum.each(prepared_items, fn item_attrs ->
            cs =
              %InvoiceItem{}
              |> InvoiceItem.changeset(Map.put(item_attrs, "invoice_id", invoice.id))

            RepoHelpers.insert_or_abort(cs)
          end)

          subtotal
        end

      # Build changeset with original user_id and company_id
      invoice_attrs =
        attrs
        |> Map.drop(["items", :items, "subtotal", :subtotal, "vat", :vat, "total", :total])
        |> maybe_put_kbe_code_id(
          kbe_code_id || invoice.kbe_code_id || inferred_kbe_code_id(invoice, bank_account)
        )
        |> maybe_put_knp_code_id(
          knp_code_id || invoice.knp_code_id || inferred_knp_code_id(invoice, bank_account)
        )
        |> maybe_put_subtotal(new_subtotal)

      invoice_changeset =
        Invoice.changeset(invoice, invoice_attrs, user_id, invoice.company_id)

      {:ok, updated_invoice} = RepoHelpers.update_or_abort(invoice_changeset)
      {:ok, preload_invoice(updated_invoice)}
    end)
  end

  defp preload_invoice(invoice) do
    Repo.preload(invoice, [
      :items,
      :bank_snapshot,
      :company,
      :kbe_code,
      :knp_code,
      bank_account: [:bank, :kbe_code, :knp_code],
      contract: [:buyer]
    ])
  end

  defp get_bank_account_for_invoice(company_id, nil) do
    case CompanyBankAccount.get_default_account(company_id) do
      nil ->
        RepoHelpers.abort(
          {:business_rule, %{rule: :bank_account_required, company_id: company_id}}
        )

      acc ->
        acc
    end
  end

  defp get_bank_account_for_invoice(company_id, bank_account_id) do
    case Repo.get(CompanyBankAccount, bank_account_id) do
      %CompanyBankAccount{company_id: ^company_id} = acc ->
        acc

      _ ->
        RepoHelpers.abort(
          {:not_found,
           %{resource: :bank_account, company_id: company_id, bank_account_id: bank_account_id}}
        )
    end
  end

  defp apply_pagination(query, opts) do
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset)

    query =
      if is_integer(limit) do
        from(q in query, limit: ^limit)
      else
        query
      end

    if is_integer(offset) and offset > 0 do
      from(q in query, offset: ^offset)
    else
      query
    end
  end

  defp prepare_items_and_subtotal!(items_attrs) when is_list(items_attrs) do
    {items, subtotal} =
      Enum.reduce(items_attrs, {[], zero_decimal()}, fn raw, {acc, sum} ->
        m = normalize_map_keys(raw)

        qty = parse_int(Map.get(m, "qty", 1))
        unit_price = parse_decimal(Map.get(m, "unit_price"))

        amount =
          unit_price
          |> Decimal.mult(Decimal.new(qty))
          |> Currencies.round_default()

        item = %{
          "code" => Map.get(m, "code"),
          "name" => Map.get(m, "name"),
          "qty" => qty,
          "unit_price" => unit_price,
          "amount" => amount
        }

        {[item | acc], Decimal.add(sum, amount)}
      end)

    {Enum.reverse(items), Currencies.round_default(subtotal)}
  end

  defp normalize_map_keys(map) when is_map(map) do
    # поддержка atom keys и string keys
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  # Convert items from map format (from HTML forms) to list format
  # Handles: %{"0" => item1, "1" => item2} -> [item1, item2]
  # Also handles already-list format and filters out destroyed items
  defp normalize_items(items_attrs) when is_list(items_attrs), do: items_attrs

  defp normalize_items(items_attrs) when is_map(items_attrs) do
    items_attrs
    |> Map.values()
    |> Enum.reject(fn item ->
      # Skip items marked for destruction or empty items
      is_map(item) and (Map.get(item, "_destroy") == "true" or Map.get(item, :_destroy) == true)
    end)
  end

  defp normalize_items(_), do: []

  defp fetch_optional_value(attrs, string_key, atom_key) do
    case Map.get(attrs, string_key) do
      nil -> Map.get(attrs, atom_key)
      value -> value
    end
  end

  defp normalize_blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp normalize_blank_to_nil(value), do: value

  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> n
      _ -> 1
    end
  end

  defp parse_int(_), do: 1

  defp parse_decimal(%Decimal{} = d), do: d
  defp parse_decimal(v) when is_integer(v), do: Decimal.new(v)

  defp parse_decimal(v) when is_float(v),
    do: v |> :erlang.float_to_binary(decimals: Currencies.default_precision()) |> Decimal.new()

  defp parse_decimal(v) when is_binary(v) do
    v =
      v
      |> String.trim()
      |> String.replace(" ", "")
      # на случай "100 000,00"
      |> String.replace(",", ".")

    case Decimal.parse(v) do
      {d, ""} -> d
      _ -> Decimal.new("0.#{String.duplicate("0", Currencies.default_precision())}")
    end
  end

  defp parse_decimal(_), do: zero_decimal()

  defp maybe_put_subtotal(attrs, nil), do: attrs

  defp maybe_put_subtotal(attrs, %Decimal{} = subtotal),
    do: Map.put(attrs, "subtotal", Decimal.to_string(subtotal))

  defp maybe_put_bank_account_id(attrs, %CompanyBankAccount{id: id}),
    do: Map.put(attrs, "bank_account_id", id)

  defp maybe_put_kbe_code_id(attrs, nil), do: attrs
  defp maybe_put_kbe_code_id(attrs, id), do: Map.put(attrs, "kbe_code_id", id)

  defp maybe_put_knp_code_id(attrs, nil), do: attrs
  defp maybe_put_knp_code_id(attrs, id), do: Map.put(attrs, "knp_code_id", id)

  defp inferred_kbe_code_id(_invoice, %CompanyBankAccount{kbe_code_id: code_id}), do: code_id

  defp inferred_kbe_code_id(invoice, nil) do
    if invoice.bank_account_id do
      case Repo.get(CompanyBankAccount, invoice.bank_account_id) do
        %CompanyBankAccount{kbe_code_id: code_id} -> code_id
        _ -> nil
      end
    end
  end

  defp inferred_knp_code_id(_invoice, %CompanyBankAccount{knp_code_id: code_id}), do: code_id

  defp inferred_knp_code_id(invoice, nil) do
    if invoice.bank_account_id do
      case Repo.get(CompanyBankAccount, invoice.bank_account_id) do
        %CompanyBankAccount{knp_code_id: code_id} -> code_id
        _ -> nil
      end
    end
  end

  defp zero_decimal do
    Decimal.new("0.#{String.duplicate("0", Currencies.default_precision())}")
  end

  defp format_company_address(%Company{} = c) do
    city = (c.city || "") |> String.trim()
    addr = (c.address || "") |> String.trim()

    cond do
      city != "" and addr != "" -> "г. #{city}, #{addr}"
      addr != "" -> addr
      city != "" -> "г. #{city}"
      true -> ""
    end
  end

  # -----InvoiceCounter-------------
  @max_invoice_number 9_999_999_999
  @max_invoice_number_formatted "9,999,999,999"
  @initial_next_seq 2

  @doc """
  Generates the next invoice number for a company.

  ## Parameters
    - company_id: The company ID
    - sequence_name: Optional sequence name (default: "default")
      Can be used for separate sequences by currency, department, etc.
      Valid values: "default", "KZT", "USD", "EUR", "RUB"

  ## Examples

      iex> Invoicing.next_invoice_number!(company_id)
      "0000000001"

      iex> Invoicing.next_invoice_number!(company_id, "USD")
      "0000000001"

  """
  def next_invoice_number!(company_id, sequence_name \\ "default") do
    sequence_name = normalize_sequence_name(sequence_name)

    # First, check for recycled numbers (FIFO - use oldest first)
    case get_and_remove_recycled_number(company_id, sequence_name) do
      {:ok, recycled_number} ->
        recycled_number

      :none_available ->
        # No recycled numbers available, use counter
        get_next_number_from_counter(company_id, sequence_name)
    end
  end

  defp get_next_number_from_counter(company_id, sequence_name) do
    current_counter =
      Repo.get_by(InvoiceCounter, company_id: company_id, sequence_name: sequence_name)

    cond do
      current_counter == nil ->
        create_and_increment_counter(company_id, sequence_name)

      true ->
        current_counter =
          sync_counter_with_existing_invoices(current_counter, company_id, sequence_name)

        if current_counter.next_seq > @max_invoice_number + 1 do
          raise RuntimeError,
                "invoice number counter overflow: maximum invoice number (#{@max_invoice_number_formatted}) exceeded for company #{company_id}, sequence #{sequence_name}"
        end

        increment_and_get_number(company_id, sequence_name)
    end
  end

  @doc """
  Formats an invoice number as exactly 11 digits.

  ## Examples

      iex> Invoicing.format_invoice_number(1)
      "00000000001"

      iex> Invoicing.format_invoice_number(123)
      "00000000123"

  """
  def format_invoice_number(seq, _sequence_name \\ "default") do
    String.pad_leading(Integer.to_string(seq), 11, "0")
  end

  # Always use default sequence (no currency prefixes supported)
  defp normalize_sequence_name(_sequence_name) do
    "default"
  end

  defp create_and_increment_counter(company_id, sequence_name) do
    next_seq = seed_next_seq_from_existing_invoices(company_id, sequence_name)

    {:ok, number} =
      Repo.transaction(fn ->
        %{next_seq: next_seq} =
          Repo.insert!(
            %InvoiceCounter{
              company_id: company_id,
              sequence_name: sequence_name,
              next_seq: next_seq
            },
            on_conflict: [inc: [next_seq: 1]],
            conflict_target: [:company_id, :sequence_name],
            returning: [:next_seq]
          )

        seq = next_seq - 1
        format_invoice_number(seq, sequence_name)
      end)

    number
  end

  defp sync_counter_with_existing_invoices(current_counter, company_id, sequence_name) do
    minimum_next_seq = minimum_counter_next_seq(company_id, sequence_name)

    if current_counter.next_seq < minimum_next_seq do
      current_counter
      |> InvoiceCounter.changeset(%{next_seq: minimum_next_seq})
      |> Repo.update!()
    else
      current_counter
    end
  end

  defp seed_next_seq_from_existing_invoices(company_id, sequence_name) do
    max(
      @initial_next_seq,
      next_free_sequence_from_existing_invoices(company_id, sequence_name) + 1
    )
  end

  defp minimum_counter_next_seq(company_id, sequence_name) do
    max(@initial_next_seq, next_free_sequence_from_existing_invoices(company_id, sequence_name))
  end

  defp next_free_sequence_from_existing_invoices(company_id, _sequence_name) do
    max_number =
      Invoice
      |> where([i], i.company_id == ^company_id and not is_nil(i.number) and i.number != "")
      |> select([i], max(i.number))
      |> Repo.one()

    case max_number do
      nil ->
        1

      number ->
        seq = String.to_integer(number)

        if seq >= @max_invoice_number do
          raise RuntimeError,
                "invoice number counter overflow: maximum invoice number (#{@max_invoice_number_formatted}) exceeded for company #{company_id}, sequence default"
        end

        seq + 1
    end
  end

  defp increment_and_get_number(company_id, sequence_name) do
    {:ok, number} =
      Repo.transaction(fn ->
        %{next_seq: next_seq} =
          Repo.insert!(
            %InvoiceCounter{
              company_id: company_id,
              sequence_name: sequence_name,
              next_seq: @initial_next_seq
            },
            on_conflict: [inc: [next_seq: 1]],
            conflict_target: [:company_id, :sequence_name],
            returning: [:next_seq]
          )

        seq = next_seq - 1

        if seq > @max_invoice_number do
          raise RuntimeError,
                "invoice number counter overflow: maximum invoice number (#{@max_invoice_number_formatted}) exceeded for company #{company_id}, sequence #{sequence_name}"
        end

        format_invoice_number(seq, sequence_name)
      end)

    number
  end

  # ------------ Marking-Invoice-issued-------------------
  def mark_invoice_issued(invoice) do
    RepoHelpers.transaction(fn ->
      invoice = RepoHelpers.fetch_or_abort(invoice, :invoice)

      invoice = preload_invoice(invoice)

      case do_issue_invoice(invoice) do
        {:ok, inv} ->
          {:ok, inv}

        {:error, reason} ->
          RepoHelpers.abort({:business_rule, %{rule: reason}})

        {:error, reason, details} ->
          RepoHelpers.abort({:business_rule, %{rule: reason, details: details}})
      end
    end)
  end

  defp do_issue_invoice(invoice) do
    cond do
      is_nil(invoice) ->
        Errors.not_found(:invoice)

      InvoiceStatus.is_issued?(invoice) ->
        Errors.business_rule(:already_issued, %{invoice_id: invoice.id, status: invoice.status})

      not InvoiceStatus.can_issue?(invoice) ->
        Errors.business_rule(:cannot_issue, %{
          invoice_id: invoice.id,
          status: "must be draft to issue"
        })

      not contract_ready_for_progression?(invoice) ->
        Errors.business_rule(
          :contract_must_be_signed_to_issue_invoice,
          contract_progression_details(invoice)
        )

      (invoice.items || []) == [] ->
        Errors.business_rule(:cannot_issue, %{
          invoice_id: invoice.id,
          items: "must have at least 1 item"
        })

      is_nil(invoice.total) or Decimal.compare(invoice.total, zero_decimal()) != :gt ->
        Errors.business_rule(:cannot_issue, %{invoice_id: invoice.id, total: "must be > 0"})

      true ->
        with {:ok, bank_account} <- select_bank_account(invoice),
             {:ok, _snap} <- create_bank_snapshot(invoice, bank_account),
             {:ok, inv} <- update_invoice_status(invoice, InvoiceStatus.issued()) do
          {:ok, preload_invoice(inv)}
        end
      end
  end

  defp contract_progression_details(invoice) do
    %{
      invoice_id: invoice.id,
      contract_id: invoice.contract_id,
      contract_status: invoice_contract_status(invoice)
    }
  end

  defp invoice_contract_status(%{contract: %{status: status}}), do: status
  defp invoice_contract_status(_invoice), do: nil

  defp update_invoice_status(invoice, status) do
    invoice
    |> Ecto.Changeset.change(status: status)
    |> Repo.update()
  end

  defp select_bank_account(invoice) do
    invoice_company_id = invoice.company_id

    case invoice.bank_account do
      %CompanyBankAccount{} = acc ->
        {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}

      _ ->
        case invoice.bank_account_id do
          nil ->
            case CompanyBankAccount.get_default_account(invoice_company_id) do
              nil ->
                Errors.business_rule(:bank_account_required, %{
                  invoice_id: invoice.id,
                  company_id: invoice_company_id
                })

              acc ->
                {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}
            end

          id ->
            case Repo.get(CompanyBankAccount, id) do
              %CompanyBankAccount{company_id: ^invoice_company_id} = acc ->
                {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}

              _ ->
                Errors.not_found(:bank_account)
            end
        end
    end
  end

  defp create_bank_snapshot(invoice, %CompanyBankAccount{} = acc) do
    bank = acc.bank
    kbe = invoice.kbe_code || acc.kbe_code
    knp = invoice.knp_code || acc.knp_code

    attrs = %{
      "invoice_id" => invoice.id,
      "bank_name" => bank && bank.name,
      "bic" => bank && bank.bic,
      "iban" => acc.iban,
      "kbe" => kbe && kbe.code,
      "knp" => knp && knp.code
    }

    %InvoiceBankSnapshot{}
    |> InvoiceBankSnapshot.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, snap} ->
        {:ok, snap}

      {:error, %Ecto.Changeset{} = cs} ->
        case Keyword.get(cs.errors, :invoice_id) do
          {_, opts} when is_list(opts) ->
            if Keyword.get(opts, :constraint) == :unique do
              Errors.business_rule(:already_issued, %{invoice_id: invoice.id})
            else
              Errors.from_changeset({:error, cs})
            end

          _ ->
            Errors.from_changeset({:error, cs})
        end
    end
  end

  def delete_invoice_for_user(user_id, invoice_id) do
    invoice =
      Invoice
      |> where([i], i.id == ^invoice_id and i.user_id == ^user_id)
      |> Repo.one()

    if invoice do
      if InvoiceStatus.is_issued?(invoice.status) do
        Errors.business_rule(:cannot_delete_issued_invoice, %{
          invoice_id: invoice.id,
          status: invoice.status
        })
      else
        case Repo.transaction(fn ->
               # Delete invoice items first
               InvoiceItem
               |> where([ii], ii.invoice_id == ^invoice_id)
               |> Repo.delete_all()

               # Delete bank snapshot if exists
               InvoiceBankSnapshot
               |> where([ibs], ibs.invoice_id == ^invoice_id)
               |> Repo.delete_all()

               # Delete the invoice
               case Repo.delete(invoice) do
                 {:ok, invoice} -> invoice
                 {:error, changeset} -> Repo.rollback({:validation_failed, changeset})
               end
             end) do
          {:ok, invoice} ->
            # Store the invoice number for recycling
            # Only draft invoices are deleted, so we can safely recycle their numbers
            recycle_invoice_number(invoice.company_id, invoice.number, "default")

            {:ok, invoice}

          {:error, {:validation_failed, changeset}} ->
            {:error, :validation, %{changeset: changeset}}

          {:error, reason} ->
            {:error, :transaction_failed, %{reason: reason}}
        end
      end
    else
      Errors.not_found(:invoice)
    end
  end

  @doc false
  defp recycle_invoice_number(company_id, number, sequence_name) do
    # Parse the number to ensure it's valid (11 digits)
    case Integer.parse(number) do
      {num, ""} when num > 0 and num <= @max_invoice_number ->
        attrs = %{
          company_id: company_id,
          number: number,
          sequence_name: normalize_sequence_name(sequence_name),
          deleted_at: DateTime.utc_now()
        }

        %InvoiceRecycledNumber{}
        |> InvoiceRecycledNumber.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, _recycled} ->
            Logger.info("Recycled invoice number #{number} for company #{company_id}")
            :ok

          {:error, %{errors: [number: {"has already been taken", _}]}} ->
            # Number already in recycle pool (shouldn't happen normally)
            Logger.warning(
              "Invoice number #{number} already in recycle pool for company #{company_id}"
            )

            :ok

          {:error, changeset} ->
            Logger.error(
              "Failed to recycle invoice number #{number}: #{inspect(changeset.errors)}"
            )

            # Don't fail the deletion if recycling fails
            :ok
        end

      _ ->
        # Invalid number format, skip recycling
        Logger.warning("Cannot recycle invalid invoice number format: #{number}")
        :ok
    end
  end

  @doc false
  defp get_and_remove_recycled_number(company_id, sequence_name) do
    sequence_name = normalize_sequence_name(sequence_name)

    # Find the oldest recycled number (FIFO)
    recycled =
      InvoiceRecycledNumber
      |> where([r], r.company_id == ^company_id and r.sequence_name == ^sequence_name)
      |> order_by([r], asc: r.inserted_at)
      |> limit(1)
      |> Repo.one()

    case recycled do
      nil ->
        :none_available

      recycled ->
        # Delete it from the pool and return the number
        case Repo.delete(recycled) do
          {:ok, _} ->
            Logger.info(
              "Reusing recycled invoice number #{recycled.number} for company #{company_id}"
            )

            {:ok, recycled.number}

          {:error, _changeset} ->
            # If deletion fails (race condition), try again
            get_and_remove_recycled_number(company_id, sequence_name)
        end
    end
  end

  defp resolve_contract_bank_account_id(contract, bank_accounts) do
    contract_bank_account_id = contract.bank_account_id

    has_contract_bank_account? =
      Enum.any?(bank_accounts, fn account -> account.id == contract_bank_account_id end)

    cond do
      has_contract_bank_account? ->
        contract_bank_account_id

      true ->
        case Enum.find(bank_accounts, & &1.is_default) || List.first(bank_accounts) do
          nil -> nil
          account -> account.id
        end
    end
  end

  defp normalize_qty_for_invoice(%Decimal{} = qty_decimal) do
    qty_decimal
    |> Decimal.round(0, :half_up)
    |> Decimal.to_integer()
  end

  defp normalize_qty_for_invoice(qty) when is_integer(qty), do: qty
  defp normalize_qty_for_invoice(qty) when is_float(qty), do: trunc(qty)
  defp normalize_qty_for_invoice(qty) when is_binary(qty), do: parse_int(qty)
  defp normalize_qty_for_invoice(_), do: 1

  defp decimal_to_string(%Decimal{} = value), do: Decimal.to_string(value)
  defp decimal_to_string(value) when is_integer(value), do: Integer.to_string(value)

  defp decimal_to_string(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact])

  defp decimal_to_string(_), do: "0"
end
