{
  inputs,
  lib,
  ...
}: {
  perSystem = {pkgs, ...}:
    with builtins;
    with lib;
    with pkgs; {
      packages.opentofu = let
        mkTerraformProvider = {
          owner,
          repo,
          version,
          src,
          registry ? "registry.opentofu.org",
        }: let
          inherit (go) GOARCH GOOS;
          provider-source-address = "${registry}/${owner}/${repo}";
        in
          stdenv.mkDerivation {
            pname = "terraform-provider-${repo}";
            inherit version src;

            unpackPhase = "unzip -o $src";

            nativeBuildInputs = [unzip];

            buildPhase = ":";

            # The upstream terraform wrapper assumes the provider filename here.
            installPhase = ''
              dir=$out/libexec/terraform-providers/${provider-source-address}/${version}/${GOOS}_${GOARCH}
              mkdir -p "$dir"
              mv terraform-* "$dir/"
            '';

            passthru = {
              inherit provider-source-address;
            };
          };

        readJSON = f: fromJSON (readFile f);

        # Fetch the latest version
        providerFor = owner: repo: let
          json = readJSON (inputs.opentofu-registry + "/providers/${substring 0 1 owner}/${owner}/${repo}.json");

          # Recent commits in opentofu-registry often append a version suffix of `-{alpha,beta}[0-9]+$`.
          # Tofu won't initialize these alpha and beta packages by default, so filter them out.
          stable = filter (e: match "^[0-9]+\.[0-9]+\.[0-9]+$" e.version != null) json.versions;

          latest = head stable;

          matching = filter (e: e.os == "linux" && e.arch == "amd64") latest.targets;
          target = head matching;
        in
          mkTerraformProvider {
            inherit (latest) version;
            inherit owner repo;
            src = fetchurl {
              url = target.download_url;
              sha256 = target.shasum;
            };
          };
      in
        opentofu.withPlugins (_: [
          (providerFor "fgouteroux" "loki")
          (providerFor "fgouteroux" "mimir")
          (providerFor "grafana" "grafana")
          (providerFor "opentofu" "aws")
          (providerFor "opentofu" "awscc")
          (providerFor "opentofu" "local")
          (providerFor "opentofu" "external")
          (providerFor "opentofu" "null")
          (providerFor "opentofu" "tls")
          (providerFor "loafoe" "ssh")
        ]);
    };
}
