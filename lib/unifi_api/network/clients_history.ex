defmodule UnifiApi.Network.ClientsHistory do
  @moduledoc """
  UniFi Network API (v2) — client history.

  Returns past client connections — devices that have been seen on the
  network even if they're currently offline. Complements
  `UnifiApi.Network.ClientsLive` (currently-connected) with longer-tail
  history.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Client fields

    * `id`, `mac`, `name`, `hostname`, `oui`
    * `is_wired`, `is_guest`
    * `first_seen`, `last_seen`, `connected_time`
    * `network`, `ap_mac` / `ap_name` for wireless
    * `manufacturer`, `os_name`
  """

  alias UnifiApi.Client

  @doc """
  Lists historical clients.

  ## Options

    * `:within_hours` — `withinHours=N`.
    * `:type` — filter by `"WIRED"` / `"WIRELESS"` / `"GUEST"` / `"VPN"`
      (sent as `type=...`).
    * `:search` — string match against name/hostname (`searchString=...`).
    * `:limit` — `pageSize=N`.
    * `:offset` — `pageNumber=N`.
  """
  @spec list(Req.Request.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def list(client, site_id, opts \\ []) do
    params =
      []
      |> maybe_param(:withinHours, opts[:within_hours])
      |> maybe_param(:type, opts[:type])
      |> maybe_param(:searchString, opts[:search])
      |> maybe_param(:pageSize, opts[:limit])
      |> maybe_param(:pageNumber, opts[:offset])

    Client.get_v1(client, "#{prefix()}/v2/api/site/#{site_id}/clients/history", params: params)
  end

  defp maybe_param(params, _key, nil), do: params
  defp maybe_param(params, key, value), do: [{key, value} | params]

  defp prefix, do: Client.v1_prefix()
end
