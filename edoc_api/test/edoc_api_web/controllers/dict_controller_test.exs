defmodule EdocApiWeb.DictControllerTest do
  use EdocApiWeb.ConnCase

  alias EdocApi.Core.{Bank, KbeCode, KnpCode}
  alias EdocApi.Payments.DictionaryCache
  alias EdocApi.Repo
  import EdocApi.TestFixtures

  setup %{conn: conn} do
    Application.put_env(:edoc_api, DictionaryCache, enabled: false)

    if pid = Process.whereis(DictionaryCache) do
      Process.exit(pid, :kill)
    end

    user = create_user!()
    EdocApi.Accounts.mark_email_verified!(user.id)

    conn =
      conn
      |> authenticate(user)
      |> put_req_header("accept", "application/json")

    :ok = seed_dictionary_rows()

    {:ok, conn: conn}
  end

  test "GET /v1/dicts/banks returns dictionary payload", %{conn: conn} do
    conn = get(conn, "/v1/dicts/banks")

    assert response(conn, 200)
    body = json_response(conn, 200)
    assert is_list(body["banks"])
    assert Enum.any?(body["banks"], &(&1["name"] == "Perf Bank"))
  end

  test "GET /v1/dicts/kbe returns dictionary payload", %{conn: conn} do
    conn = get(conn, "/v1/dicts/kbe")

    assert response(conn, 200)
    body = json_response(conn, 200)
    assert is_list(body["kbe_codes"])
    assert Enum.any?(body["kbe_codes"], &(&1["code"] == "77"))
  end

  test "GET /v1/dicts/knp returns dictionary payload", %{conn: conn} do
    conn = get(conn, "/v1/dicts/knp")

    assert response(conn, 200)
    body = json_response(conn, 200)
    assert is_list(body["knp_codes"])
    assert Enum.any?(body["knp_codes"], &(&1["code"] == "777"))
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = EdocApi.Auth.Token.generate_access_token(user.id)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp seed_dictionary_rows do
    Repo.insert!(%Bank{name: "Perf Bank", bic: unique_bic()})
    Repo.insert!(%KbeCode{code: "77", description: "Perf KBE"})
    Repo.insert!(%KnpCode{code: "777", description: "Perf KNP"})
    :ok
  end

  defp unique_bic do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string()
      |> String.slice(-6, 6)
      |> String.pad_leading(6, "0")

    "PERF#{suffix}"
  end
end
