# To enable grafana iog monitoring secrets usage:
#   * update the following with the appropriate grafana secrets
#   * remove these comments
#   * encrypt this file with sops as a binary type using an age sre/admin secret key
#
# Expect this file to generate a pre-push error until it is either encrypted or deleted

# Obtainable from deadmanssnitch.com
deadmanssnitch_api_url = "UPDATE_ME"

# An admin permissions mimir API key
mimir_api_key = "UPDATE_ME"

# The alertmanager rules endpoint
mimir_alertmanager_ruler_uri = "https://${BASE_MONITORING_FQDN}/mimir/prometheus"

# The alertmanager endpoint
mimir_alertmanager_alertmanager_uri = "https://${BASE_MONITORING_FQDN}/mimir"

# The alertmanager admin username
mimir_alertmanager_username = "UPDATE_ME"

# The prometheus ruler endpoint
mimir_prometheus_ruler_uri = "https://${BASE_MONITORING_FQDN}/mimir/prometheus"

# The prometheus alertmanager endpoint
mimir_prometheus_alertmanager_uri = "https:/${BASE_MONITORING_FQDN}/mimir/alertmanager"

# The mimir admin username
mimir_prometheus_username = "UPDATE_ME"

# Obtainable from the pagerduty web UI under the prometheus service integration
pagerduty_api_key = "UPDATE_ME"

# An admin permissions grafana service account token, created at grafana UI > Administration > Service accounts
grafana_token = "UPDATE_ME"

# The base monitoring URL
grafana_url = "https://${BASE_MONITORING_FQDN}"
