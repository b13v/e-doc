defmodule EdocApi.Auth.Token do
  @moduledoc false

  @issuer "edoc_api"
  @aud "edoc_api_users"
  @ttl_seconds 60 * 60 * 24 * 7

  @type token :: String.t()
  @type claims :: %{optional(String.t()) => term()}
  @type error :: term()

  @spec generate_access_token(Ecto.UUID.t()) ::
          {:ok, token(), claims()} | {:error, error()}
  def generate_access_token(user_id) when is_binary(user_id) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    claims = %{
      "sub" => user_id,
      "iss" => @issuer,
      "aud" => @aud,
      "iat" => now,
      "exp" => now + @ttl_seconds
    }

    # For plain claim maps, use encode_and_sign/2 (not generate_and_sign)
    Joken.encode_and_sign(claims, signer())
  end

  @spec verify(token()) :: {:ok, claims()} | {:error, error()}
  def verify(token) when is_binary(token) do
    with {:ok, claims} <- Joken.verify(token, signer()),
         :ok <- validate_claims(claims) do
      {:ok, claims}
    end
  end

  # -----------------------
  # Internals
  # -----------------------

  defp signer do
    secret = Application.fetch_env!(:edoc_api, EdocApi.Auth)[:jwt_secret]
    Joken.Signer.create("HS256", secret)
  end

  defp validate_claims(%{"sub" => sub, "iss" => iss, "aud" => aud, "exp" => exp})
       when is_binary(sub) and is_binary(iss) and is_binary(aud) and is_integer(exp) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    cond do
      iss != @issuer -> {:error, :invalid_issuer}
      aud != @aud -> {:error, :invalid_audience}
      exp <= now -> {:error, :token_expired}
      true -> :ok
    end
  end

  defp validate_claims(_), do: {:error, :invalid_claims}
end
