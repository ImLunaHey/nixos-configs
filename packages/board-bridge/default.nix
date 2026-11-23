{ buildGoModule, lib }:
buildGoModule {
  pname = "board-t3-bridge";
  version = "1.0.0";
  src = ./.;
  vendorHash = null;
  meta = {
    description = "Persistent Board event delivery to T3 Code webhooks";
    license = lib.licenses.mit;
    mainProgram = "board-bridge";
  };
}
