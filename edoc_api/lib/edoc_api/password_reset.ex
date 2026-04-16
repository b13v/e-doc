defmodule EdocApi.PasswordReset do
  @moduledoc """
  Password reset token issuance, verification, and password change flow.
  """

  import Ecto.Query, warn: false
  require Logger

  alias EdocApi.Accounts
  alias EdocApi.Accounts.User
  alias EdocApi.Accounts.UserCache
  alias EdocApi.EmailSender
  alias EdocApi.PasswordResetToken
  alias EdocApi.Repo

  @token_length_bytes 32
  @token_expiry_hours 24
  @reset_cooldown_seconds 60
  @max_requests_per_hour 3

  def request_reset(email, locale) when is_binary(email) do
    case Accounts.get_user_by_email(email) do
      nil ->
        {:ok, :accepted}

      %User{} = user ->
        issue_reset_token(user, locale, not throttled?(user.id))
    end
  end

  def verify_token(token) when is_binary(token) do
    case lookup_token(token) do
      %PasswordResetToken{} = token_row ->
        {:ok, %{user_id: token_row.user_id, token_hash: token_row.token_hash}}

      nil ->
        {:error, :invalid_or_expired}
    end
  end

  def reset_password(token, password, confirmation) when is_binary(token) do
    token_hash = hash_token(token)
    now = utc_now()

    Repo.transaction(fn ->
      query =
        from(t in PasswordResetToken,
          where: t.token_hash == ^token_hash,
          where: is_nil(t.used_at),
          where: t.expires_at > ^now,
          lock: "FOR UPDATE",
          limit: 1
        )

      case Repo.one(query) do
        nil ->
          Repo.rollback(:invalid_or_expired)

        %PasswordResetToken{} = token_row ->
          user = Repo.get!(User, token_row.user_id)

          changeset =
            User.password_update_changeset(user, %{
              "password" => password,
              "password_confirmation" => confirmation
            })

          if changeset.valid? do
            case Repo.update(changeset) do
              {:ok, _user} ->
                token_row
                |> Ecto.Changeset.change(used_at: now)
                |> Repo.update!()

                Accounts.revoke_all_refresh_tokens(user.id)
                UserCache.invalidate(user.id)
                :password_reset

              {:error, changeset} ->
                Repo.rollback({:validation_failed, changeset})
            end
          else
            Repo.rollback({:validation_failed, changeset})
          end
      end
    end)
    |> case do
      {:ok, :password_reset} -> {:ok, :password_reset}
      {:error, :invalid_or_expired} -> {:error, :invalid_or_expired}
      {:error, {:validation_failed, changeset}} -> {:error, :validation_failed, changeset}
      {:error, _} -> {:error, :invalid_or_expired}
    end
  end

  defp issue_reset_token(%User{} = user, locale, send_email?) do
    token = generate_token()
    token_hash = hash_token(token)
    expires_at = DateTime.add(utc_now(), @token_expiry_hours * 3600, :second)

    case Repo.transaction(fn ->
           invalidate_active_tokens(user.id)

           %PasswordResetToken{}
           |> PasswordResetToken.changeset(%{
             user_id: user.id,
             token_hash: token_hash,
             expires_at: expires_at
           })
           |> Repo.insert()
         end) do
      {:ok, {:ok, _token_row}} ->
        if send_email? do
          send_reset_email(user.email, token, locale)
        end

        {:ok, :accepted}

      {:ok, {:error, changeset}} ->
        Logger.warning(
          "[PASSWORD_RESET] Failed to create reset token email=#{user.email} locale=#{locale} errors=#{inspect(changeset.errors)}"
        )

        {:ok, :accepted}

      {:error, reason} ->
        Logger.warning(
          "[PASSWORD_RESET] Reset token transaction failed email=#{user.email} locale=#{locale} reason=#{inspect(reason)}"
        )

        {:ok, :accepted}
    end
  end

  defp send_reset_email(recipient_email, token, locale) do
    case EmailSender.send_password_reset_email(recipient_email, token, locale) do
      {:ok, _receipt} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[PASSWORD_RESET] Password reset email delivery failed email=#{recipient_email} locale=#{locale} reason=#{inspect(reason)}"
        )

        :ok
    end
  end

  defp throttled?(user_id) do
    now = utc_now()
    cooldown_cutoff = DateTime.add(now, -@reset_cooldown_seconds, :second)
    hour_cutoff = DateTime.add(now, -3600, :second)

    latest_request =
      from(t in PasswordResetToken,
        where: t.user_id == ^user_id,
        order_by: [desc: t.inserted_at],
        limit: 1
      )
      |> Repo.one()

    recent_count =
      from(t in PasswordResetToken,
        where: t.user_id == ^user_id,
        where: t.inserted_at > ^hour_cutoff
      )
      |> Repo.aggregate(:count, :id)

    cooldown_active? =
      case latest_request do
        %PasswordResetToken{inserted_at: %DateTime{} = inserted_at} ->
          DateTime.compare(inserted_at, cooldown_cutoff) == :gt

        _ ->
          false
      end

    recent_count >= @max_requests_per_hour or cooldown_active?
  end

  defp invalidate_active_tokens(user_id) do
    now = utc_now()

    from(t in PasswordResetToken,
      where: t.user_id == ^user_id,
      where: is_nil(t.used_at),
      where: t.expires_at > ^now
    )
    |> Repo.update_all(set: [used_at: now, updated_at: now])

    :ok
  end

  defp lookup_token(token) do
    token_hash = hash_token(token)
    now = utc_now()

    from(t in PasswordResetToken,
      where: t.token_hash == ^token_hash,
      where: is_nil(t.used_at),
      where: t.expires_at > ^now,
      limit: 1
    )
    |> Repo.one()
  end

  defp generate_token do
    :crypto.strong_rand_bytes(@token_length_bytes)
    |> Base.url_encode64(padding: false)
  end

  defp hash_token(token) do
    :sha256
    |> :crypto.hash(token)
    |> Base.encode16(case: :lower)
  end

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
