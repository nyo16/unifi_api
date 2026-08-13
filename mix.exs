defmodule UnifiApi.MixProject do
  use Mix.Project

  @version "0.4.0"

  def project do
    [
      app: :unifi_api,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "UnifiApi",
      description: "Elixir client for UniFi Dream Machine APIs (Network & Protect)",
      source_url: "https://github.com/nyo16/unifi_api",
      homepage_url: "https://github.com/nyo16/unifi_api",
      package: package(),
      docs: docs(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  # `test/support` holds the real-TLS-handshake harness used by the
  # certificate-pinning tests; it is compiled only under MIX_ENV=test and
  # is excluded from the Hex tarball by `package/0`'s `files:` allow-list.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  # Libraries must not ship an Application callback (`mod:`) — consumers
  # supervise `UnifiApi.Auth.Session` themselves if they need cookie
  # auth. See README "Installation".
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp package do
    [
      maintainers: ["Niko Maroulis"],
      licenses: ["Apache-2.0"],
      # Explicit allow-list: without it Hex packages every non-ignored path,
      # which would drag `priv/` (multi-MB dialyzer PLT) into the tarball.
      files: ~w(lib mix.exs README.md CHANGELOG.md UPGRADING.md LICENSE .formatter.exs),
      links: %{
        "GitHub" => "https://github.com/nyo16/unifi_api",
        "Changelog" => "https://github.com/nyo16/unifi_api/blob/master/CHANGELOG.md",
        "Upgrading" => "https://github.com/nyo16/unifi_api/blob/master/UPGRADING.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "UPGRADING.md", "LICENSE"],
      groups_for_modules: [
        Core: [
          UnifiApi,
          UnifiApi.Client
        ],
        "Network DPI": [
          UnifiApi.DPI.Names
        ],
        "Network API": [
          UnifiApi.Network.Info,
          UnifiApi.Network.Sites,
          UnifiApi.Network.Devices,
          UnifiApi.Network.Clients,
          UnifiApi.Network.Networks,
          UnifiApi.Network.Wifi,
          UnifiApi.Network.Firewall,
          UnifiApi.Network.Hotspot,
          UnifiApi.Network.ACL,
          UnifiApi.Network.DNS,
          UnifiApi.Network.TrafficMatching,
          UnifiApi.Network.Resources
        ],
        "Network API (Operational, v1)": [
          UnifiApi.Network.ActiveLeases,
          UnifiApi.Network.Alarms,
          UnifiApi.Network.Anomalies,
          UnifiApi.Network.ClientsHistory,
          UnifiApi.Network.ClientsLive,
          UnifiApi.Network.Dashboard,
          UnifiApi.Network.DPI,
          UnifiApi.Network.Events,
          UnifiApi.Network.IDS,
          UnifiApi.Network.PortAnomalies,
          UnifiApi.Network.PortForward,
          UnifiApi.Network.RogueAP,
          UnifiApi.Network.SystemLog,
          UnifiApi.Network.Topology,
          UnifiApi.Network.Traffic,
          UnifiApi.Network.UPS,
          UnifiApi.Network.WAN
        ],
        Utilities: [
          UnifiApi.Formatter,
          UnifiApi.Time
        ],
        Errors: [
          UnifiApi.AuthError,
          UnifiApi.RateLimitError,
          UnifiApi.StreamError
        ],
        Authentication: [
          UnifiApi.Auth.Cookie,
          UnifiApi.Auth.Session
        ],
        "Protect API": [
          UnifiApi.Protect.Cameras,
          UnifiApi.Protect.NVR,
          UnifiApi.Protect.Viewers,
          UnifiApi.Protect.Liveviews,
          UnifiApi.Protect.Sensors,
          UnifiApi.Protect.Lights,
          UnifiApi.Protect.Chimes
        ],
        "Protect API (v1)": [
          UnifiApi.Protect.Events
        ]
      ]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.7"},
      {:plug, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
