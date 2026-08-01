{
  lib,
  pkgs,
  ...
}:

let
  ndi = pkgs.ndi;

  gstPluginNdi = pkgs.gst_all_1.gst-plugins-rs;

  videoDevice = "/dev/v4l/by-id/usb-Elgato_Elgato_4K_X_A7SNB507203FB8-video-index0";
in
{
  # The NDI SDK contains a proprietary, redistributable runtime.
  nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "ndi";

  services.avahi = {
    enable = true;
    publish = {
      enable = true;
      userServices = true;
    };
  };

  networking.firewall.interfaces.enp1s0 = {
    # NDI source discovery on the local network.
    allowedUDPPorts = [ 5353 ];
    # One NDI process uses a small number of ports starting at 5960.
    allowedTCPPortRanges = [
      {
        from = 5960;
        to = 5970;
      }
    ];
    allowedUDPPortRanges = [
      {
        from = 5960;
        to = 5970;
      }
    ];
  };

  systemd.paths.ndi-elgato = {
    description = "Watch for the Elgato 4K X capture device";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathExists = videoDevice;
      Unit = "ndi-elgato.service";
    };
  };

  systemd.services.ndi-elgato = {
    description = "Publish the Elgato 4K X as an NDI source";
    after = [
      "avahi-daemon.service"
      "sound.target"
    ];
    wants = [ "avahi-daemon.service" ];

    environment = {
      GST_PLUGIN_PATH = lib.concatStringsSep ":" (
        map (pkg: "${lib.getLib pkg}/lib/gstreamer-1.0") [
          pkgs.gst_all_1.gstreamer
          pkgs.gst_all_1.gst-plugins-base
          pkgs.gst_all_1.gst-plugins-good
          gstPluginNdi
        ]
      );
      GST_REGISTRY = "/var/lib/ndi-elgato/gstreamer-registry.bin";
      HOME = "/var/lib/ndi-elgato";
      NDI_RUNTIME_DIR_V5 = "${ndi}/lib";
    };

    unitConfig.StartLimitIntervalSec = 0;

    serviceConfig = {
      Type = "simple";
      User = "ndi-elgato";
      Group = "ndi-elgato";
      SupplementaryGroups = [
        "video"
        "audio"
      ];
      Restart = "on-failure";
      RestartSec = 5;
      StateDirectory = "ndi-elgato";
      UMask = "0077";

      ExecCondition = "${pkgs.coreutils}/bin/test -e ${videoDevice}";
      ExecStart = lib.concatStringsSep " " [
        "${lib.getBin pkgs.gst_all_1.gstreamer}/bin/gst-launch-1.0"
        "-e"
        "ndisinkcombiner name=combiner"
        "! ndisink ndi-name=Elgato-4K-X"
        "v4l2src device=${videoDevice} do-timestamp=true"
        "! video/x-raw,format=NV12,width=1920,height=1080,framerate=60/1"
        "! queue"
        "! combiner.video"
        "alsasrc device=hw:X do-timestamp=true"
        "! audio/x-raw,format=S16LE,rate=48000,channels=2"
        "! queue"
        "! audioconvert"
        "! audioresample"
        "! audio/x-raw,format=F32LE,rate=48000,channels=2,layout=interleaved"
        "! combiner.audio"
      ];

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  users.groups.ndi-elgato = { };
  users.users.ndi-elgato = {
    isSystemUser = true;
    group = "ndi-elgato";
  };
}
