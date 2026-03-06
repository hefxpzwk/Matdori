defmodule Matdori.XTimeline do
  @moduledoc false

  @api_base "https://api.x.com/2"
  @default_max_results 20
  @placeholder_snapshot_text "텍스트 본문이 없는 게시물입니다."

  def fetch_recent_posts(opts \\ []) do
    max_results = opts |> Keyword.get(:max_results, @default_max_results) |> clamp_max_results()

    with {:ok, username} <- configured_username(opts),
         {:ok, bearer_token} <- configured_bearer_token(opts),
         {:ok, user} <- fetch_user(username, bearer_token),
         {:ok, tweets} <- fetch_user_tweets(user.id, bearer_token, max_results) do
      {:ok, normalize_posts(tweets, user.username, user.pinned_tweet_id)}
    end
  end

  defp configured_username(opts) do
    case opts[:username] || Application.get_env(:matdori, :x_source_username) do
      username when is_binary(username) ->
        cleaned = String.trim(username)

        if cleaned == "" do
          {:error, :missing_x_source_username}
        else
          {:ok, cleaned}
        end

      _ ->
        {:error, :missing_x_source_username}
    end
  end

  defp configured_bearer_token(opts) do
    case opts[:bearer_token] || Application.get_env(:matdori, :x_bearer_token) do
      token when is_binary(token) ->
        cleaned = String.trim(token)

        if cleaned == "" do
          {:error, :missing_x_bearer_token}
        else
          {:ok, cleaned}
        end

      _ ->
        {:error, :missing_x_bearer_token}
    end
  end

  defp fetch_user(username, bearer_token) do
    endpoint = "#{@api_base}/users/by/username/#{URI.encode(username)}"

    case get_json(endpoint, bearer_token, %{"user.fields" => "pinned_tweet_id,username"}) do
      {:ok, %{"data" => data}} when is_map(data) ->
        {:ok,
         %{
           id: data["id"],
           username: data["username"] || username,
           pinned_tweet_id: data["pinned_tweet_id"]
         }}

      {:ok, payload} ->
        {:error, {:unexpected_user_response, payload}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_user_tweets(user_id, bearer_token, max_results) do
    endpoint = "#{@api_base}/users/#{user_id}/tweets"

    params = %{
      "exclude" => "replies,retweets",
      "max_results" => max_results,
      "tweet.fields" => "created_at"
    }

    case get_json(endpoint, bearer_token, params) do
      {:ok, %{"data" => tweets}} when is_list(tweets) ->
        {:ok, tweets}

      {:ok, %{"data" => nil}} ->
        {:ok, []}

      {:ok, payload} ->
        {:error, {:unexpected_timeline_response, payload}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_posts(tweets, username, pinned_tweet_id) do
    tweets
    |> Enum.reject(&(&1["id"] == pinned_tweet_id))
    |> Enum.map(fn tweet ->
      tweet_id = tweet["id"]

      %{
        tweet_id: tweet_id,
        tweet_url: "https://x.com/#{username}/status/#{tweet_id}",
        snapshot_text: normalize_snapshot_text(tweet["text"]),
        posted_at: parse_posted_at(tweet["created_at"])
      }
    end)
  end

  defp normalize_snapshot_text(text) when is_binary(text) do
    trimmed = String.trim(text)
    if trimmed == "", do: @placeholder_snapshot_text, else: trimmed
  end

  defp normalize_snapshot_text(_), do: @placeholder_snapshot_text

  defp parse_posted_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_posted_at(_), do: nil

  defp get_json(endpoint, bearer_token, params) do
    case Req.get(endpoint,
           headers: [
             {"authorization", "Bearer #{bearer_token}"},
             {"accept", "application/json"}
           ],
           params: params,
           connect_options: [timeout: 5_000],
           receive_timeout: 8_000
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:x_api_http_error, status, extract_error_detail(body)}}

      {:error, reason} ->
        {:error, {:x_api_request_failed, reason}}
    end
  end

  defp extract_error_detail(%{"detail" => detail}) when is_binary(detail), do: detail

  defp extract_error_detail(%{"title" => title}) when is_binary(title), do: title

  defp extract_error_detail(%{"errors" => [first | _]}) when is_map(first) do
    first["detail"] || first["message"] || "unknown_x_api_error"
  end

  defp extract_error_detail(_), do: "unknown_x_api_error"

  defp clamp_max_results(value) when is_integer(value), do: value |> max(5) |> min(100)
  defp clamp_max_results(_), do: @default_max_results
end
