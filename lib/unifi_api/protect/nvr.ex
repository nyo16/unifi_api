defmodule UnifiApi.Protect.NVR do
  @moduledoc """
  UniFi Protect API — NVR information.

  Retrieves NVR details including doorbell settings.

  ## Response fields

    * `id`, `modelKey`, `name`
    * `doorbellSettings` — `%{defaultMessageText, defaultMessageResetTimeoutMs, customMessages, customImages}`
  """

  alias UnifiApi.Client

  defp prefix, do: Client.protect_prefix()

  @doc """
  Gets NVR information.

  ## Examples

      {:ok, nvr} = UnifiApi.Protect.NVR.get(client)
      nvr["name"]             # => "UNVR"
      nvr["doorbellSettings"] # => %{"defaultMessageText" => "Welcome", ...}
  """
  @spec get(Req.Request.t()) :: {:ok, term()} | {:error, term()}
  def get(client) do
    Client.get(client, "#{prefix()}/v1/nvrs")
  end
end
