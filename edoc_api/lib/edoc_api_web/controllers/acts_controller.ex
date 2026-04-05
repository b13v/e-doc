defmodule EdocApiWeb.ActsController do
  use EdocApiWeb, :controller

  plug(:put_view, html: EdocApiWeb.ActHTML)

  alias EdocApi.Acts
  alias EdocApi.Core
  alias EdocApi.Buyers
  alias EdocApi.Companies
  alias EdocApi.Documents.ActPdf
  alias EdocApiWeb.ErrorHelpers

  defp current_user(conn), do: conn.assigns.current_user

  def index(conn, _params) do
    user = current_user(conn)
    acts = Acts.list_acts_for_user(user.id)

    render(conn, :index,
      page_title: gettext("Acts"),
      acts: acts,
      act_summary: act_summary(acts),
      current_section: :acts
    )
  end

  def new(conn, params) do
    user = current_user(conn)

    case Companies.get_company_by_user_id(user.id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please set up your company first."))
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
          page_title: gettext("New Act"),
          current_section: :acts,
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
        |> put_flash(:error, gettext("Please set up your company first."))
        |> redirect(to: "/company/setup")

      company ->
        params = Map.put(act_params, "items", items_params)

        cond do
          act_params["act_type"] == "contract" and blank?(act_params["actual_date"]) ->
            conn
            |> put_flash(
              :error,
              gettext("Actual date is required when creating an act from a contract.")
            )
            |> redirect(to: "/acts/new?act_type=contract")

          true ->
            case Acts.create_act_for_user(user.id, company.id, params) do
              {:ok, act} ->
                conn
                |> put_flash(:info, gettext("Act created successfully."))
                |> redirect(to: "/acts/#{act.id}")

              {:error, :validation, %{changeset: changeset}} ->
                conn
                |> put_flash(
                  :error,
                  gettext("Failed to create act: %{details}",
                    details: ErrorHelpers.format_changeset_errors(changeset)
                  )
                )
                |> redirect(to: "/acts/new")

              {:error, :business_rule, %{rule: :items_required}} ->
                conn
                |> put_flash(:error, gettext("At least one item is required."))
                |> redirect(to: "/acts/new")

              {:error, :business_rule, %{rule: :buyer_required}} ->
                conn
                |> put_flash(:error, gettext("Please select a buyer."))
                |> redirect(to: "/acts/new")

              {:error, :business_rule, %{rule: :contract_not_issued_or_not_found}} ->
                conn
                |> put_flash(:error, gettext("Please select an issued contract."))
                |> redirect(to: "/acts/new?act_type=contract")

              {:error, :business_rule, %{rule: :quota_exceeded}} ->
                conn
                |> put_flash(
                  :error,
                  gettext("Document limit reached for this billing period. Upgrade your plan to continue.")
                )
                |> redirect(to: "/acts/new")

              {:error, reason} ->
                conn
                |> put_flash(
                  :error,
                  gettext("Failed to create act: %{reason}", reason: inspect(reason))
                )
                |> redirect(to: "/acts/new")
            end
        end
    end
  end

  def create(conn, %{"act" => _act_params}) do
    conn
    |> put_flash(:error, gettext("At least one item is required."))
    |> redirect(to: "/acts/new")
  end

  def show(conn, %{"id" => id}) do
    user = current_user(conn)

    case Acts.get_act_for_user(user.id, id) do
      nil ->
        conn
        |> put_flash(:error, gettext("Act not found."))
        |> redirect(to: "/acts/new")

      act ->
        render(conn, :show,
          page_title: gettext("Act %{number}", number: act.number),
          act: act,
          current_section: :acts
        )
    end
  end

  def sign(conn, %{"id" => id}) do
    user = current_user(conn)

    case Acts.sign_act_for_user(user.id, id) do
      {:ok, _act} ->
        conn
        |> put_flash(:info, gettext("Act marked as signed."))
        |> redirect(to: "/acts/#{id}")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, gettext("Act not found."))
        |> redirect(to: "/acts")

      {:error, :business_rule, %{rule: :act_not_issued}} ->
        conn
        |> put_flash(:error, gettext("Only issued acts can be marked as signed."))
        |> redirect(to: "/acts/#{id}")

      {:error, :business_rule, %{rule: :act_already_signed}} ->
        conn
        |> put_flash(:error, gettext("Act has already been marked as signed."))
        |> redirect(to: "/acts/#{id}")

      {:error, reason} ->
        conn
        |> put_flash(
          :error,
          gettext("Failed to mark act as signed: %{reason}", reason: inspect(reason))
        )
        |> redirect(to: "/acts/#{id}")
    end
  end

  def issue(conn, %{"id" => id}) do
    user = current_user(conn)

    case Acts.issue_act_for_user(user.id, id) do
      {:ok, _act} ->
        conn
        |> put_flash(:info, gettext("Act issued successfully."))
        |> redirect(to: "/acts/#{id}")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, gettext("Act not found."))
        |> redirect(to: "/acts")

      {:error, :business_rule, %{rule: :act_not_editable}} ->
        conn
        |> put_flash(:error, gettext("This act cannot be issued."))
        |> redirect(to: "/acts/#{id}")

      {:error, :business_rule, %{rule: :quota_exceeded}} ->
        conn
        |> put_flash(
          :error,
          gettext("Document limit reached for this billing period. Upgrade your plan to continue.")
        )
        |> redirect(to: "/acts/#{id}")

      {:error, reason} ->
        conn
        |> put_flash(
          :error,
          gettext("Failed to issue act: %{reason}", reason: inspect(reason))
        )
        |> redirect(to: "/acts/#{id}")
    end
  end

  def delete(conn, %{"id" => id}) do
    user = current_user(conn)

    case Acts.delete_act_for_user(user.id, id) do
      {:ok, _act} ->
        conn
        |> put_flash(:info, gettext("Act deleted successfully."))
        |> redirect(to: "/acts")

      {:error, :business_rule, %{rule: :cannot_delete_non_draft_act}} ->
        conn
        |> put_flash(:error, gettext("Only draft acts can be deleted."))
        |> redirect(to: "/acts")

      {:error, _} ->
        conn
        |> put_flash(:error, gettext("Act not found."))
        |> redirect(to: "/acts")
    end
  end

  def pdf(conn, %{"id" => id}) do
    user = current_user(conn)

    case Acts.get_act_for_user(user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, gettext("Act not found."))
        |> redirect(to: "/acts/new")

      act ->
        # Pre-render HTML in web layer, then pass to PDF module
        html = EdocApiWeb.PdfTemplates.act_html(act)

        case ActPdf.render(html) do
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
            |> put_flash(:error, gettext("Failed to generate the PDF file."))
            |> redirect(to: "/acts/#{id}")
        end
    end
  end

  defp normalize_id(nil), do: nil
  defp normalize_id(""), do: nil
  defp normalize_id(v) when is_binary(v), do: v
  defp normalize_id(_), do: nil

  defp act_summary(acts) do
    Enum.reduce(acts, %{draft: 0, issued: 0, signed: 0}, fn act, acc ->
      case act.status do
        "draft" -> Map.update!(acc, :draft, &(&1 + 1))
        "issued" -> Map.update!(acc, :issued, &(&1 + 1))
        "signed" -> Map.update!(acc, :signed, &(&1 + 1))
        _ -> acc
      end
    end)
  end

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
end
