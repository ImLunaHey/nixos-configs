# Resend sending verification for flaked.org (eu-west-1). Public DNS data only.
[
  {
    name = "resend._domainkey.flaked.org";
    type = "TXT";
    content = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDL0yuzOBFSLSsa77ohoe0yQESc1yv/6yWB66RMhTMttyqpeF1DE3Sj9JBSPcG1dhoRrppGIJ+EIEvjndtmRyy3LW6cbUSkjqgj2hJ31O1QSG/We/DYrHNFKPj8Ghz9pe4jiBbHRsX4PrQWFLB6QTJ/QmKOBG0UtEI3hfd2qcozjwIDAQAB";
  }
  {
    name = "send.flaked.org";
    type = "MX";
    content = "feedback-smtp.eu-west-1.amazonses.com";
    priority = 10;
  }
  {
    name = "send.flaked.org";
    type = "TXT";
    content = "v=spf1 include:amazonses.com ~all";
  }
  {
    name = "rsend.flaked.org";
    type = "CNAME";
    content = "send.forge.rmta.net";
  }
]
