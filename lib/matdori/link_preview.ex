defmodule Matdori.LinkPreview do
  @moduledoc false

  @max_body_size 800_000
  @default_headers [
    {"accept", "text/html,application/xhtml+xml"},
    {"user-agent", "MatdoriBot/1.0 (+https://matdori.app)"}
  ]

  def fetch(url, opts \\ [])

  def fetch(url, opts) when is_binary(url) do
    if Application.get_env(:matdori, :link_preview_enabled, true) do
      do_fetch(String.trim(url), opts)
    else
      %{}
    end
  end

  def fetch(_, _opts), do: %{}

  defp do_fetch(url, opts) do
    req_get = Keyword.get(opts, :req_get, &Req.get/2)

    request_opts = [
      headers: @default_headers,
      max_redirects: 3,
      connect_options: [timeout: 3_000],
      receive_timeout: 4_000
    ]

    case req_get.(url, request_opts) do
      {:ok, %Req.Response{status: status, headers: headers, body: body}}
      when status in 200..299 and is_binary(body) ->
        if html_response?(headers) do
          body
          |> String.slice(0, @max_body_size)
          |> extract_preview(url)
        else
          %{}
        end

      _ ->
        %{}
    end
  end

  defp html_response?(headers) do
    headers
    |> header_value("content-type")
    |> header_text()
    |> String.downcase()
    |> String.contains?("text/html")
  end

  defp header_value(headers, key) do
    case Enum.find(headers, fn {header, _value} -> String.downcase(to_string(header)) == key end) do
      {_header, value} -> value
      nil -> ""
    end
  end

  defp header_text(value) when is_binary(value), do: value

  defp header_text(value) when is_list(value) do
    cond do
      value == [] ->
        ""

      Enum.all?(value, &is_integer/1) ->
        List.to_string(value)

      true ->
        value
        |> Enum.map(&to_string/1)
        |> Enum.join(",")
    end
  end

  defp header_text(value), do: to_string(value)

  defp extract_preview(html, base_url) do
    title =
      meta_content(html, "property", "og:title") ||
        meta_content(html, "name", "twitter:title")

    description =
      meta_content(html, "property", "og:description") ||
        meta_content(html, "name", "twitter:description")

    image_url =
      meta_content(html, "property", "og:image") ||
        meta_content(html, "name", "twitter:image")

    image_url = absolute_url(image_url, base_url)

    %{}
    |> maybe_put(:preview_title, normalize_text(title, 120))
    |> maybe_put(:preview_description, normalize_text(description, 220))
    |> maybe_put(:preview_image_url, normalize_url(image_url))
  end

  defp meta_content(html, attr_key, attr_value) do
    escaped_attr_value = Regex.escape(attr_value)
    escaped_attr_key = Regex.escape(attr_key)

    pattern_a =
      Regex.compile!(
        "<meta[^>]*#{escaped_attr_key}\\s*=\\s*[\"']#{escaped_attr_value}[\"'][^>]*content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>",
        "i"
      )

    pattern_b =
      Regex.compile!(
        "<meta[^>]*content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*#{escaped_attr_key}\\s*=\\s*[\"']#{escaped_attr_value}[\"'][^>]*>",
        "i"
      )

    case Regex.run(pattern_a, html, capture: :all_but_first) ||
           Regex.run(pattern_b, html, capture: :all_but_first) do
      [content] -> content
      _ -> nil
    end
  end

  defp absolute_url(nil, _base), do: nil

  defp absolute_url(url, base_url) when is_binary(url) do
    trimmed = String.trim(url)

    case URI.parse(trimmed) do
      %URI{scheme: scheme, host: host} = uri when is_binary(scheme) and is_binary(host) ->
        URI.to_string(uri)

      %URI{scheme: nil, host: host} = uri when is_binary(host) ->
        base_scheme = URI.parse(base_url).scheme || "https"
        uri |> Map.put(:scheme, base_scheme) |> URI.to_string()

      %URI{scheme: nil, host: nil} = uri ->
        base_url
        |> URI.parse()
        |> URI.merge(uri)
        |> URI.to_string()

      _ ->
        nil
    end
  end

  defp normalize_text(nil, _max), do: nil

  defp normalize_text(value, max) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      cleaned -> String.slice(cleaned, 0, max)
    end
  end

  defp normalize_text(_value, _max), do: nil

  defp normalize_url(nil), do: nil

  defp normalize_url(url) when is_binary(url) do
    case String.trim(url) do
      "" -> nil
      cleaned -> cleaned
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
