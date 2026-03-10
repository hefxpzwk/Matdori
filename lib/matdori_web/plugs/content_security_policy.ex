defmodule MatdoriWeb.Plugs.ContentSecurityPolicy do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    policy =
      "default-src 'self'; " <>
        "script-src 'self' https://platform.twitter.com https://syndication.twitter.com https://cdn.syndication.twimg.com; " <>
        "style-src 'self' 'unsafe-inline' https://platform.twitter.com https://syndication.twitter.com https://ton.twimg.com; " <>
        "img-src 'self' data: https://*.twimg.com https://platform.twitter.com https://pbs.twimg.com https://abs.twimg.com https://syndication.twitter.com https://ton.twimg.com https://lh3.googleusercontent.com https://*.googleusercontent.com https://*.ggpht.com; " <>
        "frame-src 'self' https://platform.twitter.com https://syndication.twitter.com https://twitter.com; " <>
        "connect-src 'self' https://syndication.twitter.com https://cdn.syndication.twimg.com; " <>
        "font-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'"

    put_resp_header(conn, "content-security-policy", policy)
  end
end
