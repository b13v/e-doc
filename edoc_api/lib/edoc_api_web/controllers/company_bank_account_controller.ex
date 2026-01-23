defmodule EdocApiWeb.CompanyBankAccountController do
  use EdocApiWeb, :controller

  alias EdocApi.Payments
  alias EdocApi.Repo
  alias EdocApi.Core.KbeCode
  alias EdocApi.Core.KnpCode
  alias EdocApiWeb.{ErrorMapper, ControllerHelpers}
  alias EdocApiWeb.Serializers.BankAccountSerializer

  def index(conn, _params) do
    user = conn.assigns.current_user
    accounts = Payments.list_company_bank_accounts_for_user(user.id)

    json(conn, %{bank_accounts: Enum.map(accounts, &BankAccountSerializer.to_map/1)})
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    result =
      with {:ok, params} <- normalize_kbe_knp_ids(params),
           {:ok, acc} <- Payments.create_company_bank_account_for_user(user.id, params) do
        {:ok, acc}
      end

    error_map = %{
      invalid_kbe_code: &ErrorMapper.unprocessable(&1, "invalid_kbe_code"),
      invalid_knp_code: &ErrorMapper.unprocessable(&1, "invalid_knp_code")
    }

    ControllerHelpers.handle_common_result(
      conn,
      result,
      fn conn, acc ->
        conn |> put_status(:created) |> json(%{bank_account: BankAccountSerializer.to_map(acc)})
      end,
      error_map
    )
  end

  def set_default(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    bank_account_id = id

    error_map = %{
      company_required: &ErrorMapper.bad_request(&1, "company_required"),
      bank_account_not_found: &ErrorMapper.not_found(&1, "bank_account_not_found")
    }

    ControllerHelpers.handle_result(
      conn,
      Payments.set_default_bank_account(user.id, bank_account_id),
      fn conn, acc ->
        json(conn, %{bank_account: BankAccountSerializer.to_map(acc)})
      end,
      error_map
    )
  end

  defp normalize_kbe_knp_ids(params) do
    with {:ok, params} <- normalize_code_id(params, "kbe_code_id", KbeCode, :invalid_kbe_code),
         {:ok, params} <- normalize_code_id(params, "knp_code_id", KnpCode, :invalid_knp_code) do
      {:ok, params}
    end
  end

  defp normalize_code_id(params, key, schema, error_tag) do
    case Map.fetch(params, key) do
      :error ->
        {:ok, params}

      {:ok, nil} ->
        {:ok, params}

      {:ok, value} ->
        value = value |> to_string() |> String.trim()

        case Ecto.UUID.cast(value) do
          {:ok, _} ->
            {:ok, Map.put(params, key, value)}

          :error ->
            case Repo.get_by(schema, code: value) do
              nil -> {:error, error_tag}
              %{} = rec -> {:ok, Map.put(params, key, rec.id)}
            end
        end
    end
  end
end
