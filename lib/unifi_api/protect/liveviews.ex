defmodule UnifiApi.Protect.Liveviews do
  @moduledoc """
  UniFi Protect API — liveview management.

  Lists configured liveview layouts for Protect viewports.

  ## Response fields

    * `id`, `modelKey`, `name`
    * `isDefault`, `isGlobal`, `owner`
    * `layout` — grid layout (1-26)
    * `slots` — list of `%{cameras, cycleMode, cycleInterval}`
  """

  alias UnifiApi.Client

  defp prefix, do: Client.protect_prefix()

  @doc """
  Lists all liveviews.

  ## Examples

      {:ok, liveviews} = UnifiApi.Protect.Liveviews.list(client)

      # Find the default liveview
      default = Enum.find(liveviews, & &1["isDefault"])
  """
  @spec list(Req.Request.t()) :: {:ok, term()} | {:error, term()}
  def list(client) do
    Client.get(client, "#{prefix()}/v1/liveviews")
  end

  @doc """
  Gets a specific liveview by ID.

  ## Examples

      {:ok, liveview} = UnifiApi.Protect.Liveviews.get(client, liveview_id)
      liveview["name"]   # => "All Cameras"
      liveview["layout"] # => 4
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(client, id) do
    Client.get(client, "#{prefix()}/v1/liveviews/#{id}")
  end

  @doc """
  Returns a lazy stream that auto-paginates through all liveviews.

  ## Options

    * `:limit` — items per page (default: 200)
    * `:filter` — UniFi filter expression

  ## Examples

      UnifiApi.Protect.Liveviews.stream(client)
      |> Enum.to_list()
  """
  @spec stream(Req.Request.t(), keyword()) :: Enumerable.t()
  def stream(client, opts \\ []) do
    Client.stream(client, "#{prefix()}/v1/liveviews", opts)
  end
end
