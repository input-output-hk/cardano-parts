{
  flake.templates = rec {
    default = cardano-parts-project;
    cardano-parts-project = {
      path = ../templates/cardano-parts-project;
      description = "A simple cardano new parts project";
      welcomeText = ''
        # Simple Cardano New Parts Template
        ## Intended usage
        For new cardano clusters which will leverage the shared flake and nixOS modules of cardano-parts.

        ## Instructions and Info

        See the following READMEs in the order provided:

        * cardano-parts: [https://github.com/input-output-hk/cardano-parts/blob/main/README.md](https://github.com/input-output-hk/cardano-parts/blob/main/README.md)
        * The new cardano-parts project default README.md
      '';
    };
  };
}
