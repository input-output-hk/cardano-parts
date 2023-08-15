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

        ## More info
        - Bootstrap Wiki: [https://kb.devx.iog.io/doc/new-parts-clusters-GGx9b0zMYL](https://kb.devx.iog.io/doc/new-parts-clusters-GGx9b0zMYL)
      '';
    };
  };
}
