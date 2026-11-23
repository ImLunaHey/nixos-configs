{ pkgs, ... }:
let
  server = pkgs.callPackage ../../packages/llama-cpp-cuda { };
  model = pkgs.fetchurl {
    name = "Inkling-2-Mini-Uncensored-AD-IQ3_S.gguf";
    url = "https://huggingface.co/AtomicChat/Inkling-2-Mini-Uncensored-GGUF/resolve/40886ab636cabb4decf4998224f790b462ab048e/Inkling-2-Mini-Uncensored-AD-IQ3_S.gguf";
    sha256 = "23a8e6792481b6f1d0ebad51399e9ee2a2c2be8525b09ed1ae6737811159f892";
  };
in
{
  systemd.services.inkling = {
    description = "Inkling 2 Mini abliterated inference (llama.cpp CUDA)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      # 192 improves cold prefill within this GPU's memory budget; 512 OOMs.
      # Measurements and reproduction: benchmarks/tower-inkling/README.md.
      ExecStart = "${server}/bin/llama-server --model ${model} --alias inkling-2-mini-abliterated --host 0.0.0.0 --port 8080 --metrics --jinja --ctx-size 32768 --parallel 1 --n-gpu-layers 99 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --batch-size 512 --ubatch-size 192";
      DynamicUser = true;
      SupplementaryGroups = [ "video" "render" ];
      StateDirectory = "inkling";
      WorkingDirectory = "/var/lib/inkling";
      Environment = "HOME=/var/lib/inkling";
      Restart = "on-failure";
      RestartSec = "10s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      UMask = "0077";
    };
  };

  # Inference is available to the home LAN and enrolled tailnet peers.
  networking.firewall.interfaces.enp7s0.allowedTCPPorts = [ 8080 ];
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8080 ];
}
