defmodule UnifiApi.StreamError do
  @moduledoc """
  Raised when `UnifiApi.Client.stream/3` (or `stream_v1/3`/`stream_paged/2`)
  encounters an API error during pagination and the `:raise_errors` opt is
  enabled (default behaviour through v0.4.0).

  `:reason` is always one of the `t:UnifiApi.Error.t/0` members or a
  `{:unexpected_response, body_preview}` tuple, so it never carries a raw
  response body: bodies are reduced to a scrubbed, 128-character preview
  before the struct is built. This matters because the struct is *returned to
  the caller* as the stream's final element by default, so it reaches logs,
  `inspect/1`, and exception trackers whether or not it is ever raised
  (CWE-209 / OWASP A09).

  `:path` is retained verbatim for programmatic handling — it is what a caller
  needs to resume — and is redacted by `message/1`. Do not log it as-is.
  """

  defexception [:kind, :status, :reason, :path, :host]

  @type kind :: :auth | :rate_limit | :api | :transport | :unexpected | :unknown
  @type t :: %__MODULE__{
          kind: kind(),
          status: non_neg_integer() | :unknown,
          reason: term(),
          path: String.t(),
          host: String.t() | nil
        }

  @impl true
  def message(%__MODULE__{kind: kind, status: status, host: host}) do
    "stream request#{host_part(host)} failed (#{kind}: HTTP #{status})"
  end

  defp host_part(nil), do: ""
  defp host_part(host) when is_binary(host), do: " to #{redact_host(host)}"
  defp host_part(_), do: ""

  defp redact_host(host) do
    # Keep the registrable suffix; drop the label to avoid leaking internal hostnames.
    case String.split(host, ".", parts: 3) do
      [_label, tld] -> "*." <> tld
      [_label, dom, tld] -> "*." <> dom <> "." <> tld
      _ -> "***"
    end
  rescue
    _ -> "***"
  end
end
