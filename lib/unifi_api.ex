defmodule UnifiApi do
  @moduledoc """
  Elixir client for UniFi Dream Machine APIs (Network & Protect).

  ## Quick start

      # Using application config
      client = UnifiApi.new()

      # Using explicit options
      client = UnifiApi.new(base_url: "https://192.168.0.1", api_key: "my-key")

      # Network API
      {:ok, sites} = UnifiApi.Network.Sites.list(client)
      {:ok, devices} = UnifiApi.Network.Devices.list(client, "site-uuid")

      # Protect API
      {:ok, cameras} = UnifiApi.Protect.Cameras.list(client)

  ## Configuration

  Configure via application environment or pass options to `new/1`:

      config :unifi_api,
        base_url: "https://192.168.0.1",
        api_key: "your-api-key",
        verify_ssl: false,
        network_path: "/proxy/network/integration",
        protect_path: "/proxy/protect/integration"

  On UDM/UDM Pro/UDM SE the API runs behind a reverse proxy at
  `/proxy/network/integration` (Network) and `/proxy/protect/integration`
  (Protect). For Cloud Key, set both paths to `"/integration"`.

  Options passed to `new/1` override application config.
  """

  @doc """
  Creates a new API client.

  A single client works for both Network and Protect APIs — the path
  prefix is resolved per-module from application config.

  ## Options

    * `:base_url` — UniFi controller URL (e.g. `"https://192.168.0.1"`)
    * `:api_key` — API key for authentication
    * `:verify_ssl` — whether to verify SSL certificates against the OS CA
      store (default: `false`). Ignored when `:cert_fingerprints` is set.
    * `:cert_fingerprints` — list of SHA-256 fingerprints of acceptable
      peer certificates. When set, the connection is verified by pinning
      the leaf certificate to one of these fingerprints; CA validation is
      skipped. Each entry is a hex string, optionally prefixed with
      `"sha256:"` and/or separated by colons. Example:
      `["sha256:AB:CD:..."]` or `["abcd...32-byte-hex..."]`.

  ## Examples

      # From application config
      client = UnifiApi.new()

      # With explicit options
      client = UnifiApi.new(base_url: "https://192.168.0.1", api_key: "abc123")

      # Pin the controller's self-signed certificate
      client = UnifiApi.new(
        base_url: "https://192.168.0.1",
        api_key: "abc123",
        cert_fingerprints: ["sha256:AB:CD:EF:..."]
      )

      # Same client works for both APIs
      UnifiApi.Network.Sites.list(client)
      UnifiApi.Protect.Cameras.list(client)
  """
  @spec new() :: Req.Request.t()
  @spec new(keyword()) :: Req.Request.t()
  defdelegate new(opts \\ []), to: UnifiApi.Client
end
