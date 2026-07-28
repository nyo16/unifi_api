defmodule UnifiApi.Auth.Session do
  @moduledoc """
  Supervised, auto-refreshing cookie + CSRF session.

  `UnifiApi.Auth.Cookie.login/4` returns a static `Req.Request.t()` —
  fine for one-shot scripts, but when the controller rotates the CSRF
  token mid-session, callers have to either notice the 403, manually
  call `refresh_csrf/2`, and retry, or just re-login.

  `UnifiApi.Auth.Session` wraps the auth state in a GenServer:

    * The request struct returned by `client/1` has request steps
      that pull the current cookies + CSRF from the GenServer at
      send time.
    * Response steps capture any rotated `x-csrf-token` header from
      the response and update the GenServer state for the next call.

  Use this in long-running pollers that mix reads and writes against
  the v1 / v2 endpoints.

  ## Why a GenServer

  A GenServer is justified here per the
  [Iron Law](https://hexdocs.pm/elixir/processes.html): the CSRF token
  mutates across calls and may be touched concurrently from multiple
  consumers in the same BEAM node. Read-only stateless usage should
  stick with `UnifiApi.Auth.Cookie.login/4`.

  ## Quick start

      children = [
        {UnifiApi.Auth.Session,
         name: MyApp.UnifiSession,
         client: UnifiApi.new(base_url: "https://192.168.1.1", verify_ssl: false),
         username: System.fetch_env!("UNIFI_USERNAME"),
         password: System.fetch_env!("UNIFI_PASSWORD"),
         style: :udm}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

      # Anywhere in your app:
      authed = UnifiApi.Auth.Session.client(MyApp.UnifiSession)
      UnifiApi.Network.Events.list(authed, "default")
  """

  use GenServer

  alias UnifiApi.Auth.Cookie

  @typedoc """
  Options accepted by `start_link/1`.

    * `:client` — base `Req.Request.t()` from `UnifiApi.new/1`. **Required.**
    * `:username` / `:password` — controller credentials. **Required.**
    * `:style` — `:udm` (default) or `:cloud_key`.
    * `:name` — process name (any GenServer name).
    * `:remember` — passed through to `UnifiApi.Auth.Cookie.login/4`.
  """
  @type option ::
          {:client, Req.Request.t()}
          | {:username, String.t()}
          | {:password, String.t()}
          | {:style, :udm | :cloud_key}
          | {:name, GenServer.name()}
          | {:remember, boolean()}

  @doc """
  Starts the session and logs in synchronously during `init/1`.

  Returns `{:error, %UnifiApi.AuthError{}}` (or other error term) if
  login fails — the supervisor will see this and apply its restart
  policy.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Returns a `Req.Request.t()` configured to pull current cookies + CSRF
  from this session on every request and to capture rotated tokens.

  The returned struct is safe to cache — its request/response steps
  reference the session pid, not a snapshot of the state.
  """
  @spec client(GenServer.server()) :: Req.Request.t()
  def client(session), do: GenServer.call(session, :client)

  @doc """
  Forces a CSRF refresh by issuing a lightweight GET against the
  controller. Useful after a 403 to recover without a full re-login.
  """
  @spec refresh(GenServer.server()) :: :ok | {:error, term()}
  def refresh(session), do: GenServer.call(session, :refresh)

  @doc """
  Forces a full re-login. Use this when the session has fully expired
  (typically a 401 on a request that worked previously).
  """
  @spec relogin(GenServer.server()) :: :ok | {:error, term()}
  def relogin(session), do: GenServer.call(session, :relogin, 30_000)

  @doc """
  Returns the current CSRF token.
  """
  @spec csrf_token(GenServer.server()) :: String.t() | nil
  def csrf_token(session), do: GenServer.call(session, :csrf_token)

  @doc false
  def child_spec(opts) do
    %{
      id: opts[:name] || __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    base = require_opt!(opts, :client)
    username = require_opt!(opts, :username)
    password = require_opt!(opts, :password)
    style = Keyword.get(opts, :style, :udm)
    remember = Keyword.get(opts, :remember, false)

    case Cookie.login(base, username, password, style: style, remember: remember) do
      {:ok, authed} ->
        state = %{
          base: base,
          username: username,
          password: password,
          style: style,
          remember: remember,
          authed: authed
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:client, _from, %{authed: authed} = state) do
    server = self()

    wrapped =
      authed
      |> drop_static_auth_headers()
      |> Req.Request.append_request_steps(unifi_session_inject: &inject_auth(&1, server))
      |> Req.Request.append_response_steps(
        unifi_session_capture: &capture_rotated_csrf(&1, server)
      )

    {:reply, wrapped, state}
  end

  def handle_call(:refresh, _from, state) do
    case Cookie.refresh_csrf(state.authed) do
      {:ok, refreshed} -> {:reply, :ok, %{state | authed: refreshed}}
      err -> {:reply, err, state}
    end
  end

  def handle_call(:relogin, _from, state) do
    case Cookie.login(state.base, state.username, state.password,
           style: state.style,
           remember: state.remember
         ) do
      {:ok, authed} -> {:reply, :ok, %{state | authed: authed}}
      err -> {:reply, err, state}
    end
  end

  def handle_call(:csrf_token, _from, state) do
    {:reply, Cookie.csrf_token(state.authed), state}
  end

  def handle_call(:auth_snapshot, _from, %{authed: authed} = state) do
    snapshot = %{
      cookie: header(authed, "cookie"),
      csrf: Cookie.csrf_token(authed)
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_cast({:csrf_rotated, token}, state) do
    new_authed =
      state.authed
      |> Req.Request.put_header("x-csrf-token", token)
      |> Req.Request.put_private(:unifi_api_csrf, token)

    {:noreply, %{state | authed: new_authed}}
  end

  # --- Helpers ---

  defp require_opt!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "UnifiApi.Auth.Session requires :#{key} option"
    end
  end

  defp inject_auth(req, server) do
    %{cookie: cookie, csrf: csrf} = GenServer.call(server, :auth_snapshot)

    req
    |> maybe_put_header("cookie", cookie)
    |> maybe_put_header("x-csrf-token", csrf)
  end

  defp capture_rotated_csrf({req, resp}, server) do
    case Req.Response.get_header(resp, "x-csrf-token") do
      [token | _] when is_binary(token) and token != "" ->
        GenServer.cast(server, {:csrf_rotated, token})
        {req, resp}

      _ ->
        {req, resp}
    end
  end

  defp drop_static_auth_headers(req) do
    req
    |> Req.Request.delete_header("cookie")
    |> Req.Request.delete_header("x-csrf-token")
  end

  defp header(req, name) do
    case Req.Request.get_header(req, name) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp maybe_put_header(req, _name, nil), do: req
  defp maybe_put_header(req, name, value), do: Req.Request.put_header(req, name, value)
end
