defmodule UnifiApi.TestTLSServer do
  @moduledoc """
  Minimal `:ssl` server for exercising `UnifiApi.Client`'s certificate
  pinning against a **real TLS handshake**.

  This exists because the rest of the suite talks to `Req.Test`'s plug
  adapter, which short-circuits in `Req.Finch` before `:ssl` is ever
  consulted. That blind spot let two separate defects ship: TLS options
  that `:ssl` rejects outright (`:server_name` is not an `:ssl` option, so
  it reached `gen_tcp:connect/4` and raised `:badarg` on every pinned
  connection), and a `verify_fun` that accepted any self-signed
  certificate without consulting the pin at all.

  Certificates are committed fixtures under `test/support/fixtures/tls`
  (100-year validity, so they do not rot) rather than generated per run:
  no `openssl` dependency at test time, and the expected fingerprints are
  stable enough to assert on.
  """

  @fixtures Path.join(__DIR__, "fixtures/tls")

  @doc """
  Starts a TLS listener serving `certfile`/`keyfile` from the fixture dir
  and returns its port. The listener and its acceptor die with the calling
  test process.
  """
  @spec start(String.t(), String.t()) :: pos_integer()
  def start(certfile, keyfile) do
    {:ok, listen} =
      :ssl.listen(0, [
        {:active, false},
        {:reuseaddr, true},
        {:certfile, fixture_charlist(certfile)},
        {:keyfile, fixture_charlist(keyfile)}
      ])

    {:ok, {_addr, port}} = :ssl.sockname(listen)
    test = self()

    acceptor =
      spawn(fn ->
        ref = Process.monitor(test)
        accept_loop(listen, ref)
      end)

    ExUnit.Callbacks.on_exit(fn ->
      Process.exit(acceptor, :kill)
      :ssl.close(listen)
    end)

    port
  end

  @doc """
  Returns the raw SHA-256 fingerprint of a fixture certificate — the same
  bytes `UnifiApi.Client.decode_fingerprint!/1` produces.
  """
  @spec fingerprint(String.t()) :: <<_::256>>
  def fingerprint(certfile) do
    :crypto.hash(:sha256, der(certfile))
  end

  @doc """
  Returns the hex fingerprint of a fixture certificate, in the form a
  caller would pass to `:cert_fingerprints`.
  """
  @spec fingerprint_hex(String.t()) :: String.t()
  def fingerprint_hex(certfile) do
    certfile |> fingerprint() |> Base.encode16(case: :lower)
  end

  defp der(certfile) do
    @fixtures
    |> Path.join(certfile)
    |> File.read!()
    |> :public_key.pem_decode()
    |> Enum.find_value(fn
      {:Certificate, der, _} -> der
      _ -> nil
    end)
  end

  defp fixture_charlist(name), do: @fixtures |> Path.join(name) |> String.to_charlist()

  # Serve handshakes until the owning test exits. Handshake failures are
  # expected (they are what the negative tests assert), so they are
  # swallowed rather than crashing the acceptor.
  defp accept_loop(listen, ref) do
    receive do
      {:DOWN, ^ref, :process, _pid, _reason} -> :ok
    after
      0 ->
        case :ssl.transport_accept(listen, 200) do
          {:ok, socket} ->
            _ = :ssl.handshake(socket, 1000)
            accept_loop(listen, ref)

          {:error, :timeout} ->
            accept_loop(listen, ref)

          {:error, _closed} ->
            :ok
        end
    end
  end
end
