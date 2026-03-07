defmodule Matdori.EmbedTest do
  use ExUnit.Case, async: true

  alias Matdori.Embed

  test "classify/1 recognizes common YouTube video URLs" do
    urls = [
      "https://www.youtube.com/watch?v=iI5AmA9Vnhk&list=LL&index=1&t=285s",
      "https://youtu.be/iI5AmA9Vnhk?si=abc",
      "https://www.youtube.com/shorts/iI5AmA9Vnhk",
      "https://youtube.com/live/iI5AmA9Vnhk",
      "https://www.youtube.com/embed/iI5AmA9Vnhk"
    ]

    Enum.each(urls, fn url ->
      meta = Embed.classify(url)
      assert meta.mode == :native_embed
      assert meta.provider == :youtube
      assert meta.embed_url == "https://www.youtube.com/embed/iI5AmA9Vnhk?rel=0"
    end)
  end

  test "classify/1 recognizes YouTube playlist URLs" do
    list_id = "PLRsnf8Rj7fVWDfEtExl9fJ2Y9Vo13A2zY"

    meta = Embed.classify("https://www.youtube.com/playlist?list=#{list_id}")

    assert meta.mode == :native_embed
    assert meta.provider == :youtube
    assert meta.embed_url == "https://www.youtube.com/embed/videoseries?list=#{list_id}"
  end
end
