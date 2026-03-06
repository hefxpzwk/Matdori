alias Matdori.Collab

{:ok, _post} =
  Collab.upsert_today_post(
    %{
      "tweet_url" => "https://x.com/jack/status/20",
      "snapshot_text" => "Hello from Matdori snapshot for Playwright"
    },
    "e2e-seed"
  )
