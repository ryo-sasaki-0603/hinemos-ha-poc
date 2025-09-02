output "hinemos_public_ip" { value = aws_instance.hinemos.public_ip }
output "db201_public_ip"   { value = aws_instance.db201.public_ip }
output "db202_public_ip"   { value = aws_instance.db202.public_ip }

output "db201_private_ip"  { value = aws_instance.db201.private_ip }
output "db202_private_ip"  { value = aws_instance.db202.private_ip }
output "vip_private_ip"    { value = aws_network_interface.vip.private_ips[0] }

output "shared_ebs_id"     { value = aws_ebs_volume.shared.id }
output "inventory_path"    { value = "${path.module}/../ansible/inventory.ini" }