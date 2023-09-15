# {self, ... }:
{
  flake.nixosModules.common =
    # {config, ...}:
    {
      # Update auth-keys-hub config for your project's access requirements
      programs.auth-keys-hub.github = {
        # teams = [
        #   "input-output-hk/UPDATE_ME"
        # ];

        # tokenFile = config.sops.secrets.github-token.path;
      };

      # For auth-keys-hub team access, create an encrypted github token
      # with org:read access at: ./secrets/github-token.enc,
      # then uncomment:
      # sops.secrets.github-token = {
      #   sopsFile = "${self}/secrets/github-token.enc";
      #   owner = config.programs.auth-keys-hub.user;
      #   inherit (config.programs.auth-keys-hub) group;
      # };
    };
}
