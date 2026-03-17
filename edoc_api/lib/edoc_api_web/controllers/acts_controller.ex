defmodule EdocApiWeb.ActsController do
  use EdocApiWeb, :controller

  plug(:put_view, html: EdocApiWeb.ActHTML)

  alias EdocApi.Acts
  alias EdocApi.Core
  alias EdocApi.Buyers
  alias EdocApi.Companies
  alias EdocApi.Documents.ActPdf

  defp current_user(conn), do: conn.assigns.current_user

  def index(conn, _params) do
    user = current_user(conn)
    acts = Acts.list_acts_for_user(user.id)

    render(conn, :index, page_title: "Acts", acts: acts)
  end

  def new(conn, params) do
    user = current_user(conn)

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Пожалуйста, сначала зарегистрируйте свою компанию.")
        |> redirect(to: "/company/setup")

      company ->
        buyers = Buyers.list_buyers_for_company(company.id)
        contracts = Acts.list_issued_contracts_for_user(user.id)
        units = Core.list_units_of_measurements()

        act_type = params["act_type"] || "contract"
        contract_id = normalize_id(params["contract_id"])
        prefill = prefill_from_contract(user.id, contract_id)

        selected_buyer_id =
          case {act_type, prefill.selected_buyer_id} do
            {"contract", nil} -> nil
            {_, selected_id} when not is_nil(selected_id) -> selected_id
            _ -> buyers != [] && hd(buyers).id
          end

        buyer_address =
          prefill.buyer_address ||
            buyer_address_for_selection(buyers, selected_buyer_id) ||
            ""

        render(conn, :new,
          page_title: "New Act",
          act_type: act_type,
          contracts: contracts,
          buyers: buyers,
          units: units,
          selected_contract_id: prefill.selected_contract_id,
          selected_buyer_id: selected_buyer_id,
          buyer_address: buyer_address,
          prefill_items: prefill.prefill_items,
          vat_rate: prefill.vat_rate || 16
        )
    end
  end

  def create(conn, %{"act" => act_params, "items" => items_params}) do
    user = current_user(conn)

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, "Пожалуйста, сначала зарегистрируйте свою компанию.")
        |> redirect(to: "/company/setup")

      company ->
        params = Map.put(act_params, "items", items_params)

        cond do
          act_params["act_type"] == "contract" and blank?(act_params["actual_date"]) ->
            conn
            |> put_flash(:error, "Дата необходима при составлении акта на основе договора.")
            |> redirect(to: "/acts/new?act_type=contract")

          true ->
            case Acts.create_act_for_user(user.id, company.id, params) do
              {:ok, act} ->
                conn
                |> put_flash(:info, "Акт успешно создан")
                |> redirect(to: "/acts/#{act.id}")

              {:error, :validation, %{changeset: changeset}} ->
                conn
                |> put_flash(
                  :error,
                  "Не удалось создать акт: #{format_changeset_errors(changeset)}"
                )
                |> redirect(to: "/acts/new")

              {:error, :business_rule, %{rule: :items_required}} ->
                conn
                |> put_flash(:error, "Требуется как минимум одна позиция.")
                |> redirect(to: "/acts/new")

              {:error, :business_rule, %{rule: :buyer_required}} ->
                conn
                |> put_flash(:error, "Пожалуйста, выберите покупателя")
                |> redirect(to: "/acts/new")

              {:error, :business_rule, %{rule: :contract_not_issued_or_not_found}} ->
                conn
                |> put_flash(:error, "Пожалуйста, выберите заключенный договор.")
                |> redirect(to: "/acts/new?act_type=contract")

              {:error, reason} ->
                conn
                |> put_flash(:error, "Не удалось создать акт: #{inspect(reason)}")
                |> redirect(to: "/acts/new")
            end
        end
    end
  end

  def create(conn, %{"act" => _act_params}) do
    conn
    |> put_flash(:error, "Требуется как минимум одна позиция.")
    |> redirect(to: "/acts/new")
  end

  def show(conn, %{"id" => id}) do
    user = current_user(conn)

    case Acts.get_act_for_user(user.id, id) do
      nil ->
        conn
        |> put_flash(:error, "Акт не найден.")
        |> redirect(to: "/acts/new")

      act ->
        render(conn, :show, page_title: "Act #{act.number}", act: act)
    end
  end

  def delete(conn, %{"id" => id}) do
    user = current_user(conn)

    case Acts.delete_act_for_user(user.id, id) do
      {:ok, _act} ->
        conn
        |> put_flash(:info, "Акт успешно удален.")
        |> redirect(to: "/acts")

      {:error, :business_rule, %{rule: :cannot_delete_non_draft_act}} ->
        conn
        |> put_flash(:error, "Только черновики могут быть удалены.")
        |> redirect(to: "/acts")

      {:error, _} ->
        conn
        |> put_flash(:error, "Акт не найден.")
        |> redirect(to: "/acts")
    end
  end

  def pdf(conn, %{"id" => id}) do
    user = current_user(conn)

    case Acts.get_act_for_user(user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "Акт не найден.")
        |> redirect(to: "/acts/new")

      act ->
        case ActPdf.render(act) do
          {:ok, pdf_binary} ->
            conn
            |> put_layout(false)
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(inline; filename="act-#{act.number}.pdf")
            )
            |> send_resp(200, pdf_binary)

          {:error, _reason} ->
            conn
            |> put_status(:internal_server_error)
            |> put_flash(:error, "Не удалось сгенерировать PDF-файл.")
            |> redirect(to: "/acts/#{id}")
        end
    end
  end

  defp normalize_id(nil), do: nil
  defp normalize_id(""), do: nil
  defp normalize_id(v) when is_binary(v), do: v
  defp normalize_id(_), do: nil

  defp blank?(value) when value in [nil, ""], do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false

  defp prefill_from_contract(_user_id, nil) do
    %{
      selected_contract_id: nil,
      selected_buyer_id: nil,
      buyer_address: "",
      prefill_items: [],
      vat_rate: nil
    }
  end

  defp prefill_from_contract(user_id, contract_id) do
    case Acts.build_act_from_contract(user_id, contract_id) do
      {:ok, prefill} ->
        prefill

      _ ->
        %{
          selected_contract_id: nil,
          selected_buyer_id: nil,
          buyer_address: "",
          prefill_items: [],
          vat_rate: nil
        }
    end
  end

  defp buyer_address_for_selection(buyers, buyer_id) do
    buyers
    |> Enum.find(&(&1.id == buyer_id))
    |> then(fn buyer -> buyer && buyer.address end)
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end
end
