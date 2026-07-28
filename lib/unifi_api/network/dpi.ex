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

  @doc """
  Annotates DPI stats with human-readable category and application names.

  The legacy DPI endpoints return numeric `cat` and `app` IDs only.
  This helper joins them against the lists returned by
  `UnifiApi.Network.Resources.list_dpi_categories/1` and
  `list_dpi_applications/1` (which work with the integration API, no
  cookie auth required).

  Adds `"category_name"` to each `by_cat` entry and `"category_name"` +
  `"application_name"` to each `by_app` entry. Original numeric IDs
  and counters are preserved. Unknown IDs map to `nil`.

  ## Examples

      # Once per session — these don't change often, cache them:
      {:ok, categories} = UnifiApi.Network.Resources.list_dpi_categories(client)
      {:ok, applications} = UnifiApi.Network.Resources.list_dpi_applications(client)

      # Then on every poll:
      {:ok, dpi} = UnifiApi.Network.DPI.by_site(authed, "default")

      named =
        UnifiApi.Network.DPI.with_names(dpi,
          categories: categories,
          applications: applications
        )

      # Top 10 apps by tx_bytes
      named
      |> Enum.flat_map(& &1["by_app"])
      |> Enum.sort_by(& &1["tx_bytes"], :desc)
      |> Enum.take(10)
      |> Enum.map(&{&1["application_name"], &1["tx_bytes"]})

  ## Options

    * `:categories` — list of `%{"id" => int, "name" => str}` from
      `Resources.list_dpi_categories/1`. Required.
    * `:applications` — list of `%{"id" => int, "name" => str}` from
      `Resources.list_dpi_applications/1`. Required.
  """
  @spec with_names(list(map()), keyword()) :: list(map())
  def with_names(dpi_data, opts) when is_list(dpi_data) do
    categories = Keyword.fetch!(opts, :categories)
    applications = Keyword.fetch!(opts, :applications)

    cat_index = index_by_id(categories)
    app_index = index_by_id(applications)

    Enum.map(dpi_data, &annotate_entry(&1, cat_index, app_index))
  end

  defp annotate_entry(entry, cat_index, app_index) do
    by_cat =
      entry
      |> Map.get("by_cat", [])
      |> Enum.map(&add_category_name(&1, cat_index))

    by_app =
      entry
      |> Map.get("by_app", [])
      |> Enum.map(&(&1 |> add_category_name(cat_index) |> add_application_name(app_index)))

    entry
    |> Map.put("by_cat", by_cat)
    |> Map.put("by_app", by_app)
  end

  defp index_by_id(list) do
    Map.new(list, fn item -> {item["id"], item["name"]} end)
  end

  defp add_category_name(entry, index) do
    case Map.get(entry, "cat") do
      nil -> entry
      id -> Map.put(entry, "category_name", Map.get(index, id))
    end
  end

  defp add_application_name(entry, index) do
    case Map.get(entry, "app") do
      nil -> entry
      id -> Map.put(entry, "application_name", Map.get(index, id))
    end
  end

  defp prefix, do: Client.v1_prefix()
end
