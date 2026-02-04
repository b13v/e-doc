defmodule EdocApi.EmailSender do
  import Swoosh.Email

  alias EdocApi.Mailer

  @from {"EdocAPI", System.get_env("EMAIL_FROM") || "noreply@edocapi.com"}

  def send_verification_email(email, token) do
    verification_url = verification_link(token)

    new()
    |> to({nil, email})
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
    |> Mailer.deliver()
  end

  defp verification_link(token) do
    base_url = System.get_env("BASE_URL") || "http://localhost:4000"
    "#{base_url}/verify-email?token=#{token}"
  end
end
