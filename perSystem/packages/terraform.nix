{
  perSystem = {
    pkgs,
    inputs',
    ...
  }: {
    packages.terraform = let
      inherit
        (inputs'.terraform-providers.legacyPackages.providers)
        fgouteroux
        grafana
        hashicorp
        loafoe
        ;
    in
      pkgs.terraform.withPlugins (_: [
        fgouteroux.loki
        fgouteroux.mimir
        grafana.grafana
        hashicorp.aws
        hashicorp.external
        hashicorp.local
        hashicorp.null
        hashicorp.tls
        loafoe.ssh
      ]);
  };
}
