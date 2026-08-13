defmodule UnifiApi.Protect.NVR do
  @moduledoc """
  UniFi Protect API — NVR information.

  Retrieves NVR details including doorbell settings.

  ## Response fields

    * `id`, `modelKey`, `name`
    * `doorbellSettings` — `%{defaultMessageText, defaultMessageResetTimeoutMs, customMessages, customImages}`
  """

  use UnifiApi.Resource, api: :protect

  @doc """
  Gets NVR information.

  ## Options

    * `:raw` — when `true`, return the raw response body binary
      (skips JSON decoding). Useful on heavy NVR responses that the
      caller wants to stream-parse.

  ## Examples

      {:ok, nvr} = UnifiApi.Protect.NVR.get(client)
      nvr["name"]             # => "UNVR"
      nvr["doorbellSettings"] # => %{"defaultMessageText" => "Welcome", ...}
  """
  @spec get(Req.Request.t(), keyword()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get(client, opts \\ []) do
    Client.get(client, "#{prefix(client)}/v1/nvrs", opts)
  end
end
