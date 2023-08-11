{
  perSystem = {
    pkgs,
    inputs',
    ...
  }: {
    packages.terraform = let
      inherit
        (inputs'.terraform-providers.legacyPackages.providers)
        hashicorp
        loafoe
        ;
    in
      pkgs.terraform.withPlugins (_: [
        hashicorp.aws
        hashicorp.external
        hashicorp.local
        hashicorp.null
        hashicorp.tls
        loafoe.ssh
      ]);
  };
}
