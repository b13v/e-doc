defmodule Mix.Tasks.EdocApi.VerifyUser do
  use Mix.Task

  def run([email]) do
    Mix.Task.run("app.start")

    alias EdocApi.Accounts

    user = Accounts.get_user_by_email(email)

    if user do
      Accounts.mark_email_verified!(user.id)
      verified_user = Accounts.get_user_by_email(email)
      IO.puts("User email: #{verified_user.email}")
      IO.puts("Verified at: #{inspect(verified_user.verified_at)}")
      IO.puts("SUCCESS: Email verified!")
    else
      IO.puts("User not found: #{email}")
    end
  end
end
