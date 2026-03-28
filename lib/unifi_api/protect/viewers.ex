defmodule UnifiApi.Protect.Viewers do
  @moduledoc """
  UniFi Protect API — viewer management.

  List, view, and update Protect viewport devices.

  ## Response fields

    * `id`, `modelKey`, `name`, `mac`
    * `state` — `"CONNECTED"`, `"CONNECTING"`, or `"DISCONNECTED"`
    * `liveview` — the assigned liveview ID
    * `streamLimit` — max concurrent streams
  """

  alias UnifiApi.Client

  defp prefix, do: Client.protect_prefix()

  @doc """
  Lists all viewers.

  ## Examples

      {:ok, viewers} = UnifiApi.Protect.Viewers.list(client)
  """
  @spec list(Req.Request.t()) :: {:ok, term()} | {:error, term()}
  def list(client) do
    Client.get(client, "#{prefix()}/v1/viewers")
  end

  @doc """
  Gets a specific viewer by ID.

  ## Examples

      {:ok, viewer} = UnifiApi.Protect.Viewers.get(client, viewer_id)
      viewer["name"]  # => "Office Display"
      viewer["state"] # => "CONNECTED"
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(client, id) do
    Client.get(client, "#{prefix()}/v1/viewers/#{id}")
  end

  @doc """
  Updates viewer settings.

  ## Examples

      {:ok, _} = UnifiApi.Protect.Viewers.update(client, viewer_id, %{
        liveview: liveview_id
      })
  """
  @spec update(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def update(client, id, body) do
    Client.patch(client, "#{prefix()}/v1/viewers/#{id}", body)
  end
end
