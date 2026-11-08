# Exact peer IDs prevent a newly enrolled device with a familiar name from
# inheriting administrative or server access. Re-enrolments need explicit review.
let
  rule = name: sources: destinations: protocol: ports: bidirectional: {
    inherit name sources destinations protocol ports bidirectional;
    enabled = true;
    action = "accept";
  };
  policy = name: description: rules: {
    name = "nixos:${name}";
    inherit description rules;
    enabled = true;
  };
in {
  peers = {
    macbook = { id = "dbo8eia6lo5000c2j6eg"; ip = "100.66.198.238"; };
    gateway = { id = "dbo9jia6lo5000c2lg7g"; ip = "100.66.248.2"; };
    lake = { id = "dbo9jni6lo5000c2lh80"; ip = "100.66.200.157"; };
    nova = { id = "dbo9k1q6lo5000c2lipg"; ip = "100.66.196.73"; };
    void = { id = "dbo9kda6lo5000c2ll60"; ip = "100.66.117.84"; };
  };
  groups = {
    "nixos:administrators" = [ "macbook" ];
    "nixos:home-servers" = [ "lake" "nova" "void" ];
    "nixos:managed-servers" = [ "gateway" "lake" "nova" "void" ];
    "nixos:web-servers" = [ "nova" ];
  };
  # Membership in these groups is maintained by identity/setup-key enrolment.
  # Never replace their peer lists: CI runners and personal devices are dynamic.
  externalGroups = [ "github-deploy" "personal-devices" ];
  personalUser = "CiRmOTAwM2NkOS05N2NmLTQ4ZDYtOTY0ZS0yOWJjOTQ4YzU2NmUSFGRibzhrNWk2bG81MDAwYzJqZ2pn";
  personalAutoGroups = [ "personal-devices" ];
  policies = [
    (policy "administration" "Approved administrator devices to managed servers over TCP" [
      (rule "Administrative TCP" [ "nixos:administrators" ] [ "nixos:managed-servers" ] "tcp" [] false)
    ])
    (policy "administration-udp" "Approved administrator devices to managed servers over UDP" [
      (rule "Administrative UDP" [ "nixos:administrators" ] [ "nixos:managed-servers" ] "udp" [] false)
    ])
    (policy "administration-ping" "Permit administrator reachability diagnostics" [
      (rule "Administrative ping" [ "nixos:administrators" ] [ "nixos:managed-servers" ] "icmp" [] true)
    ])
    (policy "personal-web" "Personal devices reach Nova HTTPS; no SSH, storage or other server access" [
      (rule "HTTPS" [ "personal-devices" ] [ "nixos:web-servers" ] "tcp" [ "443" ] false)
    ])
    (policy "deployments" "Ephemeral GitHub runners may initiate SSH to the four deployment targets" [
      (rule "SSH" [ "github-deploy" ] [ "nixos:managed-servers" ] "tcp" [ "22" ] false)
    ])
    (policy "home-mesh" "Preserve local-server communication while excluding the public VPS" [
      (rule "Home servers" [ "nixos:home-servers" ] [ "nixos:home-servers" ] "all" [] true)
    ])
  ];
  # Explicitly adopted legacy IDs. Disable only after replacements are verified.
  retire = {
    "dbo7p3a6lo50008qo460" = "Default";
    "dbo88ka6lo5000c2ithg" = "Homelab mesh";
    "dbo88ka6lo5000c2itj0" = "GitHub SSH deployments";
    "dbo8fpa6lo5000c2j94g" = "Personal devices to homelab";
  };
}
