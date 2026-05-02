defmodule UnifiApi.Network.Topology do
  @moduledoc """
  UniFi Network API (v2) — site topology graph.

  Returns the physical and logical connections the controller has
  inferred between gateway, switches, APs, and uplink-attached clients —
  the same data behind the dashboard's topology map.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Response shape

  An array of nodes, each with at least:

    * `id`, `name`, `mac`, `model`
    * `type` — `"gateway"`, `"switch"`, `"ap"`, `"client"`
    * `state` — `"connected"`, `"disconnected"`, `"pending"`
    * `parent` — id of the upstream node (gateway has none)
    * `parentMac`, `parentPort` — for switch- and AP-attached nodes
    * `uplinkType` — `"wire"`, `"wireless"`

  > **Note:** This endpoint is available on UniFi Network 7.x+. Field
  > shapes track the v2 schema and may shift across firmware revisions.
  """

  alias UnifiApi.Client

  @doc """
  Returns the site topology graph.

  ## Examples

      {:ok, nodes} = UnifiApi.Network.Topology.get(client, "default")

      # Find the gateway
      Enum.find(nodes, &(&1["type"] == "gateway"))

      # Group by parent
      nodes
      |> Enum.group_by(& &1["parent"])
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(client, site_id) do
    Client.get_v1(client, "#{prefix()}/v2/api/site/#{site_id}/topology")
  end

  defp prefix, do: Client.v1_prefix()
end
