defmodule UnifiApi.Protect.Chimes do
  @moduledoc """
  UniFi Protect API — chime management.

  Lists Protect chime devices (doorbell chimes).

  ## Response fields

    * `id`, `modelKey`, `name`, `mac`
    * `state` — `"CONNECTED"`, `"CONNECTING"`, or `"DISCONNECTED"`
    * `cameraIds` — list of associated doorbell camera IDs
    * `ringSettings` — list of `%{cameraId, repeatTimes, ringtoneId, volume}`
  """

  alias UnifiApi.Client

  defp prefix, do: Client.protect_prefix()

  @doc """
  Lists all chimes.

  ## Examples

      {:ok, chimes} = UnifiApi.Protect.Chimes.list(client)
  """
  @spec list(Req.Request.t()) :: {:ok, term()} | {:error, term()}
  def list(client) do
    Client.get(client, "#{prefix()}/v1/chimes")
  end

  @doc """
  Gets a specific chime by ID.

  ## Examples

      {:ok, chime} = UnifiApi.Protect.Chimes.get(client, chime_id)
      chime["name"]  # => "Front Door Chime"
      chime["state"] # => "CONNECTED"
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(client, id) do
    Client.get(client, "#{prefix()}/v1/chimes/#{id}")
  end

  @doc """
  Updates chime settings.

  ## Examples

      {:ok, _} = UnifiApi.Protect.Chimes.update(client, chime_id, %{
        name: "Front Door Chime",
        ringSettings: [%{ringtoneId: "default", volume: 80}]
      })
  """
  @spec update(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def update(client, id, body) do
    Client.patch(client, "#{prefix()}/v1/chimes/#{id}", body)
  end

  @doc """
  Returns a lazy stream that auto-paginates through all chimes.

  ## Options

    * `:limit` — items per page (default: 200)
    * `:filter` — UniFi filter expression

  ## Examples

      UnifiApi.Protect.Chimes.stream(client)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream(client, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/chimes", opts)
  end
end
