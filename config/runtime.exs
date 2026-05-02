import Config

config :unifi_api,
  base_url: System.get_env("UNIFI_BASE_URL", "https://192.168.1.1"),
  api_key: System.get_env("UNIFI_API_KEY", ""),
  verify_ssl: System.get_env("UNIFI_VERIFY_SSL", "false") == "true",
  network_path: System.get_env("UNIFI_NETWORK_PATH", "/proxy/network/integration"),
  protect_path: System.get_env("UNIFI_PROTECT_PATH", "/proxy/protect/integration"),
  v1_path: System.get_env("UNIFI_V1_PATH", "/proxy/network")
