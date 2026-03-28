defmodule UnifiApi.Network.Info do
  @moduledoc """
  UniFi Network API — system information.

  Retrieves controller version and system details.
  """

  alias UnifiApi.Client

  @doc """
  Returns system information including the application version.

  ## Examples

      {:ok, info} = UnifiApi.Network.Info.get_info(client)
      info["applicationVersion"]
      # => "10.1.84"
  """
  @spec get_info(Req.Request.t()) :: {:ok, term()} | {:error, term()}
  def get_info(client) do
    Client.get(client, "#{prefix()}/v1/info")
  end

  defp prefix, do: Client.network_prefix()
end
