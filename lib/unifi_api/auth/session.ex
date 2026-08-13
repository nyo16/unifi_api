defmodule UnifiApi.Auth.Session do
  @moduledoc """
  Supervised, auto-refreshing cookie + CSRF session.

  `UnifiApi.Auth.Cookie.login/4` returns a static `Req.Request.t()` —
  fine for one-shot scripts, but when the controller rotates the CSRF
  token mid-session, callers have to either notice the 403, manually
  call `refresh_csrf/1`, and retry, or just re-login.

  `UnifiApi.Auth.Session` wraps the auth state in a GenServer:

    * The request struct returned by `client/1` has request steps
      that pull the current cookies + CSRF from `:persistent_term`
      (keyed by a per-session ref) at send time — concurrent reads,
      no mailbox serialization.
    * Response steps capture any rotated `x-csrf-token` header from
      the response and update the GenServer state *and* the
      `:persistent_term` snapshot for the next call.

  Use this in long-running pollers that mix reads and writes against
  the v1 / v2 endpoints.

  ## Why a GenServer

  A GenServer is justified here per the
  [Iron Law](https://hexdocs.pm/elixir/processes.html): the CSRF token
  mutates across calls and the rotation write needs to be serialised.
  Reads, however, do *not* — they hit `:persistent_term` directly,
  so concurrent consumers of one session no longer block on a single
  mailbox. Read-only stateless usage should stick with
  `UnifiApi.Auth.Cookie.login/4`.

  ## Credentials

  The username/password are **not** stored as separate fields in the
  GenServer state (CWE-522). Supply a `:relogin` callback instead —
  the lib calls it only when a fresh login is needed and never holds
  the plaintext beyond the closure's own capture.

  `format_status/1` redacts the state, so `:sys.get_status/1` and the
  `State:` line of `:gen_server`'s abnormal-termination report carry only
  `style`/`remember`/`pid`.

  **One exposure remains, and it is a property of OTP's error reporting
  rather than of this module.** If a crash inside a callback is a
  `FunctionClauseError` (or another error that captures its arguments), the
  *stacktrace* prints those arguments — and the argument may be the authed
  `Req.Request`, whose `cookie` and `x-csrf-token` headers Req's `Inspect`
  implementation renders verbatim. `format_status/1` cannot intercept a
  stacktrace. If you forward crash reports to a third party, scrub
  `cookie` and `x-csrf-token` at your `Logger` backend or error-tracker
  boundary.

  ## Quick start

      children = [
        {UnifiApi.Auth.Session,
         name: MyApp.UnifiSession,
         client: UnifiApi.new(base_url: "https://192.168.1.1",
                   cert_fingerprints: System.get_env("UNIFI_CERT_FINGERPRINTS", "")
                   |> String.split(",", trim: true)),
         relogin: fn ->
           UnifiApi.Auth.Cookie.login(
             UnifiApi.new(base_url: "https://192.168.1.1"),
             System.fetch_env!("UNIFI_USERNAME"),
             System.fetch_env!("UNIFI_PASSWORD"),
             style: :udm
           )
         end,
         style: :udm}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

      # Anywhere in your app:
      authed = UnifiApi.Auth.Session.client(MyApp.UnifiSession)
      UnifiApi.Network.Events.list(authed, "default")

  ### Legacy `username`/`password` (deprecated, v0.5 removal)

  For backward compatibility, `:username` + `:password` are still
  accepted — the session synthesises a `:relogin` closure from them.
  This keeps the plaintext alive for the process lifetime via the
  closure, so prefer the explicit `:relogin` callback for new code.
  """

  use GenServer

  alias UnifiApi.Auth.Cookie

  @pt_prefix {__MODULE__, :snapshot}

  # Both mutating calls perform a full HTTP round trip against the
  # controller, so the call timeout has to exceed the HTTP budget of the
  # client the session was built with (`Client.new/1` defaults: 5s connect +
  # 30s receive, one retry). Callers who raise those pass their own timeout.
  @call_timeout 60_000

  @typedoc """
  Options accepted by `start_link/1`.

    * `:client` — base `Req.Request.t()` from `UnifiApi.new/1`. **Required.**
    * `:relogin` — 0-arity callback returning `{:ok, Req.Request.t()} |
      {:error, term()}`. Preferred over `:username`/`:password` (CWE-522).
    * `:username` / `:password` — controller credentials. **Deprecated**
      (v0.5 removal): supply `:relogin` instead. When given, the session
      builds an internal `:relogin` closure that calls
      `UnifiApi.Auth.Cookie.login/4` with them.
    * `:style` — `:udm` (default) or `:cloud_key`.
    * `:name` — process name (any GenServer name).
    * `:remember` — passed through to `UnifiApi.Auth.Cookie.login/4`.
  """
  @type option ::
          {:client, Req.Request.t()}
          | {:relogin, (-> {:ok, Req.Request.t()} | {:error, term()})}
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
  Returns a `Req.Request.t()` configured to pull the current cookies + CSRF
  from this session on every request and to capture rotated tokens.

  This is a plain `:persistent_term` read — **no message is sent to the
  session process**. That matters: `handle_call(:relogin, ...)` performs a
  blocking HTTP round trip, so while a re-login is in flight a
  `GenServer.call`-based `client/1` would park every caller in the session's
  mailbox behind a full login.

  Raises if the session is not running, matching what a `GenServer.call/2`
  to a dead process did.
  """
  @spec client(GenServer.server()) :: Req.Request.t()
  def client(session) do
    case lookup(session) do
      %{wrapped: wrapped} -> wrapped
      nil -> exit({:noproc, {__MODULE__, :client, [session]}})
    end
  end

  @doc """
  Forces a CSRF refresh by issuing a lightweight GET against the
  controller. Useful after a 403 to recover without a full re-login.

  `timeout` must exceed the HTTP budget of the client this session was built
  with. The default is #{@call_timeout}ms; the previous 5s default reliably
  raised `exit(:timeout)` while the session process carried on working, and
  took every queued caller down with it.
  """
  @spec refresh(GenServer.server(), timeout()) :: :ok | {:error, term()}
  def refresh(session, timeout \\ @call_timeout),
    do: GenServer.call(session, :refresh, timeout)

  @doc """
  Forces a full re-login. Use this when the session has fully expired
  (typically a 401 on a request that worked previously).

  Concurrent callers are **coalesced**: the request carries the monotonic
  timestamp at which it was made, and if a login has already succeeded
  *after* that instant the session replies `:ok` immediately instead of
  logging in again. On expiry every consumer sees a 401 at once, and without
  this the requests serialise into N sequential full logins hammering the
  controller.
  """
  @spec relogin(GenServer.server(), timeout()) :: :ok | {:error, term()}
  def relogin(session, timeout \\ @call_timeout) do
    GenServer.call(session, {:relogin, System.monotonic_time(:millisecond)}, timeout)
  end

  @doc """
  Returns the current CSRF token. Like `client/1`, a direct
  `:persistent_term` read with no process hop.
  """
  @spec csrf_token(GenServer.server()) :: String.t() | nil
  def csrf_token(session) do
    case lookup(session) do
      %{csrf: csrf} -> csrf
      nil -> nil
    end
  end

  defp lookup(session) do
    case GenServer.whereis(session) do
      pid when is_pid(pid) -> :persistent_term.get({@pt_prefix, pid}, nil)
      _ -> nil
    end
  end

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
    style = Keyword.get(opts, :style, :udm)
    remember = Keyword.get(opts, :remember, false)

    relogin_fn = build_relogin_fn(opts, base, style, remember)

    case relogin_fn.() do
      {:ok, authed} ->
        server = self()

        # The wrapped struct is built once and published alongside the
        # cookie/CSRF snapshot, so `client/1` is a lock-free read. The
        # request step still resolves the *current* credentials at send
        # time, so a struct handed out before a re-login stays valid after.
        wrapped =
          authed
          |> drop_static_auth_headers()
          |> Req.Request.append_request_steps(unifi_session_inject: &inject_auth(&1, server))
          |> Req.Request.append_response_steps(
            unifi_session_capture: &capture_rotated_csrf(&1, server)
          )

        state = %{
          base: base,
          style: style,
          remember: remember,
          relogin: relogin_fn,
          authed: authed,
          wrapped: wrapped,
          last_login_at: System.monotonic_time(:millisecond)
        }

        publish(server, authed, wrapped)

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  # Only the two *mutating* operations go through the mailbox: they rotate
  # shared credentials and must serialise. Reads do not (see `client/1`).
  @impl true
  def handle_call(:refresh, _from, state) do
    case Cookie.refresh_csrf(state.authed) do
      {:ok, refreshed} ->
        {:reply, :ok, put_authed(state, refreshed)}

      err ->
        {:reply, err, state}
    end
  end

  def handle_call({:relogin, requested_at}, _from, state) do
    if state.last_login_at > requested_at do
      # A login already succeeded after this caller observed its failure, so
      # the credentials it failed with are stale and the current ones are
      # not. Coalesce instead of hammering the controller once per consumer.
      {:reply, :ok, state}
    else
      case state.relogin.() do
        {:ok, authed} ->
          state = %{state | last_login_at: System.monotonic_time(:millisecond)}
          {:reply, :ok, put_authed(state, authed)}

        err ->
          {:reply, err, state}
      end
    end
  end

  # The snapshot has already been rotated synchronously by the response
  # step (see `capture_rotated_csrf/2`); this only keeps the process's own
  # copy of the authed struct in step, since `refresh`/`relogin` build on it.
  @impl true
  def handle_cast({:csrf_rotated, token}, state) do
    new_authed =
      state.authed
      |> Req.Request.put_header("x-csrf-token", token)
      |> Req.Request.put_private(:unifi_api_csrf, token)

    {:noreply, %{state | authed: new_authed}}
  end

  @impl true
  def terminate(_reason, _state) do
    :persistent_term.erase({@pt_prefix, self()})
    :ok
  end

  # `:gen_server`'s default abnormal-termination handler logs
  # `State: #{inspect(state)}`, and `handle_call({:relogin, _})` does network
  # I/O, so that path is reachable in production. The raw state holds the
  # authed `Req.Request` — whose `cookie` and `x-csrf-token` headers Req's
  # `Inspect` implementation renders verbatim — plus a `:relogin` closure
  # that, on the deprecated `:username`/`:password` path, captures the
  # plaintext credentials. Report only what is useful for debugging
  # (CWE-209 / CWE-532 / OWASP A09).
  @impl true
  def format_status(%{state: state} = status) when is_map(state) do
    %{status | state: %{style: state.style, remember: state.remember, pid: self()}}
  end

  def format_status(status), do: status

  # --- Helpers ---

  defp require_opt!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "UnifiApi.Auth.Session requires :#{key} option"
    end
  end

  defp build_relogin_fn(opts, base, style, remember) do
    case Keyword.fetch(opts, :relogin) do
      {:ok, fun} when is_function(fun, 0) ->
        fun

      _ ->
        username = Keyword.get(opts, :username)
        password = Keyword.get(opts, :password)

        if is_binary(username) and is_binary(password) do
          fn ->
            Cookie.login(base, username, password,
              style: style,
              remember: remember
            )
          end
        else
          raise ArgumentError,
                "UnifiApi.Auth.Session requires either :relogin (0-arity callback) " <>
                  "or both :username and :password"
        end
    end
  end

  # One `:persistent_term` entry per session process holds everything the
  # lock-free readers need: the credentials the request step injects, plus
  # the pre-built wrapped struct `client/1` hands out.
  defp publish(server, authed, wrapped) do
    put_entry(server, %{
      cookie: header(authed, "cookie"),
      csrf: Cookie.csrf_token(authed),
      wrapped: wrapped
    })
  end

  # Folds a rotated authed struct into the state and republishes it.
  defp put_authed(state, authed) do
    publish(self(), authed, state.wrapped)
    %{state | authed: authed}
  end

  # Skip writes that would not change anything. Every
  # `:persistent_term.put/2` triggers a global scan of every process to
  # find references to the old term — measured at 169µs with 2000 live
  # processes — and UniFi controllers echo `x-csrf-token` on essentially
  # every response, so the unconditional write fired constantly for no
  # reason.
  defp put_entry(server, entry) do
    key = {@pt_prefix, server}

    case :persistent_term.get(key, nil) do
      ^entry -> :ok
      _ -> :persistent_term.put(key, entry)
    end
  end

  defp inject_auth(req, server) do
    case :persistent_term.get({@pt_prefix, server}, nil) do
      %{cookie: cookie, csrf: csrf} ->
        req
        |> maybe_put_header("cookie", cookie)
        |> maybe_put_header("x-csrf-token", csrf)

      nil ->
        req
    end
  end

  # Runs in the *calling* process, as part of that request's response steps.
  #
  # The snapshot is rotated here rather than in the `:csrf_rotated` cast: the
  # request step resolves credentials from the snapshot at send time, so
  # leaving the write to the GenServer's mailbox opens a window in which the
  # caller's next request injects the token the controller just replaced and
  # gets a 403 — the exact failure this module exists to prevent. The cast
  # still fires, to keep the process's own `authed` copy current.
  defp capture_rotated_csrf({req, resp}, server) do
    case Req.Response.get_header(resp, "x-csrf-token") do
      [token | _] when is_binary(token) and token != "" ->
        rotate_snapshot(server, token)
        GenServer.cast(server, {:csrf_rotated, token})
        {req, resp}

      _ ->
        {req, resp}
    end
  end

  # Only touches `:csrf`. A concurrent `refresh`/`relogin` republishing the
  # whole entry is the one thing that can race here, and it rotates the
  # cookie too, so letting the later write win is correct either way.
  defp rotate_snapshot(server, token) do
    key = {@pt_prefix, server}

    case :persistent_term.get(key, nil) do
      # Unchanged token: skip the write and its global scan (the common case,
      # since controllers echo the header on essentially every response).
      %{csrf: ^token} ->
        :ok

      %{} = entry ->
        :persistent_term.put(key, %{entry | csrf: token})

      nil ->
        # Session is terminating and the entry is already erased.
        :ok
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
