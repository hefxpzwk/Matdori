defmodule Matdori.Embed do
  @moduledoc false

  @x_hosts ["x.com", "www.x.com", "twitter.com", "www.twitter.com"]
  @youtube_base_host "youtube.com"
  @youtube_short_hosts ["youtu.be", "www.youtu.be"]

  def classify(url) when is_binary(url) do
    with %URI{} = uri <- URI.parse(String.trim(url)),
         %URI{host: host, path: path} <- uri,
         true <- is_binary(host) and is_binary(path) do
      downcased_host = String.downcase(host)

      cond do
        downcased_host in @x_hosts and Regex.match?(~r{^/[^/?#]+/status/\d+}, path) ->
          %{mode: :native_embed, provider: :x}

        true ->
          case youtube_target(%{uri | host: downcased_host}) do
            {:video, video_id} ->
              %{
                mode: :native_embed,
                provider: :youtube,
                embed_url: youtube_video_embed_url(video_id)
              }

            {:playlist, list_id} ->
              %{
                mode: :native_embed,
                provider: :youtube,
                embed_url: youtube_playlist_embed_url(list_id)
              }

            :error ->
              %{mode: :preview_only, provider: :generic}
          end
      end
    else
      _ -> %{mode: :preview_only, provider: :generic}
    end
  end

  def status_label(%{mode: :native_embed}), do: "임베드 가능"
  def status_label(_), do: "미리보기"

  def youtube_video_embed_url(video_id), do: "https://www.youtube.com/embed/#{video_id}?rel=0"

  def youtube_playlist_embed_url(list_id),
    do: "https://www.youtube.com/embed/videoseries?list=#{list_id}"

  defp youtube_target(%URI{host: host, path: path}) when host in @youtube_short_hosts do
    path
    |> String.trim_leading("/")
    |> String.split("/", parts: 2)
    |> List.first()
    |> normalize_video_id()
    |> case do
      {:ok, video_id} -> {:video, video_id}
      :error -> :error
    end
  end

  defp youtube_target(%URI{host: host, path: "/watch", query: query}) when is_binary(host) do
    if youtube_host?(host) do
      params = decode_query(query)

      video_result = normalize_video_id(Map.get(params, "v") || Map.get(params, "vi"))
      list_result = normalize_playlist_id(Map.get(params, "list"))

      case {video_result, list_result} do
        {{:ok, video_id}, _} -> {:video, video_id}
        {:error, {:ok, list_id}} -> {:playlist, list_id}
        _ -> :error
      end
    else
      :error
    end
  end

  defp youtube_target(%URI{host: host, path: "/playlist", query: query}) when is_binary(host) do
    if youtube_host?(host) do
      query
      |> decode_query()
      |> Map.get("list")
      |> normalize_playlist_id()
      |> case do
        {:ok, list_id} -> {:playlist, list_id}
        :error -> :error
      end
    else
      :error
    end
  end

  defp youtube_target(%URI{host: host, path: path}) when is_binary(host) do
    if youtube_host?(host) do
      cond do
        String.starts_with?(path, "/shorts/") ->
          path
          |> String.replace_prefix("/shorts/", "")
          |> String.split("/", parts: 2)
          |> List.first()
          |> normalize_video_id()
          |> to_video_target()

        String.starts_with?(path, "/embed/") ->
          path
          |> String.replace_prefix("/embed/", "")
          |> String.split("/", parts: 2)
          |> List.first()
          |> normalize_video_id()
          |> to_video_target()

        String.starts_with?(path, "/live/") ->
          path
          |> String.replace_prefix("/live/", "")
          |> String.split("/", parts: 2)
          |> List.first()
          |> normalize_video_id()
          |> to_video_target()

        true ->
          :error
      end
    else
      :error
    end
  end

  defp youtube_target(_uri), do: :error

  defp to_video_target({:ok, video_id}), do: {:video, video_id}
  defp to_video_target(:error), do: :error

  defp youtube_host?(host) when is_binary(host) do
    host == @youtube_base_host or String.ends_with?(host, ".#{@youtube_base_host}")
  end

  defp youtube_host?(_), do: false

  defp decode_query(nil), do: %{}

  defp decode_query(query) when is_binary(query) do
    try do
      URI.decode_query(query)
    rescue
      _ -> %{}
    end
  end

  defp normalize_video_id(video_id) when is_binary(video_id) do
    cleaned = String.trim(video_id)

    if Regex.match?(~r/^[A-Za-z0-9_-]{11}$/, cleaned) do
      {:ok, cleaned}
    else
      :error
    end
  end

  defp normalize_video_id(_), do: :error

  defp normalize_playlist_id(list_id) when is_binary(list_id) do
    cleaned = String.trim(list_id)

    if Regex.match?(~r/^[A-Za-z0-9_-]{10,}$/, cleaned) do
      {:ok, cleaned}
    else
      :error
    end
  end

  defp normalize_playlist_id(_), do: :error
end
