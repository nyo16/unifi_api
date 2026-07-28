defmodule UnifiApi.TimeTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Time, as: T

  test "now_ms/0 returns the current time in milliseconds" do
    before = System.os_time(:millisecond)
    now = T.now_ms()
    diff = abs(now - before)
    assert diff < 1000
  end

  test "minutes_ago/1 subtracts minutes" do
    now = System.os_time(:millisecond)
    diff = now - T.minutes_ago(5)
    # ~5 minutes ago, allow ±1s of clock jitter
    assert_in_delta diff, 5 * 60_000, 1000
  end

  test "hours_ago/1 subtracts hours" do
    now = System.os_time(:millisecond)
    diff = now - T.hours_ago(2)
    assert_in_delta diff, 2 * 3_600_000, 1000
  end

  test "days_ago/1 subtracts days" do
    now = System.os_time(:millisecond)
    diff = now - T.days_ago(1)
    assert_in_delta diff, 86_400_000, 1000
  end

  test "accepts floats" do
    now = System.os_time(:millisecond)
    diff = now - T.hours_ago(0.5)
    assert_in_delta diff, 1_800_000, 1000
  end
end
