{
  perSystem = {
    lib,
    pkgs,
    ...
  }:
    with pkgs.python3Packages; {
      packages.ssh-config-json = buildPythonPackage {
        pname = "ssh-config-json";
        version = "unstable";
        src = pkgs.fetchFromGitHub {
          owner = "tubone24";
          repo = "ssh_config_json";
          rev = "master";
          hash = "sha256-XKjOnJw5fCSAjkNpZwz+hdrvdVZLfJezgtFOBBHeP+I=";
        };

        propagatedBuildInputs = [docopt pycryptodome];

        patchPhase = ''
          ${pkgs.gnused}/bin/sed -i 's/pycryptodome==3.12.0/pycryptodome>=3.12.0/g' requirements.txt setup.cfg
        '';

        doCheck = false;

        meta = {
          homepage = "https://ssh-config-json.readthedocs.io/";
          description = "SSH Config JSON is dumping JSON for your ssh config include IdentityFiles and restoring those.";
          license = lib.licenses.mit;
        };
      };
    };
}
