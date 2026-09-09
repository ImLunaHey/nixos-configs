{ ... }:
let
  cacheUrl = "http://100.94.132.48:5000";
  cachePublicKey = "lake-1:mg96P22gZ/PkBae8X3+n/fllIOwZKr3EZVGc9z9BZS0=";
in
{
  nix.settings = {
    substituters = [
      cacheUrl
    ];
    trusted-public-keys = [
      cachePublicKey
    ];
    connect-timeout = 2;
    fallback = true;
  };
}
