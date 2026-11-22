{ lib, buildGoModule }:
buildGoModule {
  pname = "hardware-telemetry";
  version = "1.0.0";
  src = lib.cleanSource ./.;
  vendorHash = "sha256-szHwC68zQUD87ZB4Dy+loGFbTw7Y3XkXLSxFhB0w3Gk=";
  env.CGO_ENABLED = "0";
  meta.mainProgram = "hardware-telemetry";
}
