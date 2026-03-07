defmodule Matdori.LinkPreviewTest do
  use ExUnit.Case, async: true

  alias Matdori.LinkPreview

  test "fetch/2 handles list-form content-type headers" do
    previous = Application.get_env(:matdori, :link_preview_enabled)
    Application.put_env(:matdori, :link_preview_enabled, true)
    on_exit(fn -> Application.put_env(:matdori, :link_preview_enabled, previous) end)

    req_get = fn _url, _opts ->
      {:ok,
       %Req.Response{
         status: 200,
         headers: [{"content-type", ["text/html; charset=utf-8"]}],
         body: """
         <html><head>
           <meta property=\"og:title\" content=\"Preview Title\" />
           <meta property=\"og:description\" content=\"Preview Description\" />
           <meta property=\"og:image\" content=\"https://img.example.com/a.png\" />
         </head></html>
         """
       }}
    end

    preview = LinkPreview.fetch("https://example.com/post", req_get: req_get)

    assert preview.preview_title == "Preview Title"
    assert preview.preview_description == "Preview Description"
    assert preview.preview_image_url == "https://img.example.com/a.png"
  end

  test "fetch/2 returns empty map for non-html content type" do
    previous = Application.get_env(:matdori, :link_preview_enabled)
    Application.put_env(:matdori, :link_preview_enabled, true)
    on_exit(fn -> Application.put_env(:matdori, :link_preview_enabled, previous) end)

    req_get = fn _url, _opts ->
      {:ok,
       %Req.Response{
         status: 200,
         headers: [{"content-type", ["application/json"]}],
         body: "{\"ok\":true}"
       }}
    end

    assert LinkPreview.fetch("https://example.com/post", req_get: req_get) == %{}
  end
end
