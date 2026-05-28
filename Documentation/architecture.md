# Architecture

## Data path

```mermaid
flowchart LR
    subgraph cloud["Cloud VPC — 10.10.0.0/16 — AS 65001"]
        cr["FRR Router EC2<br/>10.10.1.10<br/>advertises 10.10.0.0/16"]
    end
    subgraph onprem["OnPrem-Sim VPC — 10.20.0.0/16 — AS 65002"]
        opr["FRR Router EC2<br/>10.20.1.10<br/>advertises 10.20.0.0/16"]
    end
    cr <-->|"eBGP / TCP 179<br/>over IPSec tunnel<br/>IKEv2, AES-256, SHA-256"| opr
```

## Public read-only query path

```mermaid
flowchart LR
    browser["Browser<br/>jacksalamone.com widget"]
    apigw["API Gateway<br/>HTTP API"]
    lambda["Lambda<br/>bgp-status (Python)"]
    cr["Cloud Router<br/>(SSM-enabled)"]
    opr["OnPrem Router<br/>(SSM-enabled)"]

    browser -->|"GET /?cmd=...&router=..."| apigw
    apigw --> lambda
    lambda -->|"SSM SendCommand<br/>vtysh -c 'show ...'"| cr
    lambda -->|"SSM SendCommand<br/>vtysh -c 'show ...'"| opr
```

## Protocol stack

The lab demonstrates a real production protocol stack:

| Layer | Component | Implementation |
|---|---|---|
| Routing | BGP (eBGP between two ASes) | FRR (Free Range Routing) on Ubuntu |
| Reliability | TCP port 179 | Linux kernel TCP stack |
| Confidentiality | IPSec tunnel mode | strongSwan IKEv2 |
| Key exchange | IKEv2 | strongSwan with pre-shared key |
| Encryption | AES-256-CBC | strongSwan ESP |
| Integrity | HMAC-SHA-256 | strongSwan ESP |
| DH group | MODP-2048 (group 14) | strongSwan IKE |

This is the same stack AWS Site-to-Site VPN with BGP and AWS Direct Connect use under the hood. Configuring it manually proves understanding of every layer.

## Key configuration insight

FRR 10.x enforces eBGP connected-check by default — it silently refuses to initiate TCP connections to peers not in a directly-connected subnet. Since the peer is across an IPSec tunnel (not directly connected), `bgpd` never calls `connect()`. The fix:

```
neighbor 10.20.1.10 ebgp-multihop 2
neighbor 10.20.1.10 update-source eth0
```

Discovering this was the highest-value debugging moment in building the lab.
