defmodule EdocApi.Accounts do
  import Ecto.Query, warn: false
  alias EdocApi.Repo
  alias EdocApi.Accounts.User
  alias EdocApi.Auth.RefreshToken
  alias EdocApi.Errors

  @lockout_threshold 5
  @auth_failure_delay_ms 100
  @default_refresh_ttl_seconds 30 * 24 * 60 * 60

  def get_user(id) when is_binary(id), do: Repo.get(User, id)
  def get_user(_), do: nil

  def get_user_by_email(email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()
    Repo.get_by(User, email: email)
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
    |> Errors.from_changeset()
  end

  def authenticate_user(email, password) do
    case get_user_by_email(email) do
      nil ->
        Argon2.no_user_verify()
        auth_failure_delay()
        Errors.business_rule(:invalid_credentials, %{email: email})

      user ->
        cond do
          account_locked?(user) ->
            auth_failure_delay()

            Errors.business_rule(:account_locked, %{locked_until: user.locked_until})

          Argon2.verify_pass(password, user.password_hash) ->
            {:ok, reset_login_security(user)}

          true ->
            register_failed_login(user)
        end
    end
  end

  def issue_refresh_token(user_id) when is_binary(user_id) do
    token = generate_refresh_token()
    token_hash = hash_refresh_token(token)

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(refresh_ttl_seconds(), :second)
      |> DateTime.truncate(:second)

    case %RefreshToken{}
         |> RefreshToken.changeset(%{
           user_id: user_id,
           token_hash: token_hash,
           expires_at: expires_at
         })
         |> Repo.insert() do
      {:ok, _} -> {:ok, token}
      {:error, _} -> {:error, :refresh_token_issue_failed}
    end
  end

  def rotate_refresh_token(token) when is_binary(token) do
    token_hash = hash_refresh_token(token)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      query =
        from(rt in RefreshToken,
          where: rt.token_hash == ^token_hash,
          where: is_nil(rt.revoked_at),
          where: rt.expires_at > ^now,
          preload: [:user],
          lock: "FOR UPDATE"
        )

      case Repo.one(query) do
        nil ->
          Repo.rollback(:invalid_refresh_token)

        %RefreshToken{} = current_token ->
          new_token = generate_refresh_token()
          new_token_hash = hash_refresh_token(new_token)

          expires_at =
            DateTime.utc_now()
            |> DateTime.add(refresh_ttl_seconds(), :second)
            |> DateTime.truncate(:second)

          case %RefreshToken{}
               |> RefreshToken.changeset(%{
                 user_id: current_token.user_id,
                 token_hash: new_token_hash,
                 expires_at: expires_at
               })
               |> Repo.insert() do
            {:ok, replacement_token} ->
              current_token
              |> Ecto.Changeset.change(revoked_at: now, replaced_by_id: replacement_token.id)
              |> Repo.update!()

              {current_token.user, new_token}

            {:error, _changeset} ->
              Repo.rollback(:refresh_token_issue_failed)
          end
      end
    end)
    |> case do
      {:ok, {user, replacement_token}} -> {:ok, user, replacement_token}
      {:error, :invalid_refresh_token} -> {:error, :invalid_refresh_token}
      {:error, :refresh_token_issue_failed} -> {:error, :refresh_token_issue_failed}
      {:error, _} -> {:error, :invalid_refresh_token}
    end
  end

  def revoke_refresh_token(token) when is_binary(token) do
    token_hash = hash_refresh_token(token)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(rt in RefreshToken,
      where: rt.token_hash == ^token_hash,
      where: is_nil(rt.revoked_at)
    )
    |> Repo.update_all(set: [revoked_at: now, updated_at: now])

    :ok
  end

  @doc """
  Returns user with verified status check.
  """
  def get_user_with_verification_status(id) when is_binary(id) do
    case Repo.get(User, id) do
      nil -> nil
      user -> %{user: user, verified: user.verified_at != nil}
    end
  end

  @doc """
  Checks if a user is verified.
  """
  def user_verified?(id) when is_binary(id) do
    case Repo.get(User, id) do
      %User{verified_at: nil} -> false
      %User{} -> true
      nil -> false
    end
  end

  @doc """
  Marks a user's email as verified (for testing purposes).
  """
  def mark_email_verified!(id) when is_binary(id) do
    user = Repo.get!(User, id)

    user
    |> Ecto.Changeset.change(verified_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update!()
  end

  defp account_locked?(%User{locked_until: nil}), do: false

  defp account_locked?(%User{locked_until: %DateTime{} = locked_until}) do
    DateTime.compare(locked_until, DateTime.utc_now()) == :gt
  end

  defp reset_login_security(%User{} = user) do
    if user.failed_login_attempts > 0 || not is_nil(user.locked_until) do
      user
      |> Ecto.Changeset.change(failed_login_attempts: 0, locked_until: nil)
      |> Repo.update!()
    else
      user
    end
  end

  defp register_failed_login(%User{} = user) do
    attempts = user.failed_login_attempts + 1
    locked_until = calculate_lock_until(attempts)

    user
    |> Ecto.Changeset.change(failed_login_attempts: attempts, locked_until: locked_until)
    |> Repo.update!()

    auth_failure_delay()

    if attempts >= @lockout_threshold and not is_nil(locked_until) do
      Errors.business_rule(:account_locked, %{locked_until: locked_until})
    else
      Errors.business_rule(:invalid_credentials, %{email: user.email})
    end
  end

  defp calculate_lock_until(attempts) when attempts < @lockout_threshold, do: nil

  defp calculate_lock_until(attempts) do
    lock_seconds = min(60 * (attempts - @lockout_threshold + 1), 15 * 60)

    DateTime.utc_now()
    |> DateTime.add(lock_seconds, :second)
    |> DateTime.truncate(:second)
  end

  defp auth_failure_delay, do: Process.sleep(@auth_failure_delay_ms)

  defp generate_refresh_token do
    :crypto.strong_rand_bytes(48)
    |> Base.url_encode64(padding: false)
  end

  defp hash_refresh_token(token) do
    :sha256
    |> :crypto.hash(token)
    |> Base.encode16(case: :lower)
  end

  defp refresh_ttl_seconds do
    case Application.get_env(:edoc_api, EdocApi.Auth, [])[:refresh_ttl_seconds] do
      ttl when is_integer(ttl) and ttl > 0 -> ttl
      _ -> @default_refresh_ttl_seconds
    end
  end
end
