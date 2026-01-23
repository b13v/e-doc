defmodule EdocApi.Invoicing do
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.RepoHelpers
  alias EdocApi.Currencies
  alias EdocApi.Core.Company
  alias EdocApi.Core.Invoice
  alias EdocApi.Core.InvoiceBankSnapshot
  alias EdocApi.Core.InvoiceItem
  alias EdocApi.Core.InvoiceCounter
  alias EdocApi.Core.CompanyBankAccount
  alias EdocApi.InvoiceStatus

  def get_invoice_for_user(user_id, invoice_id) do
    Invoice
    |> where([i], i.id == ^invoice_id and i.user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil -> nil
      invoice -> preload_invoice(invoice)
    end
  end

  def list_invoices_for_user(user_id) do
    Invoice
    |> where([i], i.user_id == ^user_id)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
    |> Repo.preload([
      :items,
      :bank_snapshot,
      :contract,
      bank_account: [:bank, :kbe_code, :knp_code],
      company: [:bank, :kbe_code, :knp_code]
    ])
  end

  def issue_invoice_for_user(user_id, invoice_id) do
    RepoHelpers.transaction(fn ->
      invoice =
        Invoice
        |> where([i], i.user_id == ^user_id and i.id == ^invoice_id)
        |> Repo.one()

      unless invoice do
        RepoHelpers.abort(:invoice_not_found)
      end

      invoice = preload_invoice(invoice)

      case do_issue_invoice(invoice) do
        {:ok, inv} -> {:ok, inv}
        {:error, reason} -> RepoHelpers.abort(reason)
        {:error, reason, details} -> RepoHelpers.abort({reason, details})
      end
    end)
    |> case do
      {:ok, invoice} -> {:ok, invoice}
      {:error, {reason, details}} -> {:error, reason, details}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_invoice_for_user(user_id, company_id, attrs) do
    items_attrs = Map.get(attrs, "items") || Map.get(attrs, :items) || []
    bank_account_id = Map.get(attrs, "bank_account_id") || Map.get(attrs, :bank_account_id)

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
  end

  def update_invoice_for_user(user_id, invoice_id, attrs) do
    RepoHelpers.transaction(fn ->
      invoice =
        Invoice
        |> where([i], i.user_id == ^user_id and i.id == ^invoice_id)
        |> Repo.one()

      unless invoice do
        RepoHelpers.abort(:invoice_not_found)
      end

      # Only allow updates on draft invoices
      unless InvoiceStatus.is_draft?(invoice) do
        RepoHelpers.abort(:invoice_already_issued)
      end

      items_attrs = Map.get(attrs, "items") || Map.get(attrs, :items) || []
      bank_account_id = Map.get(attrs, "bank_account_id") || Map.get(attrs, :bank_account_id)

      # Handle bank account if specified
      bank_account =
        case bank_account_id do
          nil -> nil
          _id -> get_bank_account_for_invoice(invoice.company_id, bank_account_id)
        end

      if bank_account_id && bank_account == nil do
        RepoHelpers.abort(:bank_account_not_found)
      end

      # Handle items if provided
      new_subtotal =
        if items_attrs != [] do
          RepoHelpers.check_or_abort(items_attrs != [], :items_required)
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
        |> maybe_put_subtotal(new_subtotal)

      invoice_changeset =
        Invoice.changeset(invoice, invoice_attrs, user_id, invoice.company_id)

      {:ok, invoice} = RepoHelpers.update_or_abort(invoice_changeset)
      {:ok, preload_invoice(invoice)}
    end)
    |> case do
      {:ok, invoice} -> {:ok, invoice}
      {:error, {reason, details}} -> {:error, reason, details}
      {:error, reason} -> {:error, reason}
    end
  end

  defp preload_invoice(invoice) do
    Repo.preload(invoice, [
      :items,
      :bank_snapshot,
      :contract,
      bank_account: [:bank, :kbe_code, :knp_code],
      company: [:bank, :kbe_code, :knp_code]
    ])
  end

  defp get_bank_account_for_invoice(company_id, nil) do
    case CompanyBankAccount.get_default_account(company_id) do
      nil -> RepoHelpers.abort(:bank_account_required)
      acc -> acc
    end
  end

  defp get_bank_account_for_invoice(company_id, bank_account_id) do
    case Repo.get(CompanyBankAccount, bank_account_id) do
      %CompanyBankAccount{company_id: ^company_id} = acc ->
        acc

      _ ->
        RepoHelpers.abort(:bank_account_not_found)
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

  defp maybe_put_subtotal(attrs, subtotal) when is_binary(subtotal),
    do: Map.put(attrs, "subtotal", subtotal)

  defp maybe_put_subtotal(attrs, %Decimal{} = subtotal),
    do: Map.put(attrs, "subtotal", Decimal.to_string(subtotal))

  defp maybe_put_bank_account_id(attrs, nil), do: attrs

  defp maybe_put_bank_account_id(attrs, %CompanyBankAccount{id: id}),
    do: Map.put(attrs, "bank_account_id", id)

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

  def next_invoice_number!(company_id) do
    # Check for existing counter
    current_counter =
      Repo.get_by(InvoiceCounter, company_id: company_id)

    cond do
      # Counter doesn't exist - create it starting at 2
      current_counter == nil ->
        create_and_increment_counter(company_id)

      # Counter was manually set with a specific value (not the initial 2)
      # Use it as-is without incrementing on first call
      current_counter.next_seq > @initial_next_seq ->
        seq = current_counter.next_seq - 1

        if seq > @max_invoice_number do
          raise RuntimeError,
                "invoice number counter overflow: maximum invoice number (#{@max_invoice_number_formatted}) exceeded for company #{company_id}"
        end

        # Mark as used by incrementing for next call
        Repo.update!(InvoiceCounter.changeset(current_counter, %{next_seq: current_counter.next_seq + 1}))

        String.pad_leading(Integer.to_string(seq), 10, "0")

      # Counter exists and was created normally - proceed with increment
      true ->
        if current_counter.next_seq > @max_invoice_number + 1 do
          raise RuntimeError,
                "invoice number counter overflow: maximum invoice number (#{@max_invoice_number_formatted}) exceeded for company #{company_id}"
        end

        increment_and_get_number(company_id)
    end
  end

  defp create_and_increment_counter(company_id) do
    Repo.transaction(fn ->
      %{next_seq: next_seq} =
        Repo.insert!(
          %InvoiceCounter{company_id: company_id, next_seq: @initial_next_seq},
          on_conflict: [inc: [next_seq: 1]],
          conflict_target: :company_id,
          returning: [:next_seq]
        )

      seq = next_seq - 1
      String.pad_leading(Integer.to_string(seq), 10, "0")
    end)
    |> case do
      {:ok, number} -> number
      {:error, reason} ->
        raise "invoice number generation failed: #{inspect(reason)}"
    end
  end

  defp increment_and_get_number(company_id) do
    Repo.transaction(fn ->
      %{next_seq: next_seq} =
        Repo.insert!(
          %InvoiceCounter{company_id: company_id, next_seq: @initial_next_seq},
          on_conflict: [inc: [next_seq: 1]],
          conflict_target: :company_id,
          returning: [:next_seq]
        )

      seq = next_seq - 1

      if seq > @max_invoice_number do
        raise RuntimeError,
              "invoice number counter overflow: maximum invoice number (#{@max_invoice_number_formatted}) exceeded for company #{company_id}"
      end

      String.pad_leading(Integer.to_string(seq), 10, "0")
    end)
    |> case do
      {:ok, number} -> number
      {:error, reason} ->
        raise "invoice number generation failed: #{inspect(reason)}"
    end
  end

  # ------------ Marking-Invoice-issued-------------------
  def mark_invoice_issued(invoice) do
    RepoHelpers.transaction(fn ->
      unless invoice do
        RepoHelpers.abort(:invoice_not_found)
      end

      invoice = preload_invoice(invoice)

      case do_issue_invoice(invoice) do
        {:ok, inv} -> {:ok, inv}
        {:error, reason} -> RepoHelpers.abort(reason)
        {:error, reason, details} -> RepoHelpers.abort({reason, details})
      end
    end)
    |> case do
      {:ok, inv} -> {:ok, inv}
      {:error, {reason, details}} -> {:error, reason, details}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_issue_invoice(invoice) do
    cond do
      is_nil(invoice) ->
        {:error, :invoice_not_found}

      not is_nil(invoice.bank_snapshot) ->
        {:error, :already_issued}

      InvoiceStatus.is_issued?(invoice) ->
        {:error, :already_issued}

      not InvoiceStatus.can_issue?(invoice) ->
        {:error, :cannot_issue, %{status: "must be draft to issue"}}

      (invoice.items || []) == [] ->
        {:error, :cannot_issue, %{items: "must have at least 1 item"}}

      is_nil(invoice.total) or Decimal.compare(invoice.total, zero_decimal()) != :gt ->
        {:error, :cannot_issue, %{total: "must be > 0"}}

      true ->
        with {:ok, bank_account} <- select_bank_account(invoice),
             {:ok, _snap} <- create_bank_snapshot(invoice, bank_account),
             {:ok, inv} <- update_invoice_status(invoice, InvoiceStatus.issued()) do
          {:ok, preload_invoice(inv)}
        end
    end
  end

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
              nil -> {:error, :bank_account_required}
              acc -> {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}
            end

          id ->
            case Repo.get(CompanyBankAccount, id) do
              %CompanyBankAccount{company_id: ^invoice_company_id} = acc ->
                {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}

              _ ->
                {:error, :bank_account_not_found}
            end
        end
    end
  end

  defp create_bank_snapshot(invoice, %CompanyBankAccount{} = acc) do
    bank = acc.bank
    kbe = acc.kbe_code
    knp = acc.knp_code

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
              {:error, :already_issued}
            else
              {:error, cs}
            end

          _ ->
            {:error, cs}
        end
    end
  end
end
