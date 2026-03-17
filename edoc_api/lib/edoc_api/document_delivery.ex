defmodule EdocApi.DocumentDelivery do
  import Ecto.Query, warn: false

  alias EdocApi.DocumentDelivery.Delivery
  alias EdocApi.DocumentDelivery.DocumentRenderer
  alias EdocApi.DocumentDelivery.DocumentResolver
  alias EdocApi.DocumentDelivery.EmailBuilder
  alias EdocApi.DocumentDelivery.PublicAccessToken
  alias EdocApi.DocumentDelivery.ShareTemplates
  alias EdocApi.Mailer
  alias EdocApi.Repo
  alias EdocApi.Validators.Email, as: EmailValidator

  @default_ttl_seconds 30 * 24 * 60 * 60

  def create_public_access_token(user_id, document_type, document_id, opts \\ [])
      when is_binary(user_id) do
    with {:ok, {normalized_type, _document}} <-
           DocumentResolver.get_for_user(user_id, document_type, document_id) do
      raw_token = generate_token()

      expires_at =
        DateTime.utc_now()
        |> DateTime.add(Keyword.get(opts, :ttl_seconds, ttl_seconds()), :second)

      %PublicAccessToken{}
      |> PublicAccessToken.changeset(%{
        token_hash: hash_token(raw_token),
        document_type: Atom.to_string(normalized_type),
        document_id: document_id,
        created_by_user_id: user_id,
        expires_at: expires_at
      })
      |> Repo.insert()
      |> case do
        {:ok, token} ->
          {:ok,
           %{
             token: raw_token,
             url: public_url(raw_token),
             public_access_token: token
           }}

        {:error, changeset} ->
          {:error, :validation, %{changeset: changeset}}
      end
    end
  end

  def get_public_document(raw_token) when is_binary(raw_token) do
    with {:ok, token} <- fetch_valid_token(raw_token),
         {:ok, {document_type, document}} <-
           DocumentResolver.get_public(token.document_type, token.document_id) do
      {:ok, build_public_document(document_type, document, raw_token, token)}
    end
  end

  def open_public_document(raw_token) when is_binary(raw_token) do
    with {:ok, token} <- fetch_valid_token(raw_token),
         {:ok, {document_type, document}} <-
           DocumentResolver.get_public(token.document_type, token.document_id),
         {:ok, _token} <- mark_token_opened(token) do
      {:ok, build_public_document(document_type, document, raw_token, token)}
    end
  end

  def get_public_document_pdf(raw_token) when is_binary(raw_token) do
    with {:ok, token} <- fetch_valid_token(raw_token),
         {:ok, {document_type, document}} <-
           DocumentResolver.get_public(token.document_type, token.document_id),
         {:ok, _token} <- mark_token_opened(token),
         {:ok, pdf_binary} <- renderer().render(document_type, document) do
      {:ok,
       %{
         pdf_binary: pdf_binary,
         filename: DocumentRenderer.filename(document_type, document)
       }}
    end
  end

  def revoke_public_access_token(user_id, token_id)
      when is_binary(user_id) and is_binary(token_id) do
    PublicAccessToken
    |> where([t], t.id == ^token_id and t.created_by_user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :public_token_not_found}

      token ->
        token
        |> Ecto.Changeset.change(revoked_at: now())
        |> Repo.update()
        |> case do
          {:ok, updated_token} -> {:ok, updated_token}
          {:error, changeset} -> {:error, :validation, %{changeset: changeset}}
        end
    end
  end

  def send_email(user_id, document_type, document_id, attrs)
      when is_binary(user_id) and is_map(attrs) do
    with {:ok, {normalized_type, document}} <-
           DocumentResolver.get_for_user(user_id, document_type, document_id),
         {:ok, recipient_email} <- validate_recipient_email(attrs),
         {:ok, pdf_binary} <- renderer().render(normalized_type, document),
         {:ok, token_data} <- create_public_access_token(user_id, normalized_type, document.id),
         {:ok, delivery} <-
           create_delivery(%{
             document_type: Atom.to_string(normalized_type),
             document_id: document.id,
             channel: "email",
             kind: "official",
             status: "pending",
             recipient_email: recipient_email,
             recipient_phone:
               Map.get(attrs, "recipient_phone") || Map.get(attrs, :recipient_phone),
             recipient_name: Map.get(attrs, "recipient_name") || Map.get(attrs, :recipient_name),
             public_access_token_id: token_data.public_access_token.id
           }),
         email <- EmailBuilder.build(normalized_type, document, pdf_binary, token_data.url, attrs) do
      case Mailer.deliver(email) do
        {:ok, _receipt} ->
          {:ok, sent_delivery} = mark_delivery_sent(delivery)

          {:ok,
           %{
             delivery: sent_delivery,
             public_link: token_data.url,
             document: document_payload(normalized_type, document),
             transport: email_transport()
           }}

        {:error, reason} ->
          {:ok, failed_delivery} = mark_delivery_failed(delivery, inspect(reason))

          {:error, :email_delivery_failed,
           %{
             delivery_id: failed_delivery.id,
             message: "Failed to send document email"
           }}
      end
    end
  end

  def generate_share(user_id, document_type, document_id, channel, attrs \\ %{})
      when is_binary(user_id) and is_map(attrs) do
    with {:ok, {normalized_type, document}} <-
           DocumentResolver.get_for_user(user_id, document_type, document_id),
         {:ok, normalized_channel} <- ShareTemplates.normalize_channel(channel),
         {:ok, token_data} <- create_public_access_token(user_id, normalized_type, document.id),
         {:ok, delivery} <-
           create_delivery(%{
             document_type: Atom.to_string(normalized_type),
             document_id: document.id,
             channel: Atom.to_string(normalized_channel),
             kind: "share",
             status: "pending",
             recipient_phone:
               Map.get(attrs, "recipient_phone") || Map.get(attrs, :recipient_phone),
             recipient_name: Map.get(attrs, "recipient_name") || Map.get(attrs, :recipient_name),
             public_access_token_id: token_data.public_access_token.id
           }),
         {:ok, share_payload} <-
           ShareTemplates.build(
             normalized_channel,
             Map.get(attrs, "locale") || Map.get(attrs, :locale),
             normalized_type,
             document,
             token_data.url,
             Map.get(attrs, "recipient_name") || Map.get(attrs, :recipient_name)
           ),
         {:ok, sent_delivery} <- mark_delivery_sent(delivery) do
      {:ok,
       %{
         delivery: sent_delivery,
         public_link: token_data.url,
         share: Map.put(share_payload, :public_link, token_data.url),
         document: document_payload(normalized_type, document)
       }}
    end
  end

  defp create_delivery(attrs) do
    %Delivery{}
    |> Delivery.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, delivery} -> {:ok, delivery}
      {:error, changeset} -> {:error, :validation, %{changeset: changeset}}
    end
  end

  defp mark_delivery_sent(delivery) do
    delivery
    |> Ecto.Changeset.change(status: "sent", sent_at: now())
    |> Repo.update()
  end

  defp mark_delivery_failed(delivery, error_message) do
    delivery
    |> Ecto.Changeset.change(status: "failed", error_message: error_message)
    |> Repo.update()
  end

  defp mark_token_opened(token) do
    timestamp = now()

    Repo.transaction(fn ->
      {:ok, updated_token} =
        token
        |> Ecto.Changeset.change(last_accessed_at: timestamp)
        |> Repo.update()

      from(d in Delivery,
        where: d.public_access_token_id == ^token.id and is_nil(d.opened_at)
      )
      |> Repo.update_all(set: [opened_at: timestamp, status: "opened"])

      updated_token
    end)
    |> case do
      {:ok, updated_token} -> {:ok, updated_token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_valid_token(raw_token) do
    token_hash = hash_token(raw_token)

    PublicAccessToken
    |> where([t], t.token_hash == ^token_hash)
    |> where([t], is_nil(t.revoked_at))
    |> where([t], t.expires_at > ^DateTime.utc_now())
    |> Repo.one()
    |> case do
      nil -> {:error, :public_token_not_found}
      token -> {:ok, token}
    end
  end

  defp build_public_document(document_type, document, raw_token, token) do
    DocumentRenderer.public_document(document_type, document, raw_token)
    |> Map.put(:expires_at, token.expires_at)
  end

  defp document_payload(document_type, document) do
    %{
      type: Atom.to_string(document_type),
      id: document.id,
      title: DocumentRenderer.title(document_type, document)
    }
  end

  defp validate_recipient_email(attrs) do
    email =
      attrs
      |> Map.get("recipient_email", Map.get(attrs, :recipient_email))
      |> EmailValidator.normalize()

    cond do
      is_nil(email) or email == "" ->
        {:error, :recipient_email_required}

      Regex.match?(EmailValidator.pattern(), email) ->
        {:ok, email}

      true ->
        {:error, :recipient_email_required}
    end
  end

  defp email_transport do
    case mailer_adapter() do
      Swoosh.Adapters.Local ->
        %{
          mode: "local_preview",
          warning:
            "SMTP is not configured. This email was captured by the local mailer adapter and was not delivered to the recipient inbox."
        }

      Swoosh.Adapters.Test ->
        %{
          mode: "test"
        }

      Swoosh.Adapters.SMTP ->
        %{
          mode: "smtp"
        }

      adapter when is_atom(adapter) ->
        %{
          mode: "adapter",
          adapter: Atom.to_string(adapter)
        }

      adapter ->
        %{
          mode: "adapter",
          adapter: inspect(adapter)
        }
    end
  end

  defp mailer_adapter do
    Application.get_env(:edoc_api, EdocApi.Mailer, [])
    |> Keyword.get(:adapter, Swoosh.Adapters.Local)
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  defp hash_token(token) do
    :sha256
    |> :crypto.hash(token)
    |> Base.encode16(case: :lower)
  end

  defp public_url(raw_token), do: "#{EdocApiWeb.Endpoint.url()}/public/docs/#{raw_token}"

  defp ttl_seconds do
    Application.get_env(:edoc_api, :document_delivery, [])
    |> Keyword.get(:ttl_seconds, @default_ttl_seconds)
  end

  defp renderer do
    Application.get_env(:edoc_api, :document_delivery, [])
    |> Keyword.get(:renderer, DocumentRenderer)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
