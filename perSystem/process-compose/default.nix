{
  perSystem = {self', ...}: {
    process-compose.demo = {
      package = self'.packages.process-compose;
      settings = {
        processes = {
          demosay.command = ''
            while true; do
              echo "Enjoy the big demo!"
              sleep 2
            done
          '';
        };
      };
    };
  };
}
