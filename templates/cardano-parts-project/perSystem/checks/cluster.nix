{
  perSystem = {
    lib,
    system,
    ...
  }:
    lib.optionalAttrs (system == "x86_64-linux") {
      # TODO: add some useful tests here
    };
}
