defmodule Matdori.TextAnchors do
  @moduledoc false

  @context_size 16

  def normalize(text) when is_binary(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.split("\n", trim: false)
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.join("\n")
    |> String.normalize(:nfc)
  end

  def selector_from_range(snapshot_text, start_g, end_g) do
    graphemes = String.graphemes(normalize(snapshot_text))
    exact = grapheme_slice(graphemes, start_g, end_g)
    prefix = grapheme_slice(graphemes, max(0, start_g - @context_size), start_g)
    suffix = grapheme_slice(graphemes, end_g, min(length(graphemes), end_g + @context_size))

    %{
      quote_exact: exact,
      quote_prefix: empty_to_nil(prefix),
      quote_suffix: empty_to_nil(suffix),
      start_g: start_g,
      end_g: end_g
    }
  end

  def resolve(snapshot_text, selector) when is_map(selector) do
    normalized = normalize(snapshot_text)
    graphemes = String.graphemes(normalized)
    exact = normalize(Map.get(selector, :quote_exact) || Map.get(selector, "quote_exact") || "")

    cond do
      exact == "" ->
        {:error, :invalid}

      true ->
        matches = find_matches(graphemes, String.graphemes(exact))

        case disambiguate(matches, graphemes, selector) do
          {:ok, start_g, end_g} -> {:ok, %{start_g: start_g, end_g: end_g}}
          :none -> fallback_to_position(graphemes, selector, exact)
          :ambiguous -> {:error, :ambiguous}
        end
    end
  end

  def grapheme_slice(graphemes, start_g, end_g)

  def grapheme_slice(graphemes, start_g, end_g) when start_g >= 0 and end_g >= start_g do
    graphemes
    |> Enum.slice(start_g, end_g - start_g)
    |> Enum.join()
  end

  defp find_matches(graphemes, exact_graphemes) do
    max_start = length(graphemes) - length(exact_graphemes)

    if max_start < 0 do
      []
    else
      for start_g <- 0..max_start,
          Enum.slice(graphemes, start_g, length(exact_graphemes)) == exact_graphemes do
        {start_g, start_g + length(exact_graphemes)}
      end
    end
  end

  defp disambiguate([], _graphemes, _selector), do: :none
  defp disambiguate([single], _graphemes, _selector), do: to_ok(single)

  defp disambiguate(matches, graphemes, selector) do
    prefix = Map.get(selector, :quote_prefix) || Map.get(selector, "quote_prefix")
    suffix = Map.get(selector, :quote_suffix) || Map.get(selector, "quote_suffix")
    norm_prefix = if prefix, do: normalize_context(prefix), else: nil
    norm_suffix = if suffix, do: normalize_context(suffix), else: nil

    filtered =
      Enum.filter(matches, fn {start_g, end_g} ->
        prefix_ok?(graphemes, start_g, norm_prefix) and suffix_ok?(graphemes, end_g, norm_suffix)
      end)

    case filtered do
      [] -> :none
      [single] -> to_ok(single)
      _ -> :ambiguous
    end
  end

  defp fallback_to_position(graphemes, selector, exact) do
    start_g = parse_int(Map.get(selector, :start_g) || Map.get(selector, "start_g"))
    end_g = parse_int(Map.get(selector, :end_g) || Map.get(selector, "end_g"))

    cond do
      is_nil(start_g) or is_nil(end_g) ->
        {:error, :not_found}

      start_g < 0 or end_g <= start_g or end_g > length(graphemes) ->
        {:error, :not_found}

      grapheme_slice(graphemes, start_g, end_g) == exact ->
        {:ok, %{start_g: start_g, end_g: end_g}}

      true ->
        {:error, :not_found}
    end
  end

  defp prefix_ok?(_graphemes, _start_g, nil), do: true

  defp prefix_ok?(graphemes, start_g, prefix) do
    prefix_g = String.graphemes(prefix)
    from = max(0, start_g - length(prefix_g))
    grapheme_slice(graphemes, from, start_g) == prefix
  end

  defp suffix_ok?(_graphemes, _end_g, nil), do: true

  defp suffix_ok?(graphemes, end_g, suffix) do
    suffix_g = String.graphemes(suffix)
    to = min(length(graphemes), end_g + length(suffix_g))
    grapheme_slice(graphemes, end_g, to) == suffix
  end

  defp to_ok({start_g, end_g}), do: {:ok, start_g, end_g}

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp normalize_context(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.normalize(:nfc)
  end
end
