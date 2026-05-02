defmodule UnifiApi.MixProject do
  use Mix.Project

  @version "0.3.0"

  def project do
    [
      app: :unifi_api,
      version: @version,
      elixir: "~> 1.18",
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

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {UnifiApi.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp package do
    [
      maintainers: ["Niko Maroulis"],
      licenses: ["Apache-2.0"],
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
          UnifiApi.Formatter
        ],
        Errors: [
          UnifiApi.AuthError,
          UnifiApi.RateLimitError,
          UnifiApi.StreamError
        ],
        Authentication: [
          UnifiApi.Auth.Cookie
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
      {:req, "~> 0.5"},
      {:plug, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
