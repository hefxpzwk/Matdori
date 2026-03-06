defmodule Matdori.TextAnchorsTest do
  use ExUnit.Case, async: true

  alias Matdori.TextAnchors

  test "normalize/1 normalizes line endings and unicode" do
    input = "Cafe\u0301\r\nhello  \r\n"
    assert TextAnchors.normalize(input) == "Café\nhello\n"
  end

  test "resolve/2 disambiguates repeated matches with prefix/suffix" do
    text = "alpha beta alpha beta"

    selector = %{
      quote_exact: "alpha",
      quote_prefix: "beta ",
      quote_suffix: " beta",
      start_g: 0,
      end_g: 5
    }

    assert {:ok, %{start_g: 11, end_g: 16}} = TextAnchors.resolve(text, selector)
  end

  test "resolve/2 returns ambiguous without enough context" do
    text = "test test test"
    selector = %{quote_exact: "test", start_g: 0, end_g: 4}

    assert {:error, :ambiguous} = TextAnchors.resolve(text, selector)
  end

  test "resolve/2 handles emoji grapheme ranges" do
    text = "Hello 👋 world"

    selector = %{
      quote_exact: "👋",
      quote_prefix: "Hello ",
      quote_suffix: " world",
      start_g: 6,
      end_g: 7
    }

    assert {:ok, %{start_g: 6, end_g: 7}} = TextAnchors.resolve(text, selector)
  end
end
