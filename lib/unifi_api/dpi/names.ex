defmodule UnifiApi.DPI.Names do
  @moduledoc """
  Pure helper for annotating UniFi DPI stats with human-readable
  category and application names.

  Lifted out of `UnifiApi.Network.DPI` so it can be used without an
  HTTP client (the original wrapped it in the same module despite
  being a pure data transform). The legacy
  `UnifiApi.Network.DPI.with_names/2` is preserved as a thin delegation
  for v0.4.x to avoid a breaking change for callers who imported it
  from that module; switch your alias to `UnifiApi.DPI.Names` when you
  bump the dep — the function will be dropped from `Network.DPI` in
  v0.5.0.

  ## Quick start

      # Once per session — these don't change often, cache them:
      {:ok, categories} = UnifiApi.Network.Resources.list_dpi_categories(client)
      {:ok, applications} = UnifiApi.Network.Resources.list_dpi_applications(client)

      # Then on every poll:
      {:ok, dpi} = UnifiApi.Network.DPI.by_site(authed, "default")

      named =
        UnifiApi.DPI.Names.with_names(dpi,
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

  @doc """
  Annotates DPI stats with human-readable category and application names.

  Adds `"category_name"` to each `by_cat` entry and `"category_name"` +
  `"application_name"` to each `by_app` entry. Original numeric IDs
  and counters are preserved. Unknown IDs map to `nil`.
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
end
