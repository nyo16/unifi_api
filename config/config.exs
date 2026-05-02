import Config

config :unifi_api,
  base_url: "https://192.168.1.1",
  api_key: "",
  verify_ssl: false,
  # UDM defaults — for Cloud Key, set network_path / protect_path to
  # "/integration" and v1_path to "".
  network_path: "/proxy/network/integration",
  protect_path: "/proxy/protect/integration",
  v1_path: "/proxy/network"
