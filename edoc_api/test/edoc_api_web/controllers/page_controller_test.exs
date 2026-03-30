defmodule EdocApiWeb.PageControllerTest do
  use EdocApiWeb.ConnCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Accounts

  describe "GET /" do
    test "renders landing auth links for guests", %{conn: conn} do
      conn = get(conn, "/")

      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]

      body = html_response(conn, 200)
      assert body =~ ">Вход<"
      assert body =~ ~s(href="http://localhost:4000/login")
      assert body =~ ">Регистрация<"
      assert body =~ ~s(href="http://localhost:4000/signup")
      assert body =~ ~s(<link rel="stylesheet" href="/assets/landing.css" />)
      refute body =~ "<style>"
      refute body =~ ~s(<a href="#kz-features" class="nav-link">Казахстан</a>)
      refute body =~ ~s(<i class="fas fa-play"></i>)
      refute body =~ "<h4>Мультивалютность</h4>"
      refute body =~ "<h3>Корпоративный</h3>"
      assert body =~ ~r/<h3[^>]*>Стартовый<\/h3>/
      assert body =~ ~s(<span class="price-amount">2 900 ₸</span>)
      assert body =~ ~r/<h3[^>]*>Базовый<\/h3>/
      assert body =~ ~s(<span class="price-amount">5 900 ₸</span>)
      refute body =~ "<h3>Бизнес</h3>"
      refute body =~ ~s(<span class="price-amount">9 900 ₸</span>)
      refute body =~ ~s(<span class="price-amount">24 900 ₸</span>)
      assert body =~ ~s(<div class="stat-number">5,000+</div>)
      assert body =~ ~s(<div class="stat-number">50,000</div>)
      refute body =~ ~s(<div class="stat-number">10,000+</div>)
      refute body =~ ~s(<div class="stat-number">500,000+</div>)
      assert body =~ ~r/<h3[^>]*>Счета на оплату<\/h3>/
      refute body =~ "Счета и счета-фактуры"
      refute body =~ "поддержка нескольких валют"
      assert body =~ "Автоматический расчет НДС 16% и других ставок."
      refute body =~ "Автоматический расчет НДС 12% и других ставок."
      assert body =~ "Полная локализация интерфейса на казахский и русский языки."
      refute body =~ "Полная локализация на казахский и русский языки. Документы на"
      assert body =~ ~r/<h4[^>]*>Продукт<\/h4>/
      assert body =~ ~r/href="#features"[^>]*>Возможности<\/a>/
      assert body =~ ~r/href="#pricing"[^>]*>Цены<\/a>/
      assert body =~ ~r/href="#how-it-works"[^>]*>Как это работает<\/a>/
      refute body =~ ">Интеграции<"
      refute body =~ ">API<"
      refute body =~ "© 2024 Edocly"
      assert body =~ ~s(<span id="footer-year"></span>)
      assert body =~ "new Date().getFullYear()"
      assert body =~ ~s(data-lang="kk")
      assert body =~ ~s(data-lang="ru")
      assert body =~ "edocly_locale"
      assert body =~ "\"kk\""
      assert body =~ "Мүмкіндіктер"
      assert body =~ "Қалай жұмыс істейді"
      assert body =~ "Кіру"
      assert body =~ "Тіркелу"
      assert body =~ "document.cookie"
    end

    test "redirects authenticated users to invoices", %{conn: conn} do
      user = create_user!()
      Accounts.mark_email_verified!(user.id)

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: user.id})
        |> get("/")

      assert redirected_to(conn) == "/invoices"
    end

    test "serves landing stylesheet from static assets", %{conn: conn} do
      conn = get(conn, "/assets/landing.css")

      assert get_resp_header(conn, "content-type") == ["text/css"]

      body = response(conn, 200)
      assert body =~ "@view-transition {navigation: auto;}"
      assert body =~ "grid-template-columns: repeat(2, minmax(0, 1fr));"
      assert body =~ "max-width: 960px;"
      assert body =~ "margin: 50px auto 0;"
    end
  end
end
