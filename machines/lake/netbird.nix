{ ... }:
{
  # Lake trusts enrolled peers; other hosts open only SSH on wt0 by default.
  networking.firewall.trustedInterfaces = [ "wt0" ];
}
