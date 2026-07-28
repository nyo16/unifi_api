defmodule UnifiApi.Time do
  @moduledoc """
  Tiny time helpers for the v1 / v2 endpoints that take unix-millisecond
  timestamps (`UnifiApi.Protect.Events.list/2` `:start` / `:end`,
  `UnifiApi.Network.Traffic.by_client/3` `:start` / `:end`, etc.).

  Saves the boilerplate `System.os_time(:millisecond) - 60 * 60 * 1000`
  that every time-window query ends up needing.

  ## Examples

      import UnifiApi.Time

      # Last hour of motion events
      {:ok, events} =
        UnifiApi.Protect.Events.list(authed,
          start: hours_ago(1),
          end: now_ms(),
          types: ["motion"]
        )
  """

  @doc "Current time in unix milliseconds."
  @spec now_ms() :: integer()
  def now_ms, do: System.os_time(:millisecond)

  @doc "Unix milliseconds for `n` minutes ago. Accepts integers or floats."
  @spec minutes_ago(number()) :: integer()
  def minutes_ago(n) when is_number(n), do: now_ms() - trunc(n * 60_000)

  @doc "Unix milliseconds for `n` hours ago."
  @spec hours_ago(number()) :: integer()
  def hours_ago(n) when is_number(n), do: now_ms() - trunc(n * 3_600_000)

  @doc "Unix milliseconds for `n` days ago."
  @spec days_ago(number()) :: integer()
  def days_ago(n) when is_number(n), do: now_ms() - trunc(n * 86_400_000)
end
