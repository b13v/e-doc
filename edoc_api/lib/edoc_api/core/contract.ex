defmodule EdocApi.Core.Contract do
  @moduledoc """
  Contract schema following Kazakhstan legal practice.
  A contract is a legal document between a seller (company) and a buyer.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.ContractStatus

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contracts" do
    # Identification
    field(:number, :string)
    field(:issue_date, :date)
    field(:city, :string)

    # Financial
    field(:currency, :string, default: "KZT")
    field(:vat_rate, :integer, default: 16)

    # Status
    field(:status, :string, default: ContractStatus.default())
    field(:issued_at, :utc_datetime)
    field(:signed_at, :utc_datetime)

    # Legacy field (kept for backward compatibility)
    field(:title, :string)
    field(:body_html, :string)

    # Buyer details (for external counterparties not in system)
    field(:buyer_name, :string)
    field(:buyer_legal_form, :string)
    field(:buyer_bin_iin, :string)
    field(:buyer_address, :string)
    field(:buyer_director_name, :string)
    field(:buyer_director_title, :string)
    field(:buyer_basis, :string)
    field(:buyer_phone, :string)
    field(:buyer_email, :string)

    # Relationships
    belongs_to(:company, EdocApi.Core.Company)
    belongs_to(:buyer_company, EdocApi.Core.Company)
    belongs_to(:bank_account, EdocApi.Core.CompanyBankAccount)

    has_many(:invoices, EdocApi.Core.Invoice)
    has_many(:contract_items, EdocApi.Core.ContractItem)

    timestamps(type: :utc_datetime)
  end

  # Buyer fields (for external buyers)
  @buyer_fields ~w(
    buyer_name
    buyer_legal_form
    buyer_bin_iin
    buyer_address
    buyer_director_name
    buyer_director_title
    buyer_basis
    buyer_phone
    buyer_email
  )a

  @required_fields ~w(number issue_date)a
  @optional_fields ~w(
    city
    currency
    vat_rate
    status
    issued_at
    signed_at
    title
    body_html
    buyer_company_id
    bank_account_id
  )a ++ @buyer_fields

  @doc """
  Creates a changeset for a contract.

  ## Parameters
  - contract: the contract struct
  - attrs: the attributes to cast
  - seller_company_id: the seller's company ID (required, from authenticated user)
  """
  def changeset(contract, attrs, seller_company_id) do
    contract
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> maybe_put_default_status()
    |> sanitize_body_html()
    |> put_change(:company_id, seller_company_id)
    |> validate_required(@required_fields ++ [:company_id])
    |> validate_inclusion(:status, ContractStatus.all())
    |> validate_inclusion(:currency, ~w(KZT USD EUR RUB))
    |> validate_inclusion(:vat_rate, [0, 12, 16])
    |> unique_constraint(:number, name: :contracts_company_id_number_index)
    |> validate_buyer_details()
  end

  @doc """
  Creates a changeset for updating an existing contract.
  """
  def update_changeset(contract, attrs) do
    contract
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> sanitize_body_html()
    |> validate_inclusion(:status, ContractStatus.all())
    |> validate_inclusion(:currency, ~w(KZT USD EUR RUB))
    |> validate_inclusion(:vat_rate, [0, 12, 16])
    |> validate_buyer_details()
  end

  defp maybe_put_default_status(changeset) do
    case get_field(changeset, :status) do
      nil -> put_change(changeset, :status, ContractStatus.default())
      _status -> changeset
    end
  end

  defp sanitize_body_html(changeset) do
    case get_change(changeset, :body_html) do
      nil ->
        changeset

      body_html ->
        sanitized = HtmlSanitizeEx.basic_html(body_html)
        put_change(changeset, :body_html, sanitized)
    end
  end

  # Validate that either buyer_company_id is set OR buyer details are provided
  defp validate_buyer_details(changeset) do
    buyer_company_id = get_field(changeset, :buyer_company_id)
    buyer_name = get_field(changeset, :buyer_name)
    buyer_bin_iin = get_field(changeset, :buyer_bin_iin)

    cond do
      # Buyer company is set - no need for buyer details
      buyer_company_id != nil ->
        changeset

      # Buyer details provided - validate required ones
      buyer_name != nil and buyer_bin_iin != nil ->
        changeset

      # New contract without buyer info
      is_new?(changeset) and buyer_name == nil ->
        changeset

      # Update without buyer info but no buyer_company
      true ->
        add_error(
          changeset,
          :buyer_name,
          "must provide either buyer_company_id or buyer details (buyer_name, buyer_bin_iin)"
        )
    end
  end

  defp is_new?(changeset) do
    get_field(changeset, :id) == nil
  end

  @doc """
  Returns the effective buyer name for this contract.
  """
  def buyer_name(%__MODULE__{buyer_company: %EdocApi.Core.Company{name: name}}),
    do: name

  def buyer_name(%__MODULE__{buyer_name: name}), do: name
  def buyer_name(_), do: nil

  @doc """
  Returns the effective buyer BIN/IIN for this contract.
  """
  def buyer_bin_iin(%__MODULE__{buyer_company: %EdocApi.Core.Company{bin_iin: bin}}),
    do: bin

  def buyer_bin_iin(%__MODULE__{buyer_bin_iin: bin}), do: bin
  def buyer_bin_iin(_), do: nil

  @doc """
  Returns the effective buyer address for this contract.
  """
  def buyer_address(%__MODULE__{buyer_company: %EdocApi.Core.Company{address: addr}}),
    do: addr

  def buyer_address(%__MODULE__{buyer_address: addr}), do: addr
  def buyer_address(_), do: nil
end
