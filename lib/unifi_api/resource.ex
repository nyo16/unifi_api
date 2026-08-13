defmodule UnifiApi.Resource do
  @moduledoc """
  Shared plumbing for the endpoint modules.

  Every resource module under `UnifiApi.Network.*` and `UnifiApi.Protect.*`
  needs the same three things: the path prefix for its API surface, id
  validation before interpolation, and optional-query-param assembly. Before
  v0.4.0 that was 37 copies of `defp prefix`, 20 copies of `defp maybe_param`,
  and 115 inline `Client.validate_id!/1` calls — so a missing `validate_id!`
  in any one module was invisible, and moving the prefixes off global
  `Application` env would have meant 37 near-identical edits.

  ## Usage

      defmodule UnifiApi.Network.Devices do
        use UnifiApi.Resource, api: :network

        def get(client, site_id, device_id) do
          Client.get(client, "\#{prefix(client)}/v1/sites/\#{id!(site_id)}/devices/\#{id!(device_id)}")
        end
      end

  `api:` is one of `t:UnifiApi.Client.api/0` — `:network`, `:protect`,
  `:network_v1`, `:protect_v1`.

  ## What it injects

    * `alias UnifiApi.Client`
    * `prefix(client)` — this module's path prefix, read from the client
      (**not** from `Application` env; see `UnifiApi.Client.prefix/2`).
    * `id!(id)` — `UnifiApi.Client.validate_id!/1`, shortened because it
      appears inline in interpolations where a long name hurts readability.
    * `maybe_param(params, key, value)` — prepends `{key, value}` unless
      `value` is `nil`.
    * `maybe_csv(params, key, values)` — prepends a comma-joined `{key, csv}`
      unless `values` is `nil` or empty.

  All four are private to the using module. The macro also defines
  `__resource__/1` for introspection: `__resource__(:api)` returns the API
  surface and `__resource__(:helpers)` returns captures of the injected
  helpers, which is also what keeps an unused one from tripping
  `--warnings-as-errors`.
  """

  @doc false
  defmacro __using__(opts) do
    api = Keyword.fetch!(opts, :api)

    unless api in [:network, :protect, :network_v1, :protect_v1] do
      raise ArgumentError,
            "expected `use UnifiApi.Resource, api: _` to be one of " <>
              ":network, :protect, :network_v1, :protect_v1, got: #{inspect(api)}"
    end

    quote do
      alias UnifiApi.Client

      @resource_api unquote(api)

      @doc false
      def __resource__(:api), do: @resource_api

      # Also keeps every injected helper referenced. Not every resource uses
      # all four, and an unused private function is a warning — fatal under
      # `--warnings-as-errors`. `@compile {:nowarn_unused_function, ...}` is
      # not an option: the compiler still strips the unused function, leaving
      # the suppression pointing at nothing, and `mix dialyzer` then aborts
      # with "Unknown function maybe_param/3".
      @doc false
      def __resource__(:helpers), do: {&prefix/1, &id!/1, &maybe_param/3, &maybe_csv/3}

      defp prefix(client), do: Client.prefix(client, @resource_api)

      defp id!(id), do: Client.validate_id!(id)

      defp maybe_param(params, _key, nil), do: params
      defp maybe_param(params, key, value), do: [{key, value} | params]

      defp maybe_csv(params, _key, nil), do: params
      defp maybe_csv(params, _key, []), do: params

      defp maybe_csv(params, key, values) when is_list(values),
        do: [{key, Enum.join(values, ",")} | params]

      defp maybe_csv(params, key, value), do: [{key, value} | params]
    end
  end
end
