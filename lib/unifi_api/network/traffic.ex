defmodule UnifiApi.Network.Traffic do
  @moduledoc """
  UniFi Network API (v2) — traffic time series.

  Returns aggregated traffic counters over a configurable time window —
  per client and per destination country.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Common params

    * `:start` — window start, unix milliseconds.
    * `:end` — window end, unix milliseconds (defaults to now if omitted).
    * `:interval` — bucket size: `"hour"`, `"day"`, `"week"`.

  ## Response shape

  An array of buckets, each with `time` and the relevant counters
  (`tx_bytes`, `rx_bytes`, plus `country`/`mac` for the variant).
  """

  use UnifiApi.Resource, api: :network_v1

  @doc """
  Returns per-client traffic breakdown over the time window.
  """
  @spec by_client(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def by_client(client, site_id, opts \\ []) do
    Client.get_v1(client, "#{prefix(client)}/v2/api/site/#{id!(site_id)}/traffic",
      params: build_params(opts)
    )
  end

  @doc """
  Returns destination-country traffic breakdown over the time window.
  """
  @spec by_country(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def by_country(client, site_id, opts \\ []) do
    Client.get_v1(
      client,
      "#{prefix(client)}/v2/api/site/#{id!(site_id)}/country-traffic",
      params: build_params(opts)
    )
  end

  defp build_params(opts) do
    []
    |> maybe_param(:start, opts[:start])
    |> maybe_param(:end, opts[:end])
    |> maybe_param(:interval, opts[:interval])
  end
end
