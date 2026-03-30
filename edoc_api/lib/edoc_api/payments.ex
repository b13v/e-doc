defmodule EdocApi.Payments do
  import Ecto.Query, warn: false

  alias EdocApi.Repo
  alias EdocApi.Companies
  alias EdocApi.Core.{Bank, CompanyBankAccount, KbeCode, KnpCode}
  alias EdocApi.Validators.Iban

  def list_company_bank_accounts_for_user(user_id) do
    load_company_bank_accounts_for_user(user_id)
  end

  def list_visible_company_bank_accounts_for_user(user_id) do
    user_id
    |> load_company_bank_accounts_for_user()
    |> Enum.filter(&valid_company_bank_account?/1)
  end

  defp load_company_bank_accounts_for_user(user_id) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        []

      company ->
        CompanyBankAccount
        |> where([a], a.company_id == ^company.id)
        |> order_by([a], desc: a.is_default, asc: a.label)
        |> Repo.all()
        |> Repo.preload([:bank, :kbe_code, :knp_code])
    end
  end

  def create_company_bank_account_for_user(user_id, attrs) do
    case Companies.get_company_by_user_id(user_id) do
      nil ->
        {:error, :company_required}

      company ->
        Repo.transaction(fn ->
          with {:ok, attrs} <- merge_code_ids_for_create(company.id, attrs),
               {:ok, attrs} <- ensure_create_label(company.id, attrs) do
            if requested_default?(attrs) do
              CompanyBankAccount.reset_all_defaults(company.id)
            end

            case %CompanyBankAccount{}
                 |> CompanyBankAccount.changeset(attrs, company.id)
                 |> Repo.insert() do
              {:ok, acc} ->
                Repo.preload(acc, [:bank, :kbe_code, :knp_code])

              {:error, %Ecto.Changeset{} = cs} ->
                Repo.rollback(cs)
            end
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
        |> case do
          {:ok, acc} -> {:ok, acc}
          {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def get_company_bank_account_for_user(user_id, bank_account_id) do
    with {:ok, company} <- get_company_or_rollback(user_id),
         {:ok, bank_account} <- verify_bank_account_ownership(company.id, bank_account_id) do
      {:ok, Repo.preload(bank_account, [:bank, :kbe_code, :knp_code])}
    end
  end

  def update_company_bank_account_for_user(user_id, bank_account_id, attrs) do
    with {:ok, company} <- get_company_or_rollback(user_id),
         {:ok, bank_account} <- verify_bank_account_ownership(company.id, bank_account_id),
         {:ok, attrs} <- merge_code_ids_for_update(company.id, bank_account, attrs),
         {:ok, updated} <-
           bank_account
           |> CompanyBankAccount.changeset(attrs, company.id)
           |> Repo.update() do
      {:ok, Repo.preload(updated, [:bank, :kbe_code, :knp_code])}
    else
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
      {:error, reason} -> {:error, reason}
    end
  end

  def set_default_bank_account(user_id, bank_account_id) do
    Repo.transaction(fn ->
      with {:ok, company} <- get_company_or_rollback(user_id),
           {:ok, bank_account} <- verify_bank_account_ownership(company.id, bank_account_id) do
        # Only reset if this account is not already default
        if bank_account.is_default do
          bank_account
        else
          # Reset all defaults FIRST (before any validation that could fail)
          CompanyBankAccount.reset_all_defaults(company.id)

          # Now set the new default
          {:ok, acc} =
            bank_account
            |> CompanyBankAccount.set_as_default_changeset(%{}, company.id)
            |> Repo.update()

          acc
        end
      else
        {:error, reason} -> Repo.rollback(reason)
        nil -> Repo.rollback(:bank_account_not_found)
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Repo.preload(acc, [:bank, :kbe_code, :knp_code])}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_company_or_rollback(user_id) do
    case Companies.get_company_by_user_id(user_id) do
      nil -> {:error, :company_required}
      company -> {:ok, company}
    end
  end

  defp verify_bank_account_ownership(company_id, bank_account_id) do
    case Repo.get(CompanyBankAccount, bank_account_id) do
      %CompanyBankAccount{company_id: ^company_id} = acc -> {:ok, acc}
      _ -> {:error, :bank_account_not_found}
    end
  end

  @doc false
  def set_default_bank_account_for_company!(company_id, bank_account_id) do
    # Transaction-safe pattern for internal use
    {:ok, acc} =
      Repo.transaction(fn ->
        bank_account =
          CompanyBankAccount
          |> where([a], a.id == ^bank_account_id and a.company_id == ^company_id)
          |> Repo.one!()

        # Only reset if this account is not already default
        if bank_account.is_default do
          bank_account
        else
          CompanyBankAccount.reset_all_defaults(company_id)

          bank_account
          |> CompanyBankAccount.set_as_default_changeset(%{}, company_id)
          |> Repo.update!()
        end
      end)

    # Reload from database to ensure we have the latest state
    Repo.get(CompanyBankAccount, acc.id)
  end

  def list_banks do
    Bank |> order_by([b], asc: b.name) |> Repo.all()
  end

  def list_kbe_codes do
    KbeCode |> order_by([k], asc: k.code) |> Repo.all()
  end

  def list_knp_codes do
    KnpCode |> order_by([k], asc: k.code) |> Repo.all()
  end

  defp merge_code_ids_for_create(company_id, attrs) do
    with {:ok, default_kbe_code_id} <- resolve_default_kbe_code_id(company_id),
         {:ok, default_knp_code_id} <- resolve_default_knp_code_id(company_id) do
      attrs
      |> put_missing_code_id("kbe_code_id", default_kbe_code_id)
      |> put_missing_code_id("knp_code_id", default_knp_code_id)
      |> then(&{:ok, &1})
    end
  end

  defp ensure_create_label(company_id, attrs) do
    attrs = Map.new(attrs)

    case attrs |> Map.get("label", Map.get(attrs, :label)) |> normalize_label() do
      nil ->
        label = default_create_label(company_id, attrs)
        {:ok, Map.put(attrs, "label", label)}

      label ->
        {:ok, Map.put(attrs, "label", label)}
    end
  end

  defp normalize_label(nil), do: nil

  defp normalize_label(label) when is_binary(label) do
    case String.trim(label) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp default_create_label(company_id, attrs) do
    base_label =
      attrs
      |> Map.get("bank_id", Map.get(attrs, :bank_id))
      |> then(&bank_name_for_label/1)
      |> case do
        nil -> "Bank account"
        bank_name -> bank_name
      end

    account_number =
      CompanyBankAccount
      |> where([a], a.company_id == ^company_id)
      |> Repo.aggregate(:count, :id)
      |> Kernel.+(1)

    "#{base_label} #{account_number}"
  end

  defp bank_name_for_label(nil), do: nil

  defp bank_name_for_label(bank_id) do
    case Repo.get(Bank, bank_id) do
      %Bank{name: name} when is_binary(name) -> String.trim(name)
      _ -> nil
    end
  end

  defp merge_code_ids_for_update(company_id, %CompanyBankAccount{} = bank_account, attrs) do
    with {:ok, default_kbe_code_id} <- resolve_default_kbe_code_id(company_id),
         {:ok, default_knp_code_id} <- resolve_default_knp_code_id(company_id) do
      attrs
      |> put_missing_code_id("kbe_code_id", bank_account.kbe_code_id || default_kbe_code_id)
      |> put_missing_code_id("knp_code_id", bank_account.knp_code_id || default_knp_code_id)
      |> then(&{:ok, &1})
    end
  end

  defp put_missing_code_id(attrs, key, value) do
    atom_key = String.to_existing_atom(key)

    attrs
    |> Map.new()
    |> then(fn attrs_map ->
      existing = Map.get(attrs_map, key) || Map.get(attrs_map, atom_key)

      cond do
        is_binary(existing) and String.trim(existing) != "" ->
          attrs_map

        existing != nil ->
          attrs_map

        true ->
          Map.put(attrs_map, key, value)
      end
    end)
  end

  defp resolve_default_kbe_code_id(company_id) do
    resolve_default_code_id(company_id, :kbe_code_id, KbeCode, :kbe_code_required)
  end

  defp resolve_default_knp_code_id(company_id) do
    resolve_default_code_id(company_id, :knp_code_id, KnpCode, :knp_code_required)
  end

  defp resolve_default_code_id(company_id, field, schema, error_tag) do
    from(a in CompanyBankAccount,
      where: a.company_id == ^company_id and a.is_default == true,
      order_by: [desc: a.inserted_at],
      limit: 1,
      select: field(a, ^field)
    )
    |> Repo.one()
    |> case do
      code_id when is_binary(code_id) and code_id != "" ->
        {:ok, code_id}

      _ ->
        case Repo.one(from(s in schema, order_by: [asc: s.code], limit: 1, select: s.id)) do
          nil -> {:error, error_tag}
          code_id -> {:ok, code_id}
        end
    end
  end

  defp requested_default?(attrs) when is_map(attrs) do
    attrs
    |> Map.get("is_default", Map.get(attrs, :is_default))
    |> then(&Ecto.Type.cast(:boolean, &1))
    |> case do
      {:ok, true} -> true
      _ -> false
    end
  end

  defp valid_company_bank_account?(%CompanyBankAccount{iban: iban}) do
    Iban.valid_checksum?(iban)
  end
end
