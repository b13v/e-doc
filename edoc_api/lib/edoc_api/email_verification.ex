defmodule EdocApi.EmailVerification do
  @moduledoc """
  Context module for email verification tokens and verification logic.
  """

  import Ecto.Query, warn: false
  require Logger

  alias EdocApi.Repo
  alias EdocApi.Accounts.User
  alias EdocApi.EmailVerificationToken

  @token_length 32
  @default_expiry_hours 24
  @resend_expiry_hours 1
  @max_resend_per_hour 3

  defmodule Token do
    @moduledoc """
    Struct representing an email verification token.
    """
    defstruct [:token, :token_hash, :expires_at, :user_id]

    @type t :: %__MODULE__{
            token: String.t(),
            token_hash: String.t(),
            expires_at: DateTime.t(),
            user_id: Ecto.UUID.t()
          }
  end

  @doc """
  Creates a new verification token for a user.
  Generates a secure random token, stores its hash, and returns the raw token.
  """
  def create_token_for_user(user_id) when is_binary(user_id) do
    token = generate_secure_token()
    token_hash = hash_token(token)
    expiry_hours = get_expiry_hours(user_id)

    %EmailVerificationToken{}
    |> EmailVerificationToken.changeset(%{
      user_id: user_id,
      token_hash: token_hash,
      expires_at: DateTime.utc_now() |> DateTime.add(expiry_hours * 3600, :second)
    })
    |> Repo.insert()
    |> case do
      {:ok, db_token} ->
        Logger.info("Created email verification token for user #{user_id}")

        {:ok,
         %Token{
           token: token,
           token_hash: token_hash,
           expires_at: db_token.expires_at,
           user_id: user_id
         }}

      {:error, changeset} ->
        Logger.error("Failed to create verification token: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Verifies a token by its string value.
  Returns {:ok, user_id} if valid, {:error, reason} otherwise.
  """
  def verify_token(token) when is_binary(token) do
    token_hash = hash_token(token)

    query =
      from(t in EmailVerificationToken,
        where: t.token_hash == ^token_hash,
        where: is_nil(t.used_at),
        where: t.expires_at > ^DateTime.utc_now(),
        preload: [:user],
        limit: 1
      )

    case Repo.one(query) do
      %EmailVerificationToken{user: %User{} = user} = db_token ->
        if user.verified_at != nil do
          {:error, :already_verified}
        else
          Repo.transaction(fn ->
            Repo.update!(Ecto.Changeset.change(db_token, used_at: DateTime.utc_now()))
            Repo.update!(Ecto.Changeset.change(user, verified_at: DateTime.utc_now()))
          end)

          Logger.info("Email verified successfully for user #{user.id}")
          {:ok, user.id}
        end

      nil ->
        {:error, :invalid_or_expired_token}
    end
  end

  @doc """
  Checks if a user has verified their email.
  """
  def user_verified?(user_id) when is_binary(user_id) do
    case Repo.get(User, user_id) do
      %User{verified_at: nil} -> false
      %User{} -> true
      nil -> false
    end
  end

  @doc """
  Gets the latest unexpired, unused token for a user.
  Returns {:ok, token} if exists, {:error, :not_found} otherwise.
  """
  def get_latest_token(user_id) when is_binary(user_id) do
    query =
      from(t in EmailVerificationToken,
        where: t.user_id == ^user_id,
        where: is_nil(t.used_at),
        where: t.expires_at > ^DateTime.utc_now(),
        order_by: [desc: t.inserted_at],
        limit: 1
      )

    case Repo.one(query) do
      %EmailVerificationToken{} = token ->
        {:ok, token}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Checks if a user can resend verification email.
  Returns {:ok, :allowed} or {:error, :rate_limited}.
  """
  def can_resend?(user_id) when is_binary(user_id) do
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second)

    count =
      from(t in EmailVerificationToken,
        where: t.user_id == ^user_id,
        where: t.inserted_at > ^one_hour_ago
      )
      |> Repo.aggregate(:count, :id)

    if count < @max_resend_per_hour do
      {:ok, :allowed}
    else
      {:error, :rate_limited}
    end
  end

  @doc """
  Deletes all expired or used tokens for a user.
  Called periodically for cleanup.
  """
  def cleanup_tokens_for_user(user_id) when is_binary(user_id) do
    from(t in EmailVerificationToken,
      where: t.user_id == ^user_id,
      where: t.expires_at <= ^DateTime.utc_now() or not is_nil(t.used_at)
    )
    |> Repo.delete_all()

    :ok
  end

  defp generate_secure_token do
    :crypto.strong_rand_bytes(@token_length)
    |> Base.url_encode64(padding: false)
  end

  defp hash_token(token) do
    :sha256
    |> :crypto.hash(token)
    |> Base.encode16()
  end

  defp get_expiry_hours(user_id) do
    case get_latest_token(user_id) do
      {:ok, _} -> @resend_expiry_hours
      {:error, :not_found} -> @default_expiry_hours
    end
  end
end
