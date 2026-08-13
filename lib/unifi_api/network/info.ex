defmodule UnifiApi.Network.Info do
  @moduledoc """
  UniFi Network API — system information.

  Retrieves controller version and system details.
  """

  use UnifiApi.Resource, api: :network

  @doc """
  Returns system information including the application version.

  ## Examples

      {:ok, info} = UnifiApi.Network.Info.get_info(client)
      info["applicationVersion"]
      # => "10.1.84"
  """
  @spec get_info(Req.Request.t()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get_info(client) do
    Client.get(client, "#{prefix(client)}/v1/info")
  end
end
