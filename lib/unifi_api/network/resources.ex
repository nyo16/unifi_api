defmodule UnifiApi.Network.Resources do
  @moduledoc """
  UniFi Network API — supporting resources.

  Read-only endpoints for WANs, VPN tunnels/servers, RADIUS profiles,
  device tags, DPI data, and country lists. These are typically used
  as reference data when building firewall rules, ACLs, or network configs.
  """

  alias UnifiApi.Client

  defp prefix, do: Client.network_prefix()

  @doc """
  Lists WAN interfaces on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, wans} = UnifiApi.Network.Resources.list_wans(client, site_id)
  """
  @spec list_wans(Req.Request.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list_wans(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/sites/#{site_id}/wans", opts)
  end

  @doc """
  Lists site-to-site VPN tunnels.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, tunnels} = UnifiApi.Network.Resources.list_vpn_tunnels(client, site_id)
  """
  @spec list_vpn_tunnels(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def list_vpn_tunnels(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/sites/#{site_id}/vpn/site-to-site-tunnels", opts)
  end

  @doc """
  Lists VPN servers on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, servers} = UnifiApi.Network.Resources.list_vpn_servers(client, site_id)
  """
  @spec list_vpn_servers(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def list_vpn_servers(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/sites/#{site_id}/vpn/servers", opts)
  end

  @doc """
  Lists RADIUS profiles on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, profiles} = UnifiApi.Network.Resources.list_radius_profiles(client, site_id)
  """
  @spec list_radius_profiles(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def list_radius_profiles(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/sites/#{site_id}/radius/profiles", opts)
  end

  @doc """
  Lists device tags on a site.

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, tags} = UnifiApi.Network.Resources.list_device_tags(client, site_id)
  """
  @spec list_device_tags(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def list_device_tags(client, site_id, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/sites/#{site_id}/device-tags", opts)
  end

  @doc """
  Lists DPI categories (not site-scoped).

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, categories} = UnifiApi.Network.Resources.list_dpi_categories(client)
  """
  @spec list_dpi_categories(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list_dpi_categories(client, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/dpi/categories", opts)
  end

  @doc """
  Lists DPI applications (not site-scoped).

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, apps} = UnifiApi.Network.Resources.list_dpi_applications(client)
  """
  @spec list_dpi_applications(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list_dpi_applications(client, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/dpi/applications", opts)
  end

  @doc """
  Lists countries (not site-scoped).

  ## Options

  Supports pagination: `:offset`, `:limit`, `:filter`.

  ## Examples

      {:ok, countries} = UnifiApi.Network.Resources.list_countries(client)
  """
  @spec list_countries(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list_countries(client, opts \\ []) do
    Client.get(client, "#{prefix()}/v1/countries", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all WANs.

  ## Examples

      UnifiApi.Network.Resources.stream_wans(client, site_id) |> Enum.to_list()
  """
  @spec stream_wans(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream_wans(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/sites/#{site_id}/wans", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all VPN tunnels.

  ## Examples

      UnifiApi.Network.Resources.stream_vpn_tunnels(client, site_id) |> Enum.to_list()
  """
  @spec stream_vpn_tunnels(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream_vpn_tunnels(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/sites/#{site_id}/vpn/site-to-site-tunnels", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all VPN servers.

  ## Examples

      UnifiApi.Network.Resources.stream_vpn_servers(client, site_id) |> Enum.to_list()
  """
  @spec stream_vpn_servers(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream_vpn_servers(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/sites/#{site_id}/vpn/servers", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all RADIUS profiles.

  ## Examples

      UnifiApi.Network.Resources.stream_radius_profiles(client, site_id) |> Enum.to_list()
  """
  @spec stream_radius_profiles(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream_radius_profiles(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/sites/#{site_id}/radius/profiles", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all device tags.

  ## Examples

      UnifiApi.Network.Resources.stream_device_tags(client, site_id) |> Enum.to_list()
  """
  @spec stream_device_tags(Req.Request.t(), String.t(), keyword()) :: Enumerable.t()
  def stream_device_tags(client, site_id, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/sites/#{site_id}/device-tags", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all DPI categories.

  ## Examples

      UnifiApi.Network.Resources.stream_dpi_categories(client) |> Enum.to_list()
  """
  @spec stream_dpi_categories(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream_dpi_categories(client, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/dpi/categories", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all DPI applications.

  ## Examples

      UnifiApi.Network.Resources.stream_dpi_applications(client) |> Enum.to_list()
  """
  @spec stream_dpi_applications(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream_dpi_applications(client, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/dpi/applications", opts)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all countries.

  ## Examples

      UnifiApi.Network.Resources.stream_countries(client) |> Enum.to_list()
  """
  @spec stream_countries(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream_countries(client, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/countries", opts)
  end
end
