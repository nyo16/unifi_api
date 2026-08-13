defmodule UnifiApi.Network.PortForward do
  @moduledoc """
  UniFi Network API (v1) — port-forward rules.

  Manages NAT port-forward rules on the gateway.

  Requires cookie + CSRF authentication. See `UnifiApi.Auth.Cookie`.

  ## Rule fields

    * `_id`, `name`, `enabled`
    * `proto` — `"tcp"`, `"udp"`, `"tcp_udp"`
    * `src` — source CIDR / `"any"`
    * `dst_port`, `fwd_port`, `fwd` (forward IP)
    * `pfwd_interface` — `"wan"`, `"wan2"`, `"both"`
    * `log` — boolean, log packets matching this rule
  """

  use UnifiApi.Resource, api: :network_v1

  @doc """
  Lists port-forward rules on a site.

  ## Options

  Validated with `Keyword.validate!/2` — an unknown key raises
  `ArgumentError` rather than being silently dropped.

    * `:limit` — page size, sent as the v1 `_limit` query param.
    * `:start` — page offset, sent as the v1 `_start` query param.
    * `:params` — extra query params, merged verbatim ahead of
      `_limit` / `_start`.
    * `:raw` — when `true`, return the raw response body binary (skips
      JSON decoding and the v1 envelope unwrap).

  ## Pagination — first page only, and there is no `stream/3`

  `/rest/portforward` is a v1 collection endpoint: it pages on
  `_start` / `_limit` and the `meta` envelope carries no total count, so a
  full page is indistinguishable from a truncated one. `list/3` returns
  **the first page only** whenever `:limit` is set, and whatever the
  controller's own default cap allows otherwise. This module has **no
  `stream/3`** — rule sets are hand-maintained and small. Page manually if
  yours is not: request `limit: n` and walk `:start` in steps of `n` until
  a page returns fewer than `n` items.

  Because a truncated read is indistinguishable from a complete one, never
  treat `list/3` as the authoritative rule set when computing a diff to
  apply back via `update/4` or `delete/3`.

  ## Examples

      {:ok, rules} = UnifiApi.Network.PortForward.list(authed, "default")

      # Explicit page of 100
      {:ok, rules} = UnifiApi.Network.PortForward.list(authed, "default",
        limit: 100, start: 0)
  """
  @spec list(Req.Request.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def list(client, site_id, opts \\ []) do
    opts = Keyword.validate!(opts, [:limit, :start, :params, :raw])

    params =
      opts
      |> Keyword.get(:params, [])
      |> maybe_param(:_limit, opts[:limit])
      |> maybe_param(:_start, opts[:start])

    Client.get_v1(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/rest/portforward",
      Keyword.take(opts, [:raw]) ++ [params: params]
    )
  end

  @doc """
  Returns a specific port-forward rule by id.
  """
  @spec get(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def get(client, site_id, rule_id) do
    Client.get_v1(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/rest/portforward/#{id!(rule_id)}"
    )
  end

  @doc """
  Creates a new port-forward rule.

  ## Examples

      {:ok, rule} = UnifiApi.Network.PortForward.create(client, "default", %{
        name: "Game server",
        enabled: true,
        proto: "tcp_udp",
        src: "any",
        dst_port: "25565",
        fwd: "192.168.1.50",
        fwd_port: "25565",
        pfwd_interface: "wan"
      })
  """
  @spec create(Req.Request.t(), String.t(), map()) :: {:ok, term()} | {:error, UnifiApi.Error.t()}
  def create(client, site_id, body) do
    Client.post(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/rest/portforward",
      body
    )
  end

  @doc """
  Updates an existing port-forward rule.
  """
  @spec update(Req.Request.t(), String.t(), String.t(), map()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def update(client, site_id, rule_id, body) do
    Client.put(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/rest/portforward/#{id!(rule_id)}",
      body
    )
  end

  @doc """
  Deletes a port-forward rule.
  """
  @spec delete(Req.Request.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, UnifiApi.Error.t()}
  def delete(client, site_id, rule_id) do
    Client.delete(
      client,
      "#{prefix(client)}/api/s/#{id!(site_id)}/rest/portforward/#{id!(rule_id)}"
    )
  end
end
