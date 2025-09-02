# hinemos-ha-poc

RHEL9上でDB2＋Pacemakerの共有ディスク(Attach/Detach)＋VIP(ENI移動)方式の最小構成POC。  
命名規則: `<project>-<env>-<awsサービス名>` 例: `hinemos-poc-ec2-db201`

## 構成概要
- VPC（10.10.0.0/16）
- Public Subnet（10.10.1.0/24, 単一AZ）
- EC2:
  - ec2-hinemos: RHEL9 / t2.medium
  - ec2-db201, ec2-db202: RHEL9 / t3.large（同一AZ）
- 共有EBS(gp3) 50GiB: 初期はdb201にアタッチ（/dev/xvdf）
- VIP: Public Subnet内のENI(10.10.1.200など)をフェイルオーバで付替
- セキュリティ: SSH(22)のみ自宅IPから許可

> 注意: ENI/VIP/共有EBSの切替は**同一AZ**が前提。Pacemakerの具体的なリソース設定は手動工程。

---

## 1) 事前準備
- AWS: RHEL9の利用権限/AMIアクセス（Red Hat公式）
- 既存のEC2キーペア名（`key_name`）
- 自宅グローバルIP（`my_ip_cidr`）
- Terraform v1.6+ / Ansible v9+ / Python3

## 2) Terraform で環境作成
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集（key_name, my_ip_cidr, vip_private_ip等）

terraform init
terraform apply -auto-approve
