defmodule EdocApi.EmailSender do
  import Swoosh.Email

  require Logger

  alias EdocApi.Mailer

  @from {"EdocAPI", System.get_env("EMAIL_FROM") || "noreply@edocapi.com"}
  @invite_from {"Edocly", System.get_env("EMAIL_FROM") || "noreply@edocapi.com"}

  def send_verification_email(recipient_email, token) do
    verification_url = verification_link(token)

    email =
      new()
      |> to({nil, recipient_email})
      |> from(@from)
      |> subject("Verify your email - EdocAPI")
      |> html_body("""
      <html>
        <body>
          <h1>Welcome to EdocAPI!</h1>
          <p>Please click the link below to verify your email address:</p>
          <p><a href="#{verification_url}">#{verification_url}</a></p>
          <p>This link will expire in 24 hours.</p>
          <p>If you didn't create an account on EdocAPI, please ignore this email.</p>
        </body>
      </html>
      """)
      |> text_body("""
      Welcome to EdocAPI!

      Please click the link below to verify your email address:
      #{verification_url}

      This link will expire in 24 hours.

      If you didn't create an account on EdocAPI, please ignore this email.
      """)

    Logger.info("[EMAIL] Sending verification email to: #{recipient_email}")

    case Mailer.deliver(email) do
      {:ok, receipt} ->
        Logger.info("[EMAIL] Delivered successfully: #{inspect(receipt)}")
        {:ok, receipt}

      {:error, reason} ->
        Logger.error("[EMAIL] Failed to deliver: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def send_membership_invite_email(recipient_email, attrs \\ %{}) do
    company_name =
      attrs
      |> Map.get(:company_name, Map.get(attrs, "company_name"))
      |> normalize_company_name()

    inviter_email = Map.get(attrs, :inviter_email, Map.get(attrs, "inviter_email"))
    locale = attrs |> Map.get(:locale, Map.get(attrs, "locale")) |> normalize_invite_locale()
    signup_url = signup_link(recipient_email)

    email =
      new()
      |> to({nil, recipient_email})
      |> from(@invite_from)
      |> subject(invite_subject(locale, company_name))
      |> html_body(invite_html_body(locale, company_name, signup_url, inviter_email))
      |> text_body(invite_text_body(locale, company_name, signup_url, inviter_email))

    Logger.info("[EMAIL] Sending membership invite to: #{recipient_email}")

    case Mailer.deliver(email) do
      {:ok, receipt} ->
        Logger.info("[EMAIL] Membership invite delivered successfully: #{inspect(receipt)}")
        {:ok, receipt}

      {:error, reason} ->
        Logger.error("[EMAIL] Membership invite failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp verification_link(token) do
    base_url = System.get_env("BASE_URL") || "http://localhost:4000"
    "#{base_url}/verify-email?token=#{token}"
  end

  defp signup_link(email) do
    base_url = System.get_env("BASE_URL") || "http://localhost:4000"
    "#{base_url}/signup?email=#{URI.encode_www_form(email)}"
  end

  defp normalize_company_name(nil), do: "your company"
  defp normalize_company_name(""), do: "your company"
  defp normalize_company_name(name), do: name

  defp normalize_invite_locale("kk"), do: "kk"
  defp normalize_invite_locale(_), do: "ru"

  defp invite_subject("kk", company_name), do: "Шақыру • Edocly • #{company_name}"
  defp invite_subject("ru", company_name), do: "Приглашение • Edocly • #{company_name}"

  defp invite_text_body("kk", company_name, signup_url, inviter_email) do
    """
    Сізді Edocly жүйесіндегі компанияға шақырды: #{company_name}.

    Тіркелу үшін келесі сілтемеге өтіңіз:
    #{signup_url}

    Егер осы email-пен аккаунтыңыз бар болса, жүйеге кіріңіз.
    #{invite_sender_line("kk", inviter_email)}
    """
  end

  defp invite_text_body("ru", company_name, signup_url, inviter_email) do
    """
    Вас пригласили в компанию #{company_name} в системе Edocly.

    Чтобы присоединиться, перейдите по ссылке для регистрации:
    #{signup_url}

    Если у вас уже есть аккаунт с этим email, просто войдите в систему.
    #{invite_sender_line("ru", inviter_email)}
    """
  end

  defp invite_html_body(locale, company_name, signup_url, inviter_email) do
    intro =
      case locale do
        "kk" -> "Сізді Edocly жүйесіндегі компанияға шақырды: #{company_name}."
        _ -> "Вас пригласили в компанию #{company_name} в системе Edocly."
      end

    cta =
      case locale do
        "kk" -> "Тіркелу үшін келесі сілтемеге өтіңіз:"
        _ -> "Чтобы присоединиться, перейдите по ссылке для регистрации:"
      end

    login_hint =
      case locale do
        "kk" -> "Егер осы email-пен аккаунтыңыз бар болса, жүйеге кіріңіз."
        _ -> "Если у вас уже есть аккаунт с этим email, просто войдите в систему."
      end

    sender = invite_sender_line(locale, inviter_email)

    """
    <html>
      <body>
        <p>#{intro}</p>
        <p>#{cta}</p>
        <p><a href="#{signup_url}">#{signup_url}</a></p>
        <p>#{login_hint}</p>
        #{if sender == "", do: "", else: "<p>#{sender}</p>"}
      </body>
    </html>
    """
  end

  defp invite_sender_line("kk", nil), do: ""
  defp invite_sender_line("kk", ""), do: ""
  defp invite_sender_line("kk", inviter_email), do: "Шақырған: #{inviter_email}"

  defp invite_sender_line("ru", nil), do: ""
  defp invite_sender_line("ru", ""), do: ""
  defp invite_sender_line("ru", inviter_email), do: "Пригласил: #{inviter_email}"
end
