

Abstraction — the caller supplies team, environment, az_count. They never touch CIDR math, AZ names, or route table wiring.
Privilege (least privilege, network version) — isolated subnets get no path out at all; the default security group gets locked to nothing.
Encapsulation — subnet carving, routing, and NAT wiring all live inside the module; nothing about how it's built leaks out except the finished result (via outputs).
Volatility — we use for_each keyed by stable names (AZ names, tier names), not count/index, so adding one AZ later doesn't cause Terraform to destroy and recreate unrelated subnets — same reasoning we used for policy attachments.