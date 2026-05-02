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

  @typedoc """
  Result of `detect/1`. The string fields are absolute path prefixes you can
  use directly with `Application.put_env(:unifi_api, ..., ...)` or with the
  per-call routing in `UnifiApi.Auth.Cookie.login/4`.
  """
  @type controller_info :: %{
          style: :udm | :cloud_key,
          network_prefix: String.t(),
          protect_prefix: String.t(),
          v1_prefix: String.t(),
          auth_path: String.t()
        }

  @doc """
  Probes the controller and reports which path conventions to use.

  Issues `GET /` against the configured `base_url` with redirects disabled
  and applies the heuristic popularised by the
  [unpoller](https://github.com/unpoller/unpoller) project:

    * `200` — UniFi OS device (UDM, UDM Pro, UDM SE, UCK-G2). The Network
      and Protect APIs live under `/proxy/network` and `/proxy/protect`
      respectively, and login is at `/api/auth/login`.
    * `301`/`302`/`303` — standalone controller / Cloud Key. Network and
      Protect live at the root, and login is at `/api/login`.

  This heuristic is the same one unpoller uses against tens of thousands
  of deployments, but it is **not** infallible — set the prefixes
  manually via application config if `detect/1` mis-identifies your
  controller.

  ## Examples

      client = UnifiApi.new(base_url: "https://192.168.1.1", verify_ssl: false)

      {:ok, info} = UnifiApi.detect(client)
      # %{style: :udm, network_prefix: "/proxy/network/integration",
      #   protect_prefix: "/proxy/protect/integration",
      #   v1_prefix: "/proxy/network", auth_path: "/api/auth/login"}

      # Apply the discovered prefixes to subsequent calls:
      Application.put_env(:unifi_api, :network_path, info.network_prefix)
      Application.put_env(:unifi_api, :protect_path, info.protect_prefix)
  """
  @spec detect(Req.Request.t()) :: {:ok, controller_info()} | {:error, term()}
  def detect(client) do
    probe = Req.merge(client, redirect: false)

    case Req.get(probe, url: "/") do
      {:ok, %Req.Response{status: status}} when status in [301, 302, 303] ->
        {:ok, info(:cloud_key)}

      {:ok, %Req.Response{status: 200}} ->
        {:ok, info(:udm)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp info(:udm) do
    %{
      style: :udm,
      network_prefix: "/proxy/network/integration",
      protect_prefix: "/proxy/protect/integration",
      v1_prefix: "/proxy/network",
      auth_path: "/api/auth/login"
    }
  end

  defp info(:cloud_key) do
    %{
      style: :cloud_key,
      network_prefix: "/integration",
      protect_prefix: "/integration",
      v1_prefix: "",
      auth_path: "/api/login"
    }
  end
end
