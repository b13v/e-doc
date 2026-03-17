defmodule EdocApiWeb.InvoiceHTML do
  use EdocApiWeb, :html
  alias Decimal

  embed_templates("invoice_html/*")

  def amount_words_kzt(nil), do: "—"

  def amount_words_kzt(%Decimal{} = d) do
    d = Decimal.round(d, 2)
    s = Decimal.to_string(d, :normal)

    {tenge, tiyn} =
      case String.split(s, ".") do
        [i, f] -> {String.to_integer(i), String.pad_trailing(String.slice(f, 0, 2), 2, "0")}
        [i] -> {String.to_integer(i), "00"}
      end

    words = num_to_words_ru(tenge)
    "#{String.capitalize(words)} тенге #{tiyn} тиын"
  end

  @ones %{
    0 => "ноль",
    1 => "один",
    2 => "два",
    3 => "три",
    4 => "четыре",
    5 => "пять",
    6 => "шесть",
    7 => "семь",
    8 => "восемь",
    9 => "девять"
  }
  @teens %{
    10 => "десять",
    11 => "одиннадцать",
    12 => "двенадцать",
    13 => "тринадцать",
    14 => "четырнадцать",
    15 => "пятнадцать",
    16 => "шестнадцать",
    17 => "семнадцать",
    18 => "восемнадцать",
    19 => "девятнадцать"
  }
  @tens %{
    2 => "двадцать",
    3 => "тридцать",
    4 => "сорок",
    5 => "пятьдесят",
    6 => "шестьдесят",
    7 => "семьдесят",
    8 => "восемьдесят",
    9 => "девяносто"
  }
  @hundreds %{
    1 => "сто",
    2 => "двести",
    3 => "триста",
    4 => "четыреста",
    5 => "пятьсот",
    6 => "шестьсот",
    7 => "семьсот",
    8 => "восемьсот",
    9 => "девятьсот"
  }

  defp num_to_words_ru(n) when is_integer(n) and n >= 0 do
    cond do
      n < 10 -> @ones[n]
      n < 20 -> @teens[n]
      n < 100 -> words_2(n)
      n < 1000 -> words_3(n)
      n < 1_000_000 -> words_group(n, 1000, {"тысяча", "тысячи", "тысяч"}, feminine: true)
      n < 1_000_000_000 -> words_group(n, 1_000_000, {"миллион", "миллиона", "миллионов"})
      true -> words_group(n, 1_000_000_000, {"миллиард", "миллиарда", "миллиардов"})
    end
  end

  defp words_2(n) do
    t = div(n, 10)
    o = rem(n, 10)
    base = @tens[t]
    if o == 0, do: base, else: base <> " " <> @ones[o]
  end

  defp words_3(n) do
    h = div(n, 100)
    rest = rem(n, 100)
    head = @hundreds[h]

    tail =
      cond do
        rest == 0 -> ""
        rest < 10 -> " " <> @ones[rest]
        rest < 20 -> " " <> @teens[rest]
        true -> " " <> words_2(rest)
      end

    head <> tail
  end

  defp words_group(n, unit, forms, opts \\ []) do
    g = div(n, unit)
    rest = rem(n, unit)
    g_words = group_words(g, opts)
    form = choose_form(g, forms)

    rest_words =
      cond do
        rest == 0 -> ""
        true -> " " <> num_to_words_ru(rest)
      end

    String.trim(g_words <> " " <> form <> rest_words)
  end

  defp group_words(g, opts) do
    feminine? = Keyword.get(opts, :feminine, false)
    base = num_to_words_ru(g)

    if feminine?, do: feminineize_last_unit(base, g), else: base
  end

  defp feminineize_last_unit(base, g) do
    tens = rem(g, 100)
    ones = rem(g, 10)

    cond do
      tens in 11..19 ->
        base

      ones == 1 ->
        replace_suffix(base, "один", "одна")

      ones == 2 ->
        replace_suffix(base, "два", "две")

      true ->
        base
    end
  end

  defp replace_suffix(str, suffix, replacement) do
    if String.ends_with?(str, suffix) do
      prefix_len = byte_size(str) - byte_size(suffix)
      binary_part(str, 0, prefix_len) <> replacement
    else
      str
    end
  end

  defp choose_form(n, {one, few, many}) do
    n = rem(n, 100)
    last = rem(n, 10)

    cond do
      n in 11..19 -> many
      last == 1 -> one
      last in 2..4 -> few
      true -> many
    end
  end
end
