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

  use UnifiApi.Resource, api: :network_v1

  @doc """
  Returns site-wide DPI stats grouped by application and category.

  Response is a list of one entry per site with `by_app` and `by_cat`
  arrays.
  """
  @spec by_site(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def by_site(client, site_id) do
    Client.get_v1(client, "#{prefix(client)}/api/s/#{id!(site_id)}/stat/sitedpi")
  end

  @doc """
  Returns DPI stats grouped by client (MAC).

  Response is a list with one entry per client containing `mac` and the
  same `by_app` / `by_cat` shape as `by_site/2`.
  """
  @spec by_client(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def by_client(client, site_id) do
    Client.get_v1(client, "#{prefix(client)}/api/s/#{id!(site_id)}/stat/stadpi")
  end

  @doc """
  Annotates DPI stats with human-readable category and application names.

  **Deprecated in v0.4.0** (removal in v0.5.0): the helper has been
  lifted to `UnifiApi.DPI.Names.with_names/2` — it was a pure data
  transform living in an HTTP-only module. This function remains as a
  thin delegation so existing aliases keep working:

      # Old (deprecated, removed in v0.5):
      UnifiApi.Network.DPI.with_names(dpi, categories: cats, applications: apps)

      # New:
      UnifiApi.DPI.Names.with_names(dpi, categories: cats, applications: apps)

  See `UnifiApi.DPI.Names` for the full doc and rationale.
  """
  @spec with_names(list(map()), keyword()) :: list(map())
  def with_names(dpi_data, opts) when is_list(dpi_data) do
    UnifiApi.DPI.Names.with_names(dpi_data, opts)
  end
end
