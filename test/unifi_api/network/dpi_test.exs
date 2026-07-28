defmodule UnifiApi.Network.DPITest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.DPI

  defp test_client(plug) do
    Req.new(base_url: "http://localhost", plug: plug, retry: false)
  end

  test "by_site/2 hits /stat/sitedpi" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/sitedpi"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => [%{"by_app" => []}]})
      end)

    assert {:ok, [%{"by_app" => []}]} = DPI.by_site(client, "default")
  end

  test "by_client/2 hits /stat/stadpi" do
    client =
      test_client(fn conn ->
        assert conn.request_path == "/proxy/network/api/s/default/stat/stadpi"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => [%{"mac" => "ab:cd"}]})
      end)

    assert {:ok, [%{"mac" => "ab:cd"}]} = DPI.by_client(client, "default")
  end

  describe "with_names/2" do
    @categories [
      %{"id" => 1, "name" => "Web"},
      %{"id" => 2, "name" => "Streaming"}
    ]

    @applications [
      %{"id" => 100, "name" => "YouTube"},
      %{"id" => 101, "name" => "Gmail"}
    ]

    test "annotates by_cat entries with category_name" do
      dpi = [%{"by_cat" => [%{"cat" => 1, "tx_bytes" => 1000}], "by_app" => []}]

      assert [%{"by_cat" => [%{"category_name" => "Web", "tx_bytes" => 1000}]}] =
               DPI.with_names(dpi, categories: @categories, applications: @applications)
    end

    test "annotates by_app entries with both category_name and application_name" do
      dpi = [
        %{
          "by_app" => [%{"app" => 100, "cat" => 2, "tx_bytes" => 500}],
          "by_cat" => []
        }
      ]

      assert [
               %{
                 "by_app" => [
                   %{
                     "application_name" => "YouTube",
                     "category_name" => "Streaming",
                     "tx_bytes" => 500
                   }
                 ]
               }
             ] = DPI.with_names(dpi, categories: @categories, applications: @applications)
    end

    test "leaves unknown IDs with nil names" do
      dpi = [%{"by_cat" => [%{"cat" => 999}], "by_app" => [%{"app" => 999, "cat" => 999}]}]

      assert [
               %{
                 "by_cat" => [%{"category_name" => nil}],
                 "by_app" => [%{"application_name" => nil, "category_name" => nil}]
               }
             ] = DPI.with_names(dpi, categories: @categories, applications: @applications)
    end

    test "preserves entries without cat/app keys" do
      dpi = [%{"by_cat" => [%{"tx_bytes" => 1}], "by_app" => [%{"tx_bytes" => 2}]}]

      assert [%{"by_cat" => [bc], "by_app" => [ba]}] =
               DPI.with_names(dpi, categories: @categories, applications: @applications)

      refute Map.has_key?(bc, "category_name")
      refute Map.has_key?(ba, "category_name")
      refute Map.has_key?(ba, "application_name")
    end

    test "raises if :categories or :applications opts are missing" do
      assert_raise KeyError, fn -> DPI.with_names([], applications: []) end
      assert_raise KeyError, fn -> DPI.with_names([], categories: []) end
    end
  end
end
