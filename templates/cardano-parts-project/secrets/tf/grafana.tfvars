# To enable grafana cloud secrets usage:
#   * update the following with the appropriate grafana cloud secrets
#   * remove these comments
#   * encrypt this file with sops as a binary type using an age sre/admin secret key
#
# Expect this file to generate a pre-push error until it is either encrypted or deleted
deadmanssnitch_api_url = "UPDATE_ME"
grafana_cloud_api_key = "UPDATE_ME"
grafana_cloud_stack_region_slug = "UPDATE_ME"
mimir_alertmanager_uri = "UPDATE_ME"
mimir_alertmanager_username = "UPDATE_ME"
mimir_api_key = "UPDATE_ME"
mimir_prometheus_uri = "UPDATE_ME"
mimir_prometheus_username = "UPDATE_ME"
pagerduty_api_key = "UPDATE_ME"

