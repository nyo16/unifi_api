defmodule UnifiApi.Network.SitesFindTest do
  use ExUnit.Case, async: true

  alias UnifiApi.Network.Sites

  defp test_client(sites) do
    Req.new(
      base_url: "http://localhost",
      plug: fn conn -> Req.Test.json(conn, sites) end,
      retry: false
    )
  end

  @sites [
    %{"id" => "id-default", "name" => "Default", "internalReference" => "default"},
    %{"id" => "id-hq", "name" => "HQ", "internalReference" => "hq01"}
  ]

  describe "find_by_name/2" do
    test "returns the matching site" do
      assert {:ok, %{"id" => "id-hq"}} = Sites.find_by_name(test_client(@sites), "HQ")
    end

    test "returns :not_found when no site matches" do
      assert {:error, :not_found} = Sites.find_by_name(test_client(@sites), "Nope")
    end

    test "is case-sensitive" do
      assert {:error, :not_found} = Sites.find_by_name(test_client(@sites), "hq")
    end
  end

  describe "find_by_internal_reference/2" do
    test "matches against internalReference field" do
      assert {:ok, %{"id" => "id-hq"}} =
               Sites.find_by_internal_reference(test_client(@sites), "hq01")
    end

    test "returns :not_found when no site matches" do
      assert {:error, :not_found} =
               Sites.find_by_internal_reference(test_client(@sites), "missing")
    end
  end
end
