data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Cloud VPC (BGP AS 65001) ─────────────────────────────────────────────────

resource "aws_vpc" "cloud" {
  cidr_block           = var.cloud_cidr
  enable_dns_hostnames = true
  tags                 = { Name = "bgp-lab-cloud", BGP_ASN = tostring(var.cloud_asn) }
}

resource "aws_internet_gateway" "cloud" {
  vpc_id = aws_vpc.cloud.id
  tags   = { Name = "bgp-lab-cloud-igw" }
}

resource "aws_subnet" "cloud" {
  vpc_id            = aws_vpc.cloud.id
  cidr_block        = cidrsubnet(var.cloud_cidr, 8, 1)
  availability_zone = "${var.region}a"
  tags              = { Name = "bgp-lab-cloud-subnet" }
}

resource "aws_route_table" "cloud" {
  vpc_id = aws_vpc.cloud.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cloud.id
  }

  route {
    cidr_block           = var.onprem_cidr
    network_interface_id = aws_network_interface.cloud_router.id
  }

  tags = { Name = "bgp-lab-cloud-rt" }
}

resource "aws_route_table_association" "cloud" {
  subnet_id      = aws_subnet.cloud.id
  route_table_id = aws_route_table.cloud.id
}

resource "aws_security_group" "cloud_router" {
  name        = "bgp-lab-cloud-router-sg"
  description = "IPSec (IKE/NAT-T/ESP), BGP (TCP 179), SSH, ICMP"
  vpc_id      = aws_vpc.cloud.id

  ingress {
    description = "IKE"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ESP"
    from_port   = -1
    to_port     = -1
    protocol    = "50"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "BGP"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = [var.onprem_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.cloud_cidr, var.onprem_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bgp-lab-cloud-router-sg" }
}

resource "aws_network_interface" "cloud_router" {
  subnet_id         = aws_subnet.cloud.id
  private_ips       = [cidrhost(cidrsubnet(var.cloud_cidr, 8, 1), 10)]
  source_dest_check = false
  security_groups   = [aws_security_group.cloud_router.id]
  tags              = { Name = "bgp-lab-cloud-router-eni" }
}

resource "aws_eip" "cloud_router" {
  network_interface = aws_network_interface.cloud_router.id
  tags              = { Name = "bgp-lab-cloud-eip" }
}

resource "aws_instance" "cloud_router" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_pair

  network_interface {
    network_interface_id = aws_network_interface.cloud_router.id
    device_index         = 0
  }

  # Installs strongSwan (IPSec) + FRR (BGP) and enables IP forwarding
  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y strongswan strongswan-pki libcharon-extra-plugins curl gnupg
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    # Install FRR (Free Range Routing)
    curl -s https://deb.frrouting.org/frr/keys.gpg | tee /usr/share/keyrings/frrouting.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr $(lsb_release -s -c) frr-stable" | tee /etc/apt/sources.list.d/frr.list
    apt-get update -y
    apt-get install -y frr frr-pythontools

    # Enable BGP daemon
    sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons
    systemctl enable frr
    systemctl start frr
  EOF
  )

  tags = { Name = "bgp-lab-cloud-router", BGP_ASN = tostring(var.cloud_asn) }
}

# ── OnPrem-Sim VPC (BGP AS 65002) ────────────────────────────────────────────

resource "aws_vpc" "onprem" {
  cidr_block           = var.onprem_cidr
  enable_dns_hostnames = true
  tags                 = { Name = "bgp-lab-onprem", BGP_ASN = tostring(var.onprem_asn) }
}

resource "aws_internet_gateway" "onprem" {
  vpc_id = aws_vpc.onprem.id
  tags   = { Name = "bgp-lab-onprem-igw" }
}

resource "aws_subnet" "onprem" {
  vpc_id            = aws_vpc.onprem.id
  cidr_block        = cidrsubnet(var.onprem_cidr, 8, 1)
  availability_zone = "${var.region}a"
  tags              = { Name = "bgp-lab-onprem-subnet" }
}

resource "aws_route_table" "onprem" {
  vpc_id = aws_vpc.onprem.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.onprem.id
  }

  route {
    cidr_block           = var.cloud_cidr
    network_interface_id = aws_network_interface.onprem_router.id
  }

  tags = { Name = "bgp-lab-onprem-rt" }
}

resource "aws_route_table_association" "onprem" {
  subnet_id      = aws_subnet.onprem.id
  route_table_id = aws_route_table.onprem.id
}

resource "aws_security_group" "onprem_router" {
  name        = "bgp-lab-onprem-router-sg"
  description = "IPSec, BGP (TCP 179), SSH, ICMP"
  vpc_id      = aws_vpc.onprem.id

  ingress {
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "50"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = [var.cloud_cidr]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.cloud_cidr, var.onprem_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "bgp-lab-onprem-router-sg" }
}

resource "aws_network_interface" "onprem_router" {
  subnet_id         = aws_subnet.onprem.id
  private_ips       = [cidrhost(cidrsubnet(var.onprem_cidr, 8, 1), 10)]
  source_dest_check = false
  security_groups   = [aws_security_group.onprem_router.id]
  tags              = { Name = "bgp-lab-onprem-router-eni" }
}

resource "aws_eip" "onprem_router" {
  network_interface = aws_network_interface.onprem_router.id
  tags              = { Name = "bgp-lab-onprem-eip" }
}

resource "aws_instance" "onprem_router" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_pair

  network_interface {
    network_interface_id = aws_network_interface.onprem_router.id
    device_index         = 0
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y strongswan strongswan-pki libcharon-extra-plugins curl gnupg
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    curl -s https://deb.frrouting.org/frr/keys.gpg | tee /usr/share/keyrings/frrouting.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr $(lsb_release -s -c) frr-stable" | tee /etc/apt/sources.list.d/frr.list
    apt-get update -y
    apt-get install -y frr frr-pythontools

    sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons
    systemctl enable frr
    systemctl start frr
  EOF
  )

  tags = { Name = "bgp-lab-onprem-router", BGP_ASN = tostring(var.onprem_asn) }
}
