alias Matdori.Collab

username =
  case Application.get_env(:matdori, :x_source_username) do
    value when is_binary(value) and value != "" -> value
    _ -> "bbiribarabu"
  end

tweet_id = "20"

{:ok, _summary} =
  Collab.sync_configured_account_posts(
    source_posts: [
      %{
        title: "Playwright shared room",
        tweet_id: tweet_id,
        tweet_url: "https://x.com/#{username}/status/#{tweet_id}",
        snapshot_text: "Hello from Matdori snapshot for Playwright",
        posted_at: DateTime.utc_now()
      }
    ],
    session_id: "e2e-seed"
  )
