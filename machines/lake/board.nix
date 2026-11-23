{ config, ... }:
{
  imports = [ ../../modules/board.nix ];
  services.agent-board = {
    enable = true;
    tailnetHostname = "lake.tail3275e2.ts.net";
    allowedUsers = [ "imlunahey@github" ];
    routesFile = config.sops.secrets.board_t3_routes.path;
  };
  sops.secrets.board_t3_routes = {
    sopsFile = ../../secrets/board-t3-routes.json;
    format = "binary";
    restartUnits = [ "board-t3-bridge.service" ];
  };
}
