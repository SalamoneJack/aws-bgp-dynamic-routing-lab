# Architecture Diagram

Add your draw.io architecture diagram here as `architecture.png`.

## Suggested draw.io Elements

- Two VPC boxes: Cloud (AS 65001) and OnPrem-Sim (AS 65002)
- EC2 router instances in each VPC with BGP router ID labels
- Bidirectional arrow between routers labeled "eBGP session / TCP 179 / over IPSec tunnel"
- BGP table callout on each router showing local and learned routes
- AS numbers prominently labeled on each VPC
- Separate callout showing the layering: BGP → TCP → ESP (IPSec) → UDP 4500 → IP

## Export

Export as PNG at 1200px wide, save as `docs/architecture.png`.
Update the README image reference: `![Architecture](docs/architecture.png)`
