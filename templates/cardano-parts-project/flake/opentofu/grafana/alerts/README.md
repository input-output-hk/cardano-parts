# Grafana Cloud Alert Configuration
* For consuming repositories configured to utilize grafana-cloud, any files in this directory ending in `*.nix-import` will be added to grafana-cloud alerts upon terraform apply
* Terraform apply for the grafana workspace is accomplished with: `just tf grafana apply`
* Grafana stackName must be declared in `flake/cluster.nix`
  * See `flakeModule/cluster.nix` option: `flake.cardano-parts.cluster.infra.grafana.stackName`
* Corresponding grafana cloud secrets must also exist in encrypted files:
```
secrets/monitoring/grafana-agent-metrics-password.enc
secrets/monitoring/grafana-agent-metrics-url.enc
secrets/monitoring/grafana-agent-metrics-username.enc
secrets/tf/grafana.tfvars
```
* Delete any files in this directory whose alerts are not desired
