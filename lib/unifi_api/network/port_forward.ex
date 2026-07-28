defmodule UnifiApi.Network.PortForward do
  @moduledoc """
  UniFi Network API (v1) — port-forward rules.

  Manages NAT port-forward rules on the gateway.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Rule fields

    * `_id`, `name`, `enabled`
    * `proto` — `"tcp"`, `"udp"`, `"tcp_udp"`
    * `src` — source CIDR / `"any"`
    * `dst_port`, `fwd_port`, `fwd` (forward IP)
    * `pfwd_interface` — `"wan"`, `"wan2"`, `"both"`
    * `log` — boolean, log packets matching this rule
  """

  alias UnifiApi.Client

  @doc """
  Lists all port-forward rules on a site.
  """
  @spec list(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id) do
    Client.get_v1(client, "#{prefix()}/api/s/#{site_id}/rest/portforward")
  end

  @doc """
  Returns a specific port-forward rule by id.
  """
  @spec get(Req.Request.t(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(client, site_id, rule_id) do
    Client.get_v1(client, "#{prefix()}/api/s/#{site_id}/rest/portforward/#{rule_id}")
  end

  @doc """
  Creates a new port-forward rule.

  ## Examples

      {:ok, rule} = UnifiApi.Network.PortForward.create(client, "default", %{
        name: "Game server",
        enabled: true,
        proto: "tcp_udp",
        src: "any",
        dst_port: "25565",
        fwd: "192.168.1.50",
        fwd_port: "25565",
        pfwd_interface: "wan"
      })
  """
  @spec create(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def create(client, site_id, body) do
    Client.post(client, "#{prefix()}/api/s/#{site_id}/rest/portforward", body)
  end

  @doc """
  Updates an existing port-forward rule.
  """
  @spec update(Req.Request.t(), String.t(), String.t(), map()) ::
          {:ok, term()} | {:error, term()}
  def update(client, site_id, rule_id, body) do
    Client.put(client, "#{prefix()}/api/s/#{site_id}/rest/portforward/#{rule_id}", body)
  end

  @doc """
  Deletes a port-forward rule.
  """
  @spec delete(Req.Request.t(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def delete(client, site_id, rule_id) do
    Client.delete(client, "#{prefix()}/api/s/#{site_id}/rest/portforward/#{rule_id}")
  end

  defp prefix, do: Client.v1_prefix()
end
