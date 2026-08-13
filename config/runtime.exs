import Config

# `UNIFI_INSECURE_TLS=1` is a last-resort escape hatch for self-signed
# UDM/Cloud Key controllers whose owners cannot pin a fingerprint or
# install a trusted CA. Prefer `cert_fingerprints` or `verify_ssl: true`
# with a trusted CA whenever possible (CWE-295 / OWASP A02).
insecure_tls = System.get_env("UNIFI_INSECURE_TLS", "0") in ["1", "true"]

config :unifi_api,
  base_url: System.get_env("UNIFI_BASE_URL", "https://192.168.1.1"),
  api_key: System.get_env("UNIFI_API_KEY", ""),
  verify_ssl: not insecure_tls and System.get_env("UNIFI_VERIFY_SSL", "true") == "true",
  network_path: System.get_env("UNIFI_NETWORK_PATH", "/proxy/network/integration"),
  protect_path: System.get_env("UNIFI_PROTECT_PATH", "/proxy/protect/integration"),
  v1_path: System.get_env("UNIFI_V1_PATH", "/proxy/network")
