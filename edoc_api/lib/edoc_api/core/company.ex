defmodule EdocApi.Core.Company do
  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.Validators.{BinIin, Email, String}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "companies" do
    field(:name, :string)
    field(:legal_form, :string)
    field(:bin_iin, :string)
    field(:city, :string)
    field(:address, :string)
    field(:email, :string)
    field(:phone, :string)
    field(:representative_name, :string)
    field(:representative_title, :string)
    field(:basis, :string)
    field(:warnings, {:array, :map}, virtual: true)

    has_many(:bank_accounts, EdocApi.Core.CompanyBankAccount)
    belongs_to(:user, EdocApi.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(
    name
    legal_form
    bin_iin
    city
    address
    phone
    representative_name
    representative_title
    basis
  )a

  @optional_fields ~w(email)a

  @doc """
  Variant B (recommended): user_id is NOT accepted from attrs.
  You must pass user_id explicitly from the authenticated user context.
  """
  def changeset(company, attrs, user_id) do
    company
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> put_change(:user_id, user_id)
    |> validate_required(@required_fields ++ [:user_id])
    |> normalize_fields()
    |> BinIin.validate(:bin_iin)
    |> Email.validate(:email)
    |> validate_phone()
  end

  # -------------------------
  # Normalization
  # -------------------------

  defp normalize_fields(changeset) do
    changeset
    |> update_change(:bin_iin, &BinIin.normalize/1)
    |> update_change(:email, &Email.normalize/1)
    |> update_change(:city, &String.normalize/1)
    |> update_change(:address, &String.normalize/1)
    |> update_change(:name, &String.normalize/1)
    |> update_change(:representative_name, &String.normalize/1)
    |> update_change(:representative_title, &String.normalize/1)
    |> update_change(:basis, &String.normalize/1)
    |> maybe_normalize_phone()
  end

  # -------------------------
  # Validations
  # -------------------------

  # -------------------------
  # Phone (soft validation)
  # -------------------------

  defp maybe_normalize_phone(changeset) do
    case get_change(changeset, :phone) do
      nil ->
        changeset

      phone when is_binary(phone) ->
        phone = Elixir.String.trim(phone)

        case normalize_kz_mobile_phone(phone) do
          {:ok, formatted} -> put_change(changeset, :phone, formatted)
          :error -> changeset
        end
    end
  end

  # Мягкая валидация: НЕ добавляет errors, только warning в changeset.private
  defp validate_phone(changeset) do
    phone = get_field(changeset, :phone)

    cond do
      is_nil(phone) or phone == "" ->
        # phone у тебя required, но на всякий — не ломаем, а предупреждаем
        add_warning(changeset, :phone, "phone is blank")

      not is_binary(phone) ->
        add_warning(changeset, :phone, "phone is not a string")

      true ->
        case normalize_kz_mobile_phone(phone) do
          {:ok, formatted} ->
            # если вдруг формат не совпадает, но номер распознан — нормализуем
            changeset |> put_change(:phone, formatted)

          :error ->
            add_warning(
              changeset,
              :phone,
              "phone must look like +7 (7xx) xxx xx xx. Got: #{inspect(phone)}"
            )
        end
    end
  end

  # Принимаем разные вводы:
  # +7 (777) 123 45 67
  # 87771234567
  # 7771234567
  # 7 777 123 4567
  #
  # Возвращаем ТОЛЬКО канон: +7 (DDD) DDD DD DD
  # и только для мобильных KZ: 7xx

  defp normalize_kz_mobile_phone(input) when is_binary(input) do
    digits = Elixir.String.replace(input, ~r/\D+/, "")

    normalized_digits =
      cond do
        Elixir.String.length(digits) == 11 and Elixir.String.starts_with?(digits, "8") ->
          "7" <> Elixir.String.slice(digits, 1, 10)

        Elixir.String.length(digits) == 11 and Elixir.String.starts_with?(digits, "7") ->
          digits

        Elixir.String.length(digits) == 10 ->
          "7" <> digits

        true ->
          nil
      end

    with "7" <> rest <- normalized_digits,
         true <- Elixir.String.length(rest) == 10,
         <<code::binary-size(3), mid::binary-size(3), a::binary-size(2), b::binary-size(2)>> <-
           rest,
         true <- mobile_kz_code?(code) do
      {:ok, "+7 (#{code}) #{mid} #{a} #{b}"}
    else
      _ -> :error
    end
  end

  # defp mobile_kz_code?(code) when is_binary(code) do
  #   # KZ mobile обычно 700..799
  #   case Integer.parse(code) do
  #     {n, ""} -> n >= 700 and n <= 799
  #     _ -> false
  #   end
  # end
  defp mobile_kz_code?(code) when is_binary(code) do
    code in ~w(700 701 702 705 706 707 708 747 771 775 776 777 778)
  end

  # warnings храним в changeset.private[:warnings] как список карт:
  # [%{field: :phone, message: "..."}]
  @spec add_warning(Ecto.Changeset.t(), atom(), binary()) :: Ecto.Changeset.t()
  defp add_warning(%Ecto.Changeset{} = changeset, field, message)
       when is_atom(field) and is_binary(message) do
    warnings = get_change(changeset, :warnings, [])
    put_change(changeset, :warnings, [%{field: field, message: message} | warnings])
  end

  @spec warnings_from_changeset(Ecto.Changeset.t()) :: map()
  def warnings_from_changeset(%Ecto.Changeset{} = changeset) do
    changeset
    |> get_change(:warnings, [])
    |> Enum.reverse()
    |> Enum.group_by(fn %{field: field} -> field end, fn %{message: message} -> message end)
  end
end
