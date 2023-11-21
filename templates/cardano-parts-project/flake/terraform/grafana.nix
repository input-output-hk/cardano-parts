{
  inputs,
  lib,
  config,
  ...
}:
with builtins;
with lib; let
  inherit (config.flake.cardano-parts.cluster.infra.grafana) stackName;

  cluster = config.flake.cardano-parts.cluster.infra.aws;

  alertFileList = parseDir ./grafana/alerts ".nix-import";
  dashboardFileList = parseDir ./grafana/dashboards ".json";
  recordingRulesFileList = parseDir ./grafana/recording-rules ".nix-import";

  underscore = replaceStrings ["-"] ["_"];
  extractFileName = file: unsafeDiscardStringContext (head (splitString "." (last (splitString "/" file))));
  parseDir = dirPath: suffix:
    mapAttrsToList (
      n: _: "${dirPath}/${n}"
    ) (filterAttrs (n: v: hasSuffix suffix n && v == "regular") (readDir dirPath));

  withGrafanaCloud = attrs: attrs // {provider = "grafana.cloud";};
  withGrafanaStack = attrs: attrs // {provider = "grafana.${stackName}";};

  sensitiveString = {
    type = "string";
    sensitive = true;
    nullable = false;
  };
in {
  flake.terraform.grafana = inputs.cardano-parts.inputs.terranix.lib.terranixConfiguration {
    system = "x86_64-linux";
    modules = [
      {
        terraform = {
          required_providers = {
            grafana.source = "grafana/grafana";
            mimir.source = "fgouteroux/mimir";
          };

          backend = {
            s3 = {
              inherit (cluster) region;
              bucket = cluster.bucketName;
              key = "terraform";
              dynamodb_table = "terraform";
            };
          };
        };

        variable = {
          deadmanssnitch_api_url = sensitiveString;
          grafana_cloud_api_key = sensitiveString;
          grafana_cloud_stack_region_slug = sensitiveString;
          mimir_alertmanager_uri = sensitiveString;
          mimir_alertmanager_username = sensitiveString;
          mimir_api_key = sensitiveString;
          mimir_prometheus_uri = sensitiveString;
          mimir_prometheus_username = sensitiveString;
          pagerduty_api_key = sensitiveString;
        };

        provider = {
          grafana = [
            {
              alias = "cloud";

              # Created at: https://grafana.com/orgs/$ORG_NAME/access-policies
              # Needs to have the following permissions:
              # - stacks:read (if the stack has already been created)
              # - stack-service-accounts:write
              cloud_api_key = "\${var.grafana_cloud_api_key}";
            }
            {
              alias = stackName;

              url = "\${grafana_cloud_stack.${stackName}.url}";
              auth = "\${grafana_cloud_stack_service_account_token.${stackName}.key}";
            }
          ];

          mimir = [
            {
              alias = "prometheus";
              ruler_uri = "\${var.mimir_prometheus_uri}";
              alertmanager_uri = "\${var.mimir_alertmanager_uri}";
              org_id = stackName;
              username = "\${var.mimir_prometheus_username}";
              password = "\${var.mimir_api_key}";
            }
            {
              alias = "alertmanager";
              ruler_uri = "\${var.mimir_prometheus_uri}";
              alertmanager_uri = "\${var.mimir_alertmanager_uri}";
              org_id = stackName;
              username = "\${var.mimir_alertmanager_username}";
              password = "\${var.mimir_api_key}";
            }
          ];
        };

        resource = {
          grafana_cloud_stack.${stackName} = withGrafanaCloud {
            name = "${stackName}.grafana.net";
            slug = stackName;
            region_slug = "\${var.grafana_cloud_stack_region_slug}";
          };

          grafana_cloud_stack_service_account.${stackName} = withGrafanaCloud {
            stack_slug = "\${grafana_cloud_stack.${stackName}.slug}";

            name = "terraform";
            role = "Admin";
          };

          grafana_cloud_stack_service_account_token.${stackName} = withGrafanaCloud {
            stack_slug = "\${grafana_cloud_stack.${stackName}.slug}";

            name = "terraform";
            service_account_id = "\${grafana_cloud_stack_service_account.${stackName}.id}";
          };

          grafana_contact_point.pagerduty = withGrafanaStack {
            name = "pagerduty";
            pagerduty.integration_key = "\${var.pagerduty_api_key}";
          };

          grafana_notification_policy.policy = withGrafanaStack {
            contact_point = "\${grafana_contact_point.pagerduty.name}";

            # Disable grouping
            group_by = ["..."];
          };

          mimir_alertmanager_config.pagerduty = {
            route = [
              {
                receiver = "pagerduty";
                group_by = ["..."];
                group_wait = "30s";
                group_interval = "5m";
                repeat_interval = "1y";
                child_route = [
                  {
                    receiver = "deadmanssnitch";
                    matchers = [''alertname="DeadMansSnitch"''];
                    group_wait = "30s";
                    group_interval = "5m";
                    repeat_interval = "5m";
                  }
                ];
              }
            ];

            receiver = [
              {
                name = "pagerduty";
                pagerduty_configs.service_key = "\${var.pagerduty_api_key}";
              }
              {
                name = "deadmanssnitch";
                webhook_configs = {
                  send_resolved = false;
                  url = "\${var.deadmanssnitch_api_url}";
                };
              }
            ];
            provider = "mimir.alertmanager";
          };

          # Dashboards
          grafana_dashboard = foldl' (acc: f:
            recursiveUpdate acc {
              ${underscore (extractFileName f)} = withGrafanaStack {config_json = readFile f;};
            }) {}
          dashboardFileList;

          # Alerts
          mimir_rule_group_alerting = foldl' (acc: f:
            recursiveUpdate acc {
              ${underscore (extractFileName f)} = import f // {provider = "mimir.prometheus";};
            }) {}
          alertFileList;

          # Recording rules
          mimir_rule_group_recording = foldl' (acc: f:
            recursiveUpdate acc {
              ${underscore (extractFileName f)} = import f // {provider = "mimir.prometheus";};
            }) {}
          recordingRulesFileList;
        };
      }
    ];
  };
}
