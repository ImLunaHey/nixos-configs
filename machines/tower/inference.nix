{ pkgs, ... }:
let
  server = import ../../packages/llama-cpp-inkling { inherit pkgs; };
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
      # Inkling-specific kernels allow a larger batch within the GPU memory cap.
      # Measurements, compatibility fixes and reproduction: benchmarks/tower-inkling/.
      ExecStart = "${server}/bin/llama-server --model ${model} --alias inkling-2-mini-abliterated --host 0.0.0.0 --port 8080 --metrics --jinja --ctx-size 32768 --parallel 1 --n-gpu-layers 99 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --batch-size 1024 --ubatch-size 512 --swa-compress";
      DynamicUser = true;
      SupplementaryGroups = [ "video" "render" ];
      StateDirectory = "inkling";
      WorkingDirectory = "/var/lib/inkling";
      Environment = [
        "HOME=/var/lib/inkling"
        "LD_LIBRARY_PATH=/run/opengl-driver/lib"
      ];
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
