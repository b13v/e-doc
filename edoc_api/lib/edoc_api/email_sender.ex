defmodule EdocApi.EmailSender do
  import Swoosh.Email

  require Logger

  alias EdocApi.Mailer

  @verification_from {"Edocly", System.get_env("EMAIL_FROM") || "noreply@edocapi.com"}
  @invite_from {"Edocly", System.get_env("EMAIL_FROM") || "noreply@edocapi.com"}
  @password_reset_from {"Edocly", System.get_env("EMAIL_FROM") || "noreply@edocapi.com"}

  def send_verification_email(recipient_email, token, locale \\ "ru") do
    verification_url = verification_link(token)
    locale = normalize_locale(locale)

    email =
      new()
      |> to({nil, recipient_email})
      |> from(@verification_from)
      |> subject(verification_subject(locale))
      |> html_body(verification_html_body(locale, verification_url))
      |> text_body(verification_text_body(locale, verification_url))

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

  def send_password_reset_email(recipient_email, token, locale \\ "ru") do
    locale = normalize_password_reset_locale(locale)
    reset_url = password_reset_link(token)

    email =
      new()
      |> to({nil, recipient_email})
      |> from(@password_reset_from)
      |> subject(password_reset_subject(locale))
      |> html_body(password_reset_html_body(locale, reset_url))
      |> text_body(password_reset_text_body(locale, reset_url))

    Logger.info("[EMAIL] Sending password reset email to: #{recipient_email}")

    case Mailer.deliver(email) do
      {:ok, receipt} ->
        Logger.info("[EMAIL] Password reset email delivered successfully: #{inspect(receipt)}")
        {:ok, receipt}

      {:error, reason} ->
        Logger.error("[EMAIL] Password reset email failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp verification_link(token) do
    base_url = System.get_env("BASE_URL") || "http://localhost:4000"
    "#{base_url}/verify-email?token=#{token}"
  end

  defp password_reset_link(token) do
    base_url = System.get_env("BASE_URL") || "http://localhost:4000"
    "#{base_url}/password/reset?token=#{token}"
  end

  defp verification_subject("kk"), do: "Edocly email-ды растаңыз"
  defp verification_subject(_), do: "Подтвердите email в Edocly"

  defp verification_text_body("kk", verification_url) do
    """
    Edocly жүйесіне қош келдіңіз!

    Email мекенжайыңызды растау үшін төмендегі сілтемеге өтіңіз:
    #{verification_url}

    Сілтеме 24 сағат бойы жарамды.

    Егер сіз Edocly жүйесінде аккаунт ашпаған болсаңыз, бұл хатты елемеңіз.
    """
  end

  defp verification_text_body(_, verification_url) do
    """
    Добро пожаловать в Edocly!

    Перейдите по ссылке ниже, чтобы подтвердить ваш email:
    #{verification_url}

    Ссылка действует 24 часа.

    Если вы не создавали аккаунт в Edocly, просто проигнорируйте это письмо.
    """
  end

  defp verification_html_body(locale, verification_url) do
    {headline, lead, outro} =
      case locale do
        "kk" ->
          {
            "Edocly жүйесіне қош келдіңіз!",
            "Email мекенжайыңызды растау үшін төмендегі сілтемеге өтіңіз:",
            "Егер сіз Edocly жүйесінде аккаунт ашпаған болсаңыз, бұл хатты елемеңіз."
          }

        _ ->
          {
            "Добро пожаловать в Edocly!",
            "Перейдите по ссылке ниже, чтобы подтвердить ваш email:",
            "Если вы не создавали аккаунт в Edocly, просто проигнорируйте это письмо."
          }
      end

    """
    <html>
      <body>
        <h1>#{headline}</h1>
        <p>#{lead}</p>
        <p><a href="#{verification_url}">#{verification_url}</a></p>
        <p>#{verification_expiry_line(locale)}</p>
        <p>#{outro}</p>
      </body>
    </html>
    """
  end

  defp verification_expiry_line("kk"), do: "Сілтеме 24 сағат бойы жарамды."
  defp verification_expiry_line(_), do: "Ссылка действует 24 часа."

  defp signup_link(email) do
    base_url = System.get_env("BASE_URL") || "http://localhost:4000"
    "#{base_url}/signup?email=#{URI.encode_www_form(email)}"
  end

  defp normalize_company_name(nil), do: "your company"
  defp normalize_company_name(""), do: "your company"
  defp normalize_company_name(name), do: name

  defp normalize_locale("kk"), do: "kk"
  defp normalize_locale(_), do: "ru"

  defp normalize_invite_locale("kk"), do: "kk"
  defp normalize_invite_locale(_), do: "ru"

  defp normalize_password_reset_locale("kk"), do: "kk"
  defp normalize_password_reset_locale(_), do: "ru"

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

  defp password_reset_subject("kk"), do: "Edocly құпиясөзін жаңартыңыз"
  defp password_reset_subject(_), do: "Сбросьте пароль в Edocly"

  defp password_reset_text_body("kk", reset_url) do
    """
    Құпиясөзіңізді жаңарту үшін төмендегі сілтемеге өтіңіз:
    #{reset_url}

    Сілтеме 24 сағат бойы жарамды.

    Егер сіз құпиясөзді жаңартуды сұрамаған болсаңыз, бұл хатты елемеңіз.
    """
  end

  defp password_reset_text_body(_, reset_url) do
    """
    Чтобы сбросить пароль, перейдите по ссылке ниже:
    #{reset_url}

    Ссылка действует 24 часа.

    Если вы не запрашивали сброс пароля, просто проигнорируйте это письмо.
    """
  end

  defp password_reset_html_body(locale, reset_url) do
    {headline, lead, expiry_line, outro} =
      case locale do
        "kk" ->
          {
            "Құпиясөзіңізді жаңартыңыз",
            "Құпиясөзіңізді жаңарту үшін төмендегі сілтемеге өтіңіз:",
            "Сілтеме 24 сағат бойы жарамды.",
            "Егер сіз құпиясөзді жаңартуды сұрамаған болсаңыз, бұл хатты елемеңіз."
          }

        _ ->
          {
            "Сбросьте пароль в Edocly",
            "Чтобы сбросить пароль, перейдите по ссылке ниже:",
            "Ссылка действует 24 часа.",
            "Если вы не запрашивали сброс пароля, просто проигнорируйте это письмо."
          }
      end

    """
    <html>
      <body>
        <h1>#{headline}</h1>
        <p>#{lead}</p>
        <p><a href="#{reset_url}">#{reset_url}</a></p>
        <p>#{expiry_line}</p>
        <p>#{outro}</p>
      </body>
    </html>
    """
  end
end
