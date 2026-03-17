defmodule EdocApi.Seeds do
  import Ecto.Query, warn: false
  alias EdocApi.Repo
  alias EdocApi.Core.UnitOfMeasurement

  def run do
    csv_path =
      [
        Path.expand("units_of_measurement.csv", File.cwd!()),
        Path.expand("../../units_of_measurement.csv", __DIR__)
      ]
      |> Enum.find(&File.exists?/1)

    if is_nil(csv_path) do
      IO.puts("units_of_measurement.csv was not found, skipping units seed")
    else
      csv_path
      |> read_csv_text()
      |> String.split(~r/\r?\n/, trim: true)
      |> Enum.drop(1)
      |> Enum.map(&parse_csv_line/1)
      |> Enum.map(&to_unit_row/1)
      |> Enum.reject(&is_nil/1)
      |> upsert_units()
    end
  end

  defp read_csv_text(path) do
    case System.find_executable("iconv") do
      nil ->
        path
        |> File.read!()
        |> normalize_text()

      iconv_path ->
        case System.cmd(iconv_path, ["-f", "WINDOWS-1251", "-t", "UTF-8", path]) do
          {output, 0} -> output
          _ -> path |> File.read!() |> normalize_text()
        end
    end
  end

  defp normalize_text(binary) do
    if String.valid?(binary), do: binary, else: :unicode.characters_to_binary(binary, :latin1)
  end

  defp parse_csv_line(line), do: parse_csv_line(line, "", [], false)

  defp parse_csv_line(<<>>, current, acc, _in_quotes), do: Enum.reverse([current | acc])

  defp parse_csv_line(<<";", rest::binary>>, current, acc, false),
    do: parse_csv_line(rest, "", [current | acc], false)

  defp parse_csv_line(<<"\"", "\"", rest::binary>>, current, acc, true),
    do: parse_csv_line(rest, current <> "\"", acc, true)

  defp parse_csv_line(<<"\"", rest::binary>>, current, acc, in_quotes),
    do: parse_csv_line(rest, current, acc, not in_quotes)

  defp parse_csv_line(<<char::utf8, rest::binary>>, current, acc, in_quotes),
    do: parse_csv_line(rest, current <> <<char::utf8>>, acc, in_quotes)

  defp to_unit_row([okei_code, symbol, name, category | _rest]) do
    symbol = symbol |> String.trim() |> String.trim("\"")
    name = name |> String.trim() |> String.trim("\"")
    category = category |> String.trim() |> String.trim("\"")

    case Integer.parse(String.trim(okei_code)) do
      {code, ""} when symbol != "" and name != "" ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        %{
          okei_code: code,
          symbol: symbol,
          name: name,
          category: if(category == "", do: nil, else: category),
          inserted_at: now,
          updated_at: now
        }

      _ ->
        nil
    end
  end

  defp to_unit_row(_), do: nil

  defp upsert_units([]) do
    IO.puts("No units found in CSV")
  end

  defp upsert_units(rows) do
    symbols = Enum.map(rows, & &1.symbol)

    from(u in UnitOfMeasurement, where: u.symbol not in ^symbols)
    |> Repo.delete_all()

    {count, _} =
      Repo.insert_all(UnitOfMeasurement, rows,
        on_conflict: {:replace, [:okei_code, :name, :category, :updated_at]},
        conflict_target: [:symbol]
      )

    IO.puts("Seeded units_of_measurements: #{count} rows processed")
  end
end

EdocApi.Seeds.run()
