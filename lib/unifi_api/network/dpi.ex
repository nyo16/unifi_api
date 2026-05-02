defmodule UnifiApi.Network.DPI do
  @moduledoc """
  UniFi Network API (v1) — deep packet inspection statistics.

  Returns per-application and per-category traffic stats, both
  site-aggregated and per-client.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  Use `UnifiApi.Network.Resources.list_dpi_categories/1` and
  `list_dpi_applications/1` (integration API, no cookie auth required)
  to translate the numeric `cat` and `app` IDs returned here into
  human-readable names.

  ## Stats fields (per `by_app` / `by_cat` entry)

    * `app` / `cat` — numeric ID
    * `tx_bytes`, `rx_bytes`, `tx_packets`, `rx_packets`
    * `clients` — number of distinct clients observed using this
      app/category
  """

  alias UnifiApi.Client

  @doc """
  Returns site-wide DPI stats grouped by application and category.

  Response is a list of one entry per site with `by_app` and `by_cat`
  arrays.
  """
  @spec by_site(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def by_site(client, site_id) do
    Client.get_v1(client, "#{prefix()}/api/s/#{site_id}/stat/sitedpi")
  end

  @doc """
  Returns DPI stats grouped by client (MAC).

  Response is a list with one entry per client containing `mac` and the
  same `by_app` / `by_cat` shape as `by_site/2`.
  """
  @spec by_client(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def by_client(client, site_id) do
    Client.get_v1(client, "#{prefix()}/api/s/#{site_id}/stat/stadpi")
  end

  defp prefix, do: Client.v1_prefix()
end
