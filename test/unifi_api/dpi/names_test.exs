defmodule UnifiApi.DPI.NamesTest do
  use ExUnit.Case, async: true

  alias UnifiApi.DPI.Names

  # Shaped like the payloads returned by
  # `UnifiApi.Network.Resources.list_dpi_categories/1` and
  # `list_dpi_applications/1` — integer `"id"`, string `"name"`.
  @categories [
    %{"id" => 3, "name" => "Web"},
    %{"id" => 13, "name" => "Streaming Media"},
    %{"id" => 19, "name" => "Social Network"}
  ]

  @applications [
    %{"id" => 133, "name" => "YouTube"},
    %{"id" => 4, "name" => "Google APIs"},
    %{"id" => 94, "name" => "Netflix"}
  ]

  # One element of `UnifiApi.Network.DPI.by_site/2`'s `"data"` list.
  defp site_dpi do
    [
      %{
        "by_cat" => [
          %{"cat" => 13, "rx_bytes" => 9_000_000, "tx_bytes" => 120_000, "num_clients" => 4},
          %{"cat" => 3, "rx_bytes" => 500_000, "tx_bytes" => 80_000, "num_clients" => 9}
        ],
        "by_app" => [
          %{
            "app" => 133,
            "cat" => 13,
            "rx_bytes" => 8_500_000,
            "tx_bytes" => 100_000,
            "clients" => 2
          },
          %{"app" => 4, "cat" => 3, "rx_bytes" => 250_000, "tx_bytes" => 40_000, "clients" => 7}
        ]
      }
    ]
  end

  # One element of `UnifiApi.Network.DPI.by_client/2`'s `"data"` list:
  # per-MAC, `"by_app"` only — no `"by_cat"` key at all.
  defp client_dpi do
    [
      %{
        "mac" => "fc:ec:da:01:02:03",
        "by_app" => [
          %{"app" => 94, "cat" => 13, "rx_bytes" => 1_024, "tx_bytes" => 512}
        ]
      }
    ]
  end

  defp named(dpi) do
    Names.with_names(dpi, categories: @categories, applications: @applications)
  end

  describe "with_names/2 on a by_site payload" do
    test "annotates by_cat entries with the matching category name" do
      assert [%{"by_cat" => [first, second]}] = named(site_dpi())

      assert first["cat"] == 13
      assert first["category_name"] == "Streaming Media"
      assert second["cat"] == 3
      assert second["category_name"] == "Web"
    end

    test "annotates by_app entries with both category and application names" do
      assert [%{"by_app" => [youtube, gapis]}] = named(site_dpi())

      assert youtube["application_name"] == "YouTube"
      assert youtube["category_name"] == "Streaming Media"
      assert gapis["application_name"] == "Google APIs"
      assert gapis["category_name"] == "Web"
    end

    test "keeps the original ids, counters and entry order untouched" do
      assert [%{"by_app" => [youtube, gapis], "by_cat" => [streaming, web]}] = named(site_dpi())

      assert youtube["app"] == 133
      assert youtube["rx_bytes"] == 8_500_000
      assert youtube["tx_bytes"] == 100_000
      assert youtube["clients"] == 2
      assert gapis["app"] == 4
      assert gapis["rx_bytes"] == 250_000

      assert streaming["rx_bytes"] == 9_000_000
      assert streaming["num_clients"] == 4
      assert web["tx_bytes"] == 80_000
    end

    test "adds exactly one key per by_cat entry and two per by_app entry" do
      [%{"by_cat" => [cat | _], "by_app" => [app | _]}] = named(site_dpi())
      [%{"by_cat" => [raw_cat | _], "by_app" => [raw_app | _]}] = site_dpi()

      assert Map.keys(cat) -- Map.keys(raw_cat) == ["category_name"]

      assert Enum.sort(Map.keys(app) -- Map.keys(raw_app)) == [
               "application_name",
               "category_name"
             ]
    end
  end

  describe "with_names/2 on a by_client payload" do
    test "preserves unrelated top-level keys such as the client mac" do
      assert [entry] = named(client_dpi())
      assert entry["mac"] == "fc:ec:da:01:02:03"

      assert [%{"application_name" => "Netflix", "category_name" => "Streaming Media"}] =
               entry["by_app"]
    end

    test "materialises a missing by_cat key as an empty list" do
      assert [entry] = named(client_dpi())
      assert entry["by_cat"] == []
    end

    test "materialises a missing by_app key as an empty list" do
      assert [entry] = named([%{"by_cat" => [%{"cat" => 3}]}])
      assert entry["by_app"] == []
      assert entry["by_cat"] == [%{"cat" => 3, "category_name" => "Web"}]
    end
  end

  describe "with_names/2 unknown and absent ids" do
    test "maps unknown category and application ids to nil" do
      dpi = [%{"by_cat" => [%{"cat" => 9_999}], "by_app" => [%{"app" => 9_999, "cat" => 8_888}]}]

      assert [%{"by_cat" => [cat], "by_app" => [app]}] = named(dpi)
      assert cat["category_name"] == nil
      assert app["category_name"] == nil
      assert app["application_name"] == nil
    end

    test "does not add name keys when cat/app are absent" do
      dpi = [%{"by_cat" => [%{"rx_bytes" => 1}], "by_app" => [%{"rx_bytes" => 2}]}]

      assert [%{"by_cat" => [cat], "by_app" => [app]}] = named(dpi)
      refute Map.has_key?(cat, "category_name")
      refute Map.has_key?(app, "category_name")
      refute Map.has_key?(app, "application_name")
    end

    test "treats an explicit nil id the same as an absent one" do
      dpi = [%{"by_cat" => [%{"cat" => nil}], "by_app" => [%{"app" => nil, "cat" => nil}]}]

      assert [%{"by_cat" => [cat], "by_app" => [app]}] = named(dpi)
      refute Map.has_key?(cat, "category_name")
      refute Map.has_key?(app, "application_name")
    end

    test "uses separate indexes for categories and applications" do
      # id 3 is a *category* ("Web") and id 4 an *application* ("Google
      # APIs"). Cross-looking-up either index would leak the wrong name.
      dpi = [%{"by_app" => [%{"app" => 3, "cat" => 4}]}]

      assert [%{"by_app" => [app]}] = named(dpi)
      assert app["application_name"] == nil
      assert app["category_name"] == nil
    end

    test "matches ids strictly — a string id never matches an integer one" do
      dpi = [%{"by_cat" => [%{"cat" => 3}]}]

      assert [%{"by_cat" => [cat]}] =
               Names.with_names(dpi,
                 categories: [%{"id" => "3", "name" => "Web"}],
                 applications: []
               )

      assert cat["category_name"] == nil
    end
  end

  describe "with_names/2 empty input" do
    test "returns an empty list for empty dpi data" do
      assert named([]) == []
    end

    test "annotates every entry when given a multi-entry payload" do
      dpi = [
        %{"by_cat" => [%{"cat" => 3}], "by_app" => []},
        %{"by_cat" => [], "by_app" => [%{"app" => 94, "cat" => 13}]}
      ]

      assert [first, second] = named(dpi)
      assert [%{"category_name" => "Web"}] = first["by_cat"]
      assert first["by_app"] == []
      assert second["by_cat"] == []

      assert [%{"application_name" => "Netflix", "category_name" => "Streaming Media"}] =
               second["by_app"]
    end

    test "yields nil names when the lookup lists are empty" do
      dpi = [%{"by_cat" => [%{"cat" => 3}], "by_app" => [%{"app" => 133, "cat" => 13}]}]

      assert [%{"by_cat" => [cat], "by_app" => [app]}] =
               Names.with_names(dpi, categories: [], applications: [])

      assert cat["category_name"] == nil
      assert app["category_name"] == nil
      assert app["application_name"] == nil
    end

    test "an entry with no by_cat/by_app keys gains both as empty lists" do
      assert [%{"by_cat" => [], "by_app" => [], "mac" => "aa:bb"}] = named([%{"mac" => "aa:bb"}])
    end
  end

  describe "with_names/2 contract" do
    test "requires both :categories and :applications" do
      assert_raise KeyError, fn -> Names.with_names([], applications: @applications) end
      assert_raise KeyError, fn -> Names.with_names([], categories: @categories) end
      assert_raise KeyError, fn -> Names.with_names([], []) end
    end

    test "rejects non-list dpi data" do
      # Called through `apply/3`: a bare map literal is exactly what the
      # `is_list/1` guard rejects, but the compiler's type checker would
      # (correctly) warn about it at build time and the suite must stay
      # warning-free.
      args = [%{"by_app" => []}, [categories: @categories, applications: @applications]]

      assert_raise FunctionClauseError, fn -> apply(Names, :with_names, args) end
    end

    test "is byte-identical to the deprecated Network.DPI.with_names/2 delegation" do
      opts = [categories: @categories, applications: @applications]

      assert Names.with_names(site_dpi(), opts) ==
               UnifiApi.Network.DPI.with_names(site_dpi(), opts)
    end
  end
end
