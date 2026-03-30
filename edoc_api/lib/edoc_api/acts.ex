defmodule EdocApi.Acts do
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.ActStatus
  alias EdocApi.Core.Act
  alias EdocApi.Core.ActItem
  alias EdocApi.Core.Company
  alias EdocApi.Companies
  alias EdocApi.Buyers
  alias EdocApi.Invoicing

  def list_acts_for_user(user_id) when is_binary(user_id) do
    Act
    |> where([a], a.user_id == ^user_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
    |> Repo.preload([:items, :company, :buyer, :contract])
  end

  def get_act_for_user(user_id, act_id) when is_binary(user_id) and is_binary(act_id) do
    Act
    |> where([a], a.user_id == ^user_id and a.id == ^act_id)
    |> Repo.one()
    |> case do
      nil -> nil
      act -> Repo.preload(act, [:items, :company, :buyer, :contract])
    end
  end

  def delete_act_for_user(user_id, act_id) when is_binary(user_id) and is_binary(act_id) do
    case get_act_for_user(user_id, act_id) do
      nil ->
        {:error, :not_found}

      %Act{} = act ->
        if ActStatus.is_draft?(act) do
          Repo.delete(act)
        else
          {:error, :business_rule, %{rule: :cannot_delete_non_draft_act}}
        end
    end
  end

  def sign_act_for_user(user_id, act_id) when is_binary(user_id) and is_binary(act_id) do
    case get_act_for_user(user_id, act_id) do
      nil ->
        {:error, :not_found}

      %Act{} = act ->
        cond do
          ActStatus.already_signed?(act) ->
            {:error, :business_rule, %{rule: :act_already_signed}}

          not ActStatus.can_sign?(act) ->
            {:error, :business_rule, %{rule: :act_not_issued}}

          true ->
            act
            |> Ecto.Changeset.change(status: ActStatus.signed())
            |> Repo.update()
        end
    end
  end

  def issue_act_for_user(user_id, act_id) when is_binary(user_id) and is_binary(act_id) do
    case get_act_for_user(user_id, act_id) do
      nil ->
        {:error, :not_found}

      %Act{} = act ->
        cond do
          ActStatus.already_issued?(act) ->
            {:error, :business_rule, %{rule: :act_not_editable}}

          true ->
            act
            |> Ecto.Changeset.change(status: ActStatus.issued())
            |> Repo.update()
        end
    end
  end

  def list_issued_contracts_for_user(user_id) when is_binary(user_id) do
    Invoicing.list_issued_contracts_for_user(user_id)
  end

  def build_act_from_contract(user_id, contract_id)
      when is_binary(user_id) and is_binary(contract_id) do
    with {:ok, contract} <- Invoicing.get_issued_contract_for_user(user_id, contract_id) do
      buyer = contract.buyer

      items =
        Enum.map(contract.contract_items || [], fn item ->
          %{
            "name" => item.name || "",
            "report_info" => "",
            "code" => item.code || "",
            "qty" => decimal_to_string(item.qty),
            "unit_price" => decimal_to_string(item.unit_price)
          }
        end)

      {:ok,
       %{
         selected_contract_id: contract.id,
         selected_buyer_id: buyer && buyer.id,
         buyer_address: (buyer && buyer.address) || "",
         vat_rate: contract.vat_rate || 0,
         prefill_items: items
       }}
    end
  end

  def create_act_for_user(user_id, company_id, attrs)
      when is_binary(user_id) and is_binary(company_id) and is_map(attrs) do
    with %Company{} = company <- Companies.get_company_by_user_id(user_id),
         true <- company.id == company_id,
         {:ok, buyer} <- fetch_buyer(attrs, company_id),
         {:ok, contract, vat_rate} <- fetch_optional_contract(attrs, user_id),
         {:ok, prepared_items} <- prepare_items(attrs, vat_rate) do
      number = next_act_number!(company_id)

      act_attrs =
        %{
          "number" => number,
          "status" => ActStatus.default(),
          "issue_date" => Map.get(attrs, "issue_date"),
          "actual_date" => blank_to_nil(Map.get(attrs, "actual_date")),
          "currency" => "KZT",
          "vat_rate" => vat_rate,
          "seller_name" => company.name,
          "seller_bin_iin" => company.bin_iin,
          "seller_address" => company.address,
          "seller_phone" => company.phone,
          "buyer_name" => buyer.name,
          "buyer_bin_iin" => buyer.bin_iin,
          "buyer_address" => Map.get(attrs, "buyer_address") || buyer.address || "",
          "buyer_phone" => buyer.phone,
          "company_id" => company_id,
          "user_id" => user_id,
          "buyer_id" => buyer.id,
          "contract_id" => contract && contract.id
        }

      Repo.transaction(fn ->
        case %Act{} |> Act.changeset(act_attrs) |> Repo.insert() do
          {:ok, act} ->
            Enum.each(prepared_items, fn item_attrs ->
              attrs = Map.put(item_attrs, "act_id", act.id)

              case %ActItem{} |> ActItem.changeset(attrs) |> Repo.insert() do
                {:ok, _} -> :ok
                {:error, changeset} -> Repo.rollback({:validation, %{changeset: changeset}})
              end
            end)

            Repo.preload(act, [:items, :company, :buyer, :contract])

          {:error, changeset} ->
            Repo.rollback({:validation, %{changeset: changeset}})
        end
      end)
      |> case do
        {:ok, act} ->
          {:ok, act}

        {:error, {:validation, %{changeset: changeset}}} ->
          {:error, :validation, %{changeset: changeset}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      nil ->
        {:error, :business_rule, %{rule: :company_required}}

      false ->
        {:error, :business_rule, %{rule: :company_required}}

      {:error, type, details} ->
        {:error, type, details}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def next_act_number!(company_id) when is_binary(company_id) do
    last_number =
      Act
      |> where([a], a.company_id == ^company_id)
      |> select([a], a.number)
      |> Repo.all()
      |> Enum.flat_map(fn
        nil ->
          []

        number ->
          case Integer.parse(number) do
            {value, ""} -> [value]
            _ -> []
          end
      end)
      |> Enum.max(fn -> 0 end)

    seq = if last_number > 0, do: last_number + 1, else: 1

    String.pad_leading(Integer.to_string(seq), 11, "0")
  end

  defp fetch_buyer(attrs, company_id) do
    buyer_id = blank_to_nil(Map.get(attrs, "buyer_id"))

    case buyer_id do
      nil ->
        {:error, :business_rule, %{rule: :buyer_required}}

      id ->
        case Buyers.get_buyer_for_company(id, company_id) do
          nil -> {:error, :business_rule, %{rule: :buyer_required}}
          buyer -> {:ok, buyer}
        end
    end
  end

  defp fetch_optional_contract(attrs, user_id) do
    case blank_to_nil(Map.get(attrs, "contract_id")) do
      nil ->
        {:ok, nil, normalize_vat_rate(Map.get(attrs, "vat_rate"))}

      contract_id ->
        case Invoicing.get_issued_contract_for_user(user_id, contract_id) do
          {:ok, contract} -> {:ok, contract, contract.vat_rate || 0}
          _ -> {:error, :business_rule, %{rule: :contract_not_issued_or_not_found}}
        end
    end
  end

  defp prepare_items(attrs, vat_rate) do
    raw_items = normalize_items(Map.get(attrs, "items") || [])

    items =
      raw_items
      |> Enum.reject(fn item ->
        String.trim(to_string(Map.get(item, "name", ""))) == ""
      end)
      |> Enum.map(fn item ->
        qty = parse_decimal(Map.get(item, "qty"))
        unit_price = parse_decimal(Map.get(item, "unit_price"))
        amount = Decimal.mult(qty, unit_price) |> Decimal.round(2)

        vat_amount =
          if vat_rate > 0 do
            amount
            |> Decimal.mult(Decimal.new(vat_rate))
            |> Decimal.div(Decimal.new(100 + vat_rate))
            |> Decimal.round(2)
          else
            Decimal.new(0)
          end

        %{
          "name" => Map.get(item, "name"),
          "report_info" => blank_to_nil(Map.get(item, "report_info")),
          "code" => Map.get(item, "code"),
          "qty" => qty,
          "unit_price" => unit_price,
          "amount" => amount,
          "vat_amount" => vat_amount,
          "actual_date" => blank_to_nil(Map.get(item, "actual_date"))
        }
      end)

    if items == [] do
      {:error, :business_rule, %{rule: :items_required}}
    else
      {:ok, items}
    end
  end

  defp normalize_items(items) when is_list(items), do: items

  defp normalize_items(items) when is_map(items) do
    items
    |> Enum.sort_by(fn {key, _} ->
      case Integer.parse(to_string(key)) do
        {idx, ""} -> idx
        _ -> 9_999_999
      end
    end)
    |> Enum.map(fn {_k, v} -> v end)
  end

  defp normalize_items(_), do: []

  defp parse_decimal(nil), do: Decimal.new(0)
  defp parse_decimal(""), do: Decimal.new(0)
  defp parse_decimal(%Decimal{} = d), do: d
  defp parse_decimal(v) when is_integer(v), do: Decimal.new(v)

  defp parse_decimal(v) when is_binary(v) do
    case Decimal.parse(v) do
      {d, _} -> d
      :error -> Decimal.new(0)
    end
  end

  defp parse_decimal(_), do: Decimal.new(0)

  defp decimal_to_string(nil), do: ""
  defp decimal_to_string(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  defp decimal_to_string(v), do: to_string(v)

  defp normalize_vat_rate(nil), do: 16

  defp normalize_vat_rate(v) when is_integer(v) and v >= 0, do: v

  defp normalize_vat_rate(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} when n >= 0 -> n
      _ -> 16
    end
  end

  defp normalize_vat_rate(_), do: 16

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
end
