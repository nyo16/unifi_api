defmodule UnifiApi.FormatterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias UnifiApi.Formatter

  # ---------------------------------------------------------------------------
  # table/3
  # ---------------------------------------------------------------------------

  describe "table/3 with a plain list of maps" do
    test "outputs table with headers and rows" do
      data = [
        %{"name" => "Switch 24", "ip" => "192.168.1.10"},
        %{"name" => "AP Lite", "ip" => "192.168.1.20"}
      ]

      output =
        capture_io(fn ->
          assert :ok == Formatter.table(data, ["name", "ip"], title: "Test Table")
        end)

      # Title is present
      assert output =~ "Test Table"

      # Headers are present
      assert output =~ "name"
      assert output =~ "ip"

      # Row data is present
      assert output =~ "Switch 24"
      assert output =~ "192.168.1.10"
      assert output =~ "AP Lite"
      assert output =~ "192.168.1.20"

      # Row count summary
      assert output =~ "2 rows"
    end
  end

  describe "table/3 with wrapped %{\"data\" => [...]} response" do
    test "unwraps the data key and renders the table" do
      wrapped = %{
        "data" => [
          %{"host" => "alpha", "port" => "443"},
          %{"host" => "beta", "port" => "8080"}
        ]
      }

      output =
        capture_io(fn ->
          assert :ok == Formatter.table(wrapped, ["host", "port"])
        end)

      assert output =~ "alpha"
      assert output =~ "443"
      assert output =~ "beta"
      assert output =~ "8080"
      assert output =~ "2 rows"
    end
  end

  describe "table/3 with an empty list" do
    test "outputs headers and zero rows without crashing" do
      output =
        capture_io(fn ->
          assert :ok == Formatter.table([], ["col_a", "col_b"], title: "Empty")
        end)

      assert output =~ "Empty"
      assert output =~ "col_a"
      assert output =~ "col_b"
      assert output =~ "0 rows"
    end
  end

  describe "table/3 with nil values in maps" do
    test "renders without crash, nil values become empty strings" do
      data = [
        %{"name" => "Device A", "firmware" => nil},
        %{"name" => nil, "firmware" => "6.5.0"}
      ]

      output =
        capture_io(fn ->
          assert :ok == Formatter.table(data, ["name", "firmware"])
        end)

      # Non-nil values present
      assert output =~ "Device A"
      assert output =~ "6.5.0"
      assert output =~ "2 rows"
    end
  end

  # ---------------------------------------------------------------------------
  # detail/2
  # ---------------------------------------------------------------------------

  describe "detail/2 with a plain map" do
    test "outputs key-value pairs" do
      data = %{
        "name" => "Main Gateway",
        "ip" => "10.0.0.1",
        "firmware" => "7.1.0"
      }

      output =
        capture_io(fn ->
          assert :ok == Formatter.detail(data, title: "Gateway Detail")
        end)

      assert output =~ "Gateway Detail"
      assert output =~ "name"
      assert output =~ "Main Gateway"
      assert output =~ "ip"
      assert output =~ "10.0.0.1"
      assert output =~ "firmware"
      assert output =~ "7.1.0"
    end
  end

  describe "detail/2 with wrapped %{\"data\" => %{...}} response" do
    test "unwraps the data key and renders key-value pairs" do
      wrapped = %{
        "data" => %{
          "id" => "abc123",
          "status" => "healthy"
        }
      }

      output =
        capture_io(fn ->
          assert :ok == Formatter.detail(wrapped, title: "Wrapped Detail")
        end)

      assert output =~ "Wrapped Detail"
      assert output =~ "id"
      assert output =~ "abc123"
      assert output =~ "status"
      assert output =~ "healthy"
    end
  end

  # ---------------------------------------------------------------------------
  # Shortcut functions
  # ---------------------------------------------------------------------------

  describe "devices/1" do
    test "outputs a devices table with expected columns" do
      data = [
        %{
          "name" => "USW-Pro-24",
          "macAddress" => "fc:ec:da:01:02:03",
          "model" => "USW-Pro-24-PoE",
          "state" => "CONNECTED",
          "ipAddress" => "192.168.1.5"
        },
        %{
          "name" => "U6-Lite",
          "macAddress" => "fc:ec:da:04:05:06",
          "model" => "U6-Lite",
          "state" => "DISCONNECTED",
          "ipAddress" => "192.168.1.6"
        }
      ]

      output =
        capture_io(fn ->
          assert :ok == Formatter.devices(data)
        end)

      assert output =~ "Devices"
      assert output =~ "name"
      assert output =~ "macAddress"
      assert output =~ "model"
      assert output =~ "state"
      assert output =~ "ipAddress"
      assert output =~ "USW-Pro-24"
      assert output =~ "fc:ec:da:01:02:03"
      assert output =~ "CONNECTED"
      assert output =~ "U6-Lite"
      assert output =~ "DISCONNECTED"
      assert output =~ "2 rows"
    end
  end

  describe "clients/1" do
    test "outputs a clients table with expected columns" do
      data = [
        %{
          "name" => "iPhone 15",
          "ipAddress" => "192.168.1.100",
          "macAddress" => "aa:bb:cc:dd:ee:01",
          "type" => "WIRELESS"
        },
        %{
          "name" => "Desktop PC",
          "ipAddress" => "192.168.1.101",
          "macAddress" => "aa:bb:cc:dd:ee:02",
          "type" => "WIRED"
        }
      ]

      output =
        capture_io(fn ->
          assert :ok == Formatter.clients(data)
        end)

      assert output =~ "Connected Clients"
      assert output =~ "name"
      assert output =~ "ipAddress"
      assert output =~ "macAddress"
      assert output =~ "type"
      assert output =~ "iPhone 15"
      assert output =~ "WIRELESS"
      assert output =~ "Desktop PC"
      assert output =~ "WIRED"
      assert output =~ "2 rows"
    end
  end

  describe "cameras/1" do
    test "outputs a cameras table with expected columns" do
      data = [
        %{
          "name" => "Front Door",
          "modelKey" => "G4-Bullet",
          "state" => "CONNECTED",
          "mac" => "E0:63:DA:01:02:03"
        },
        %{
          "name" => "Backyard",
          "modelKey" => "G5-Pro",
          "state" => "ONLINE",
          "mac" => "E0:63:DA:04:05:06"
        }
      ]

      output =
        capture_io(fn ->
          assert :ok == Formatter.cameras(data)
        end)

      assert output =~ "Cameras"
      assert output =~ "name"
      assert output =~ "modelKey"
      assert output =~ "state"
      assert output =~ "mac"
      assert output =~ "Front Door"
      assert output =~ "G4-Bullet"
      assert output =~ "CONNECTED"
      assert output =~ "Backyard"
      assert output =~ "G5-Pro"
      assert output =~ "2 rows"
    end
  end

  describe "networks/1" do
    test "outputs a networks table with expected columns" do
      data = [
        %{
          "name" => "Default",
          "vlanId" => "1",
          "id" => "60a1b2c3d4e5f6a7b8c9d0e1"
        },
        %{
          "name" => "IoT",
          "vlanId" => "20",
          "id" => "60a1b2c3d4e5f6a7b8c9d0e2"
        }
      ]

      output =
        capture_io(fn ->
          assert :ok == Formatter.networks(data)
        end)

      assert output =~ "Networks"
      assert output =~ "name"
      assert output =~ "vlanId"
      assert output =~ "id"
      assert output =~ "Default"
      assert output =~ "IoT"
      assert output =~ "20"
      assert output =~ "2 rows"
    end
  end

  describe "sites/1" do
    test "outputs a sites table with expected columns" do
      data = [
        %{
          "name" => "Main Office",
          "id" => "site-001",
          "internalReference" => "main-office-ref"
        },
        %{
          "name" => "Branch Office",
          "id" => "site-002",
          "internalReference" => "branch-ref"
        }
      ]

      output =
        capture_io(fn ->
          assert :ok == Formatter.sites(data)
        end)

      assert output =~ "Sites"
      assert output =~ "name"
      assert output =~ "id"
      assert output =~ "internalReference"
      assert output =~ "Main Office"
      assert output =~ "site-001"
      assert output =~ "Branch Office"
      assert output =~ "branch-ref"
      assert output =~ "2 rows"
    end
  end
end
