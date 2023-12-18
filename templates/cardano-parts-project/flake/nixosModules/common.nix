# {self, ...}:
{
  flake.nixosModules.common =
    # {config, ...}:
    {
      # Update auth-keys-hub config for your project's access requirements
      programs.auth-keys-hub.github = {
        # teams = ["input-output-hk/UPDATE_ME"];

        # Avoid loss of access edge cases when only github teams used for authorized key access
        # Edge case example:
        #   * Auth-keys-hub state defaults to the /run ephemeral state dir or subdirs
        #   * Only a github team is declared for auth-keys-hub access, and assume the github token secret is non-ephemeral
        #   * Another user deletes deletes the github token from github
        #   * The machine is rebooted
        #   * Auth keys hub state is now gone and the github token is required to pull new authorized key state, but it's no longer valid
        #   * Machine lockout occurs
        #
        # NOTE: auth-keys-hub update is required to support individual users when team fetch fails due to invalid or missing github token
        # users = ["UPDATE_ME"];

        # tokenFile = config.sops.secrets.github-token.path;
      };

      # Protect against remaining loss of access edge cases and black swan events
      # Edge case examples:
      #   a) Auth keys hub is deployed as the sole source of authorized keys
      #      * Auth keys hub is updated and a bug is introduced which expresses later on, causing machine lockout
      #   b) Auth keys hub is deployed as the sole source of authorized keys
      #      * Later, auth-keys-hub is removed from the deployment, but adding additional authorized_keys was forgotten
      #      * Machine lockout occurs
      #   c) Solar flare EMP knocking out a large number of machines over a large geographic area for some period of time
      #      * Github api is not available to pull fresh authorized key state and the ephermal storage was lost during reboot
      #      * Machine lockout occurs
      # users.users.root.openssh.authorizedKeys.keys = [
      #   "UPDATE_ME"
      # ];

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
