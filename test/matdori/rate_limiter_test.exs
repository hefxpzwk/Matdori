defmodule Matdori.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Matdori.RateLimiter

  setup do
    :ets.delete_all_objects(Matdori.RateLimiter)
    :ok
  end

  test "minute bucket enforces limit" do
    assert :ok = RateLimiter.allow?("s1", :comment_submit, 2)
    assert :ok = RateLimiter.allow?("s1", :comment_submit, 2)
    assert {:error, :rate_limited} = RateLimiter.allow?("s1", :comment_submit, 2)
  end

  test "second bucket enforces limit separately" do
    assert :ok = RateLimiter.allow?("s2", :cursor_move, 1, :second)
    assert {:error, :rate_limited} = RateLimiter.allow?("s2", :cursor_move, 1, :second)
  end
end
