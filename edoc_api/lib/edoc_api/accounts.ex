defmodule EdocApi.Accounts do
  import Ecto.Query, warn: false
  alias EdocApi.Repo
  alias EdocApi.Accounts.User
  alias EdocApi.Auth.RefreshToken
  alias EdocApi.Core.{Act, Company, Contract, Invoice, TenantMembership}
  alias EdocApi.DocumentDelivery.PublicAccessToken
  alias EdocApi.Documents.GeneratedDocument
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

  def update_user_profile(user_id, attrs) when is_binary(user_id) and is_map(attrs) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{} = user ->
        user
        |> User.profile_changeset(attrs)
        |> Repo.update()
        |> Errors.from_changeset()
    end
  end

  def update_user_password(user_id, current_password, new_password, password_confirmation)
      when is_binary(user_id) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{} = user ->
        if Argon2.verify_pass(current_password || "", user.password_hash) do
          user
          |> User.password_update_changeset(%{
            "password" => new_password,
            "password_confirmation" => password_confirmation
          })
          |> Repo.update()
          |> Errors.from_changeset()
        else
          Errors.business_rule(:invalid_current_password)
        end
    end
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

  def revoke_all_refresh_tokens(user_id) when is_binary(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(rt in RefreshToken,
      where: rt.user_id == ^user_id,
      where: is_nil(rt.revoked_at)
    )
    |> Repo.update_all(set: [revoked_at: now, updated_at: now])

    :ok
  end

  def offboard_member_from_company(company_id, membership_id, member_user_id, owner_user_id)
      when is_binary(company_id) and is_binary(membership_id) and is_binary(member_user_id) and
             is_binary(owner_user_id) do
    now = utc_now()

    Repo.transaction(fn ->
      with :ok <- reassign_company_invoices(company_id, member_user_id, owner_user_id, now),
           :ok <- reassign_company_acts(company_id, member_user_id, owner_user_id, now),
           :ok <- delete_membership(company_id, membership_id, member_user_id),
           :ok <- delete_public_tokens_for_company(company_id, member_user_id),
           :ok <- delete_generated_documents_for_company(company_id, member_user_id),
           {:ok, blockers} <- offboarding_blockers(member_user_id),
           {:ok, mode} <- maybe_hard_delete_user(member_user_id, blockers) do
        %{mode: mode, membership_id: membership_id, user_id: member_user_id}
      else
        {:error, :invoice_number_conflict_on_reassign} ->
          Repo.rollback(:invoice_number_conflict_on_reassign)

        {:error, :reassign_failed} ->
          Repo.rollback(:reassign_failed)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, :invoice_number_conflict_on_reassign} -> {:error, :invoice_number_conflict_on_reassign}
      {:error, :reassign_failed} -> {:error, :reassign_failed}
      {:error, reason} -> {:error, reason}
    end
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

  defp reassign_company_invoices(company_id, member_user_id, owner_user_id, now) do
    if invoice_number_conflict_on_reassign?(company_id, member_user_id, owner_user_id) do
      {:error, :invoice_number_conflict_on_reassign}
    else
      case from(i in Invoice, where: i.company_id == ^company_id and i.user_id == ^member_user_id)
           |> Repo.update_all(set: [user_id: owner_user_id, updated_at: now]) do
        {_count, _} -> :ok
        _ -> {:error, :reassign_failed}
      end
    end
  rescue
    _ -> {:error, :reassign_failed}
  end

  defp reassign_company_acts(company_id, member_user_id, owner_user_id, now) do
    case from(a in Act, where: a.company_id == ^company_id and a.user_id == ^member_user_id)
         |> Repo.update_all(set: [user_id: owner_user_id, updated_at: now]) do
      {_count, _} -> :ok
      _ -> {:error, :reassign_failed}
    end
  rescue
    _ -> {:error, :reassign_failed}
  end

  defp delete_membership(company_id, membership_id, member_user_id) do
    case from(m in TenantMembership,
           where:
             m.id == ^membership_id and m.company_id == ^company_id and m.user_id == ^member_user_id
         )
         |> Repo.delete_all() do
      {1, _} -> :ok
      {0, _} -> {:error, :reassign_failed}
      _ -> {:error, :reassign_failed}
    end
  rescue
    _ -> {:error, :reassign_failed}
  end

  defp delete_public_tokens_for_company(company_id, member_user_id) do
    with {:ok, invoice_ids} <- company_invoice_ids(company_id),
         :ok <- delete_public_tokens(member_user_id, "invoice", invoice_ids),
         {:ok, act_ids} <- company_act_ids(company_id),
         :ok <- delete_public_tokens(member_user_id, "act", act_ids),
         {:ok, contract_ids} <- company_contract_ids(company_id),
         :ok <- delete_public_tokens(member_user_id, "contract", contract_ids) do
      :ok
    else
      {:error, _} -> {:error, :reassign_failed}
    end
  rescue
    _ -> {:error, :reassign_failed}
  end

  defp delete_generated_documents_for_company(company_id, member_user_id) do
    with {:ok, invoice_ids} <- company_invoice_ids(company_id),
         :ok <- delete_generated_documents(member_user_id, "invoice", invoice_ids),
         {:ok, act_ids} <- company_act_ids(company_id),
         :ok <- delete_generated_documents(member_user_id, "act", act_ids),
         {:ok, contract_ids} <- company_contract_ids(company_id),
         :ok <- delete_generated_documents(member_user_id, "contract", contract_ids) do
      :ok
    else
      {:error, _} -> {:error, :reassign_failed}
    end
  rescue
    _ -> {:error, :reassign_failed}
  end

  defp company_invoice_ids(company_id) do
    {:ok, Repo.all(from(i in Invoice, where: i.company_id == ^company_id, select: i.id))}
  end

  defp company_act_ids(company_id) do
    {:ok, Repo.all(from(a in Act, where: a.company_id == ^company_id, select: a.id))}
  end

  defp company_contract_ids(company_id) do
    {:ok, Repo.all(from(c in Contract, where: c.company_id == ^company_id, select: c.id))}
  end

  defp delete_public_tokens(member_user_id, document_type, document_ids) when is_list(document_ids) do
    if document_ids == [] do
      :ok
    else
      from(t in PublicAccessToken,
        where:
          t.created_by_user_id == ^member_user_id and t.document_type == ^document_type and
            t.document_id in ^document_ids
      )
      |> Repo.delete_all()

      :ok
    end
  rescue
    _ -> {:error, :reassign_failed}
  end

  defp delete_generated_documents(member_user_id, document_type, document_ids) when is_list(document_ids) do
    if document_ids == [] do
      :ok
    else
      from(g in GeneratedDocument,
        where:
          g.user_id == ^member_user_id and g.document_type == ^document_type and
            g.document_id in ^document_ids
      )
      |> Repo.delete_all()

      :ok
    end
  rescue
    _ -> {:error, :reassign_failed}
  end

  defp offboarding_blockers(member_user_id) do
    blockers =
      []
      |> maybe_add_blocker(company_ownership_blocker?(member_user_id), :company_ownership)
      |> maybe_add_blocker(company_membership_blocker?(member_user_id), :tenant_memberships)
      |> maybe_add_blocker(invoice_blocker?(member_user_id), :invoices)
      |> maybe_add_blocker(act_blocker?(member_user_id), :acts)

    {:ok, blockers}
  rescue
    _ -> {:error, :reassign_failed}
  end

  defp maybe_add_blocker(blockers, true, blocker), do: [blocker | blockers]
  defp maybe_add_blocker(blockers, false, _blocker), do: blockers

  defp company_ownership_blocker?(member_user_id) do
    Repo.exists?(from(c in Company, where: c.user_id == ^member_user_id))
  end

  defp company_membership_blocker?(member_user_id) do
    Repo.exists?(from(m in TenantMembership, where: m.user_id == ^member_user_id))
  end

  defp invoice_blocker?(member_user_id) do
    Repo.exists?(from(i in Invoice, where: i.user_id == ^member_user_id))
  end

  defp act_blocker?(member_user_id) do
    Repo.exists?(from(a in Act, where: a.user_id == ^member_user_id))
  end

  defp maybe_hard_delete_user(member_user_id, blockers) when is_list(blockers) do
    if blockers == [] do
      case delete_all_generated_documents_for_user(member_user_id) do
        :ok ->
          case Repo.get(User, member_user_id) do
            nil ->
              {:ok, :hard_deleted_user}

            %User{} = user ->
              case Repo.delete(user) do
                {:ok, _user} -> {:ok, :hard_deleted_user}
                {:error, _changeset} -> {:error, :reassign_failed}
              end
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, :company_removed_only}
    end
  rescue
    _ -> {:error, :reassign_failed}
  end

  defp delete_all_generated_documents_for_user(member_user_id) do
    from(g in GeneratedDocument, where: g.user_id == ^member_user_id)
    |> Repo.delete_all()

    :ok
  rescue
    _ -> {:error, :reassign_failed}
  end

  defp invoice_number_conflict_on_reassign?(company_id, member_user_id, owner_user_id) do
    conflict_query =
      from(member_invoice in Invoice,
        where:
          member_invoice.company_id == ^company_id and
            member_invoice.user_id == ^member_user_id and
            not is_nil(member_invoice.number),
        join: owner_invoice in Invoice,
        on:
          owner_invoice.company_id == member_invoice.company_id and
            owner_invoice.user_id == ^owner_user_id and
            owner_invoice.number == member_invoice.number,
        select: member_invoice.id,
        limit: 1
      )

    Repo.exists?(conflict_query)
  rescue
    _ -> false
  end

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
