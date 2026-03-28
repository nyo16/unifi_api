defmodule UnifiApi.StreamError do
  @moduledoc """
  Raised when `UnifiApi.Client.stream/3` encounters an API error during pagination.
  """
  defexception [:reason, :path]

  @impl true
  def message(%{reason: reason, path: path}) do
    "stream request to #{path} failed: #{inspect(reason)}"
  end
end
