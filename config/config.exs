import Config

config :unifi_api,
  base_url: "https://192.168.1.1",
  api_key: "",
  # Secure by default (CWE-295 / OWASP A02). Set to `false` only for
  # self-signed controllers behind a trusted network, or pin the leaf
  # cert with `cert_fingerprints`. See README "Self-Signed Certificates".
  verify_ssl: true,
  # UDM defaults — for Cloud Key, set network_path / protect_path to
  # "/integration" and v1_path to "".
  network_path: "/proxy/network/integration",
  protect_path: "/proxy/protect/integration",
  v1_path: "/proxy/network"
