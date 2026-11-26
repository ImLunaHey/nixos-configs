# One exact-name zone per service leaves public flaked.org records (including
# mail, Pocket ID and NetBird bootstrap) with the normal DNS resolver.
let
  nova = "100.66.196.73";
  service = name: {
    domain = "${name}.flaked.org";
    address = nova;
    groups = [ "personal-devices" "homelab" "nixos:administrators" ];
  };
in {
  novaIPv4 = nova;
  services = map service [
    "jellyfin" "matrix" "pihole" "status" "s3" "romm" "immich"
    "watchstate" "s3-console"
  ];
}
