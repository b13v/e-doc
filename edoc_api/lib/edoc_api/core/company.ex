defmodule EdocApi.Core.Company do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "companies" do
    field(:name, :string)
    field(:legal_form, :string)
    field(:bin_iin, :string)
    field(:city, :string)
    field(:address, :string)
    field(:bank, :string)
    field(:iban, :string)
    field(:email, :string)
    field(:phone, :string)
    field(:representative_name, :string)
    field(:representative_title, :string)
    field(:basis, :string)

    belongs_to(:user, EdocApi.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(
    name
    legal_form
    bin_iin
    city
    address
    bank
    iban
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
    |> validate_bin_iin()
    |> validate_iban()
    |> validate_email()
    |> validate_phone()
  end

  # -------------------------
  # Normalization
  # -------------------------

  defp normalize_fields(changeset) do
    changeset
    |> update_change(:bin_iin, &normalize_digits/1)
    |> update_change(:iban, &normalize_iban/1)
    |> update_change(:email, &normalize_email/1)
    |> update_change(:city, &normalize_trim/1)
    |> update_change(:address, &normalize_trim/1)
    |> update_change(:bank, &normalize_trim/1)
    |> update_change(:name, &normalize_trim/1)
    |> update_change(:representative_name, &normalize_trim/1)
    |> update_change(:representative_title, &normalize_trim/1)
    |> update_change(:basis, &normalize_trim/1)
    |> maybe_normalize_phone()
  end

  defp normalize_digits(nil), do: nil

  defp normalize_digits(value) when is_binary(value),
    do: value |> String.replace(~r/\D+/, "")

  defp normalize_iban(nil), do: nil

  defp normalize_iban(value) when is_binary(value),
    do: value |> String.replace(~r/\s+/, "") |> String.upcase()

  defp normalize_email(nil), do: nil

  defp normalize_email(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  defp normalize_trim(nil), do: nil
  defp normalize_trim(value) when is_binary(value), do: String.trim(value)

  # -------------------------
  # Validations
  # -------------------------

  defp validate_bin_iin(changeset) do
    changeset
    |> validate_length(:bin_iin, is: 12)
    |> validate_format(:bin_iin, ~r/^\d{12}$/, message: "must contain exactly 12 digits")
  end

  defp validate_iban(changeset) do
    changeset
    |> validate_length(:iban, min: 15, max: 34)
    |> validate_format(
      :iban,
      ~r/^[A-Z]{2}\d{2}[A-Z0-9]+$/,
      message: "invalid IBAN format"
    )
  end

  defp validate_email(changeset) do
    case get_change(changeset, :email) do
      nil ->
        changeset

      _ ->
        validate_format(
          changeset,
          :email,
          ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
          message: "invalid email"
        )
    end
  end

  # -------------------------
  # Phone (soft validation)
  # -------------------------

  defp maybe_normalize_phone(changeset) do
    case get_change(changeset, :phone) do
      nil ->
        changeset

      phone when is_binary(phone) ->
        phone = String.trim(phone)

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
    digits = String.replace(input, ~r/\D+/, "")

    normalized_digits =
      cond do
        String.length(digits) == 11 and String.starts_with?(digits, "8") ->
          "7" <> String.slice(digits, 1, 10)

        String.length(digits) == 11 and String.starts_with?(digits, "7") ->
          digits

        String.length(digits) == 10 ->
          "7" <> digits

        true ->
          nil
      end

    with "7" <> rest <- normalized_digits,
         true <- String.length(rest) == 10,
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
    warnings = get_private(changeset, :warnings, [])

    put_private(changeset, :warnings, [%{field: field, message: message} | warnings])
  end

  @spec warnings_from_changeset(Ecto.Changeset.t()) :: map()
  def warnings_from_changeset(%Ecto.Changeset{} = changeset) do
    changeset
    |> get_private(:warnings, [])
    |> Enum.reverse()
    |> Enum.group_by(fn %{field: field} -> field end, fn %{message: message} -> message end)
  end

  defp get_private(%Ecto.Changeset{} = changeset, key, default) when is_atom(key) do
    changeset
    |> Map.get(:private, %{})
    |> Map.get(key, default)
  end

  defp put_private(%Ecto.Changeset{} = changeset, key, value) when is_atom(key) do
    private = Map.get(changeset, :private, %{})
    Map.put(changeset, :private, Map.put(private, key, value))
  end
end
