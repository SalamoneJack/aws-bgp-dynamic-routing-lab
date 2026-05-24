output "cloud_router_eip" {
  description = "Public IP of the Cloud router (BGP AS 65001)"
  value       = aws_eip.cloud_router.public_ip
}

output "onprem_router_eip" {
  description = "Public IP of the OnPrem-Sim router (BGP AS 65002)"
  value       = aws_eip.onprem_router.public_ip
}

output "cloud_router_private_ip" {
  description = "Private IP of Cloud router — use as BGP neighbor address on OnPrem"
  value       = aws_network_interface.cloud_router.private_ip
}

output "onprem_router_private_ip" {
  description = "Private IP of OnPrem router — use as BGP neighbor address on Cloud"
  value       = aws_network_interface.onprem_router.private_ip
}

output "ssh_cloud_router" {
  description = "SSH command for Cloud router"
  value       = "ssh -i ~/.ssh/${var.key_pair}.pem ubuntu@${aws_eip.cloud_router.public_ip}"
}

output "ssh_onprem_router" {
  description = "SSH command for OnPrem-Sim router"
  value       = "ssh -i ~/.ssh/${var.key_pair}.pem ubuntu@${aws_eip.onprem_router.public_ip}"
}

output "bgp_config_summary" {
  description = "BGP session parameters to configure in FRR"
  value = {
    cloud_asn              = var.cloud_asn
    cloud_router_id        = aws_network_interface.cloud_router.private_ip
    cloud_neighbor_address = aws_network_interface.onprem_router.private_ip
    cloud_advertises       = var.cloud_cidr
    onprem_asn             = var.onprem_asn
    onprem_router_id       = aws_network_interface.onprem_router.private_ip
    onprem_neighbor_address = aws_network_interface.cloud_router.private_ip
    onprem_advertises      = var.onprem_cidr
  }
}
