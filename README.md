# hinemos-ha-poc

RHEL9 上に **Hinemos Manager + DB2 + Pacemaker (共有EBS + VIP切替)** を構築するための最小構成 POC リポジトリです。  
AWS 上に Terraform で環境を作成し、Ansible で初期設定を自動化します。  
Pacemaker のクラスタ設定（VIP/EBS 切替）は手動で行う前提です。

---

## リポジトリ取得方法

### Git Clone

```bash
$ git clone https://github.com/ryo-sasaki-0603/hinemos-ha-poc.git
$ cd hinemos-ha-poc
```

## Fork して利用する場合

GitHub ページ右上の Fork をクリックして、自分のアカウントにコピー

自分のリポジトリから clone

```bash
$ git clone https://github.com/<your-account>/hinemos-ha-poc.git
$ cd hinemos-ha-poc
```

## Terraform セットアップ

インストール (RHEL9)

```bash
$ sudo dnf install -y wget unzip
$ wget https://releases.hashicorp.com/terraform/1.8.5/terraform_1.8.5_linux_amd64.zip
$ unzip terraform_1.8.5_linux_amd64.zip
$ sudo mv terraform /usr/local/bin/
$ terraform -v
```

初期設定

```bash
$ cd terraform
$ cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集（例: key_name, my_ip_cidr, vip_private_ip）
terraform init
```

## Ansible セットアップ

インストール

```bash
$ sudo dnf install -y python3 python3-pip
$ cd ansible
$ python3 -m venv .venv
$ source .venv/bin/activate
$ pip install -r requirements.txt
```

疎通確認（Terraform で環境構築後）

```bash
$ ansible -i inventory.ini all -m ping
```

## AWS クレデンシャル準備

Terraform や Pacemaker リソースエージェントが AWS を操作するために、事前に AWS CLI とクレデンシャルの設定が必要です。

### 1. IAM ユーザー / IAM ロールの準備

- **ローカルPCから Terraform を実行**する場合  
  → IAM ユーザーを作成し、アクセスキー/シークレットキーを取得  
- **EC2 上で Terraform や Pacemaker を実行**する場合  
  → IAM ロールを EC2 にアタッチするのがおすすめ  

必要な最小権限例：

- `ec2:*` （VPC, EC2, EBS, ENI 作成/削除用）  
- `ec2:AttachVolume` / `ec2:DetachVolume`  
- `ec2:AssignPrivateIpAddresses` / `ec2:UnassignPrivateIpAddresses`  

---

### 2. AWS CLI インストール（RHEL9 の場合）

```bash
$ sudo dnf install -y unzip
$ curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
$ unzip awscliv2.zip
$ sudo ./aws/install
$ aws --version
```

### 3. AWS CLI 初期設定

```bash
$ aws configure
入力項目例：
AWS Access Key ID [None]: AKIAxxxxxxxxxxxxxxxx
AWS Secret Access Key [None]: xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Default region name [None]: ap-northeast-1
Default output format [None]: json
```

プロファイルを分けて管理する場合
例えば hinemos-ha という名前で管理する場合：

```bash
$ aws configure --profile hinemos-ha
```

Terraform 側の設定例（terraform/provider.tf）：

```hcl
provider "aws" {
  region  = "ap-northeast-1"
  profile = "hinemos-ha"
}
```


## 環境展開手順

1. Terraform で AWS 環境を構築

```bash
$ cd terraform
$ terraform apply -auto-approve
```

- 作成されるリソース:
  - VPC / サブネット / セキュリティグループ
  - EC2 (Hinemos, DB2ノード x2)
  - 共有EBS (gp3)
  - VIP用ENI
  - IAM Role (EBS/VIP操作権限)

2. 完了後、自動的に ansible/inventory.ini が生成されます。

3. Ansible で初期設定

```bash
$ cd ../ansible
$ source .venv/bin/activate
$ ansible-playbook -i inventory.ini site.yml
```

### 適用内容:

- ホスト名設定（SASAKIDB01 / SASAKIDB02）
- /etc/hosts に VIP (FQDN: SASAKIDB-VIP) 登録
- DB2 必須パッケージ導入
- Pacemaker 関連パッケージ導入
- Hinemos エージェントディレクトリ作成

## 手動で行う追加作業

Terraform/Ansible で基盤は整いますが、Pacemaker のリソース定義は手動で行います。

### 共有EBS 初期化（最初のノードで）

```bash
$ sudo mkfs.xfs /dev/xvdf
$ sudo mkdir -p /disk01
$ sudo mount /dev/xvdf /disk01
```

### Pacemaker クラスタ作成

```bash
$ sudo pcs cluster auth SASAKIDB01 SASAKIDB02 -u hacluster -p <password>
$ sudo pcs cluster setup --name sasaki_cluster SASAKIDB01 SASAKIDB02
$ sudo pcs cluster start --all
$ sudo pcs cluster enable --all
```

クラスタ全体の状態確認：

```bash
$ pcs status
```

Active/Standby の切り替え（マニュアルフェイルオーバー）
pcs node standby SASAKIDB01
→ SASAKIDB01 が Standby になり、リソース（EBS + /disk01 マウント）が自動的に SASAKIDB02 へ移動します。

再びアクティブに戻す

```bash
$ pcs node unstandby SASAKIDB01
```

### VIP リソース追加 (ENI付替)

AWS Resource Agent (resource-agents-cloud) またはスクリプトを利用し、VIP用ENIをアクティブノードへアタッチします。

EBS リソース追加
Pacemaker で共有EBSを管理します:
アクティブノード → アタッチ & マウント /disk01
フェイルオーバ時 → デタッチ & ピアへ再アタッチ

## 構成概要

- EC2
  - ec2-hinemos: RHEL9 / t2.medium
  - ec2-db201: RHEL9 / t3.large
  - ec2-db202: RHEL9 / t3.large
- ストレージ
  - 共有EBS (gp3, 50GiB) /dev/xvdf → /disk01
- VIP
  - ENI + Private IP（例: 10.10.1.200）
- FQDN: SASAKIDB-VIP
- セキュリティ
  - SSH (22) 自宅IPからのみ許可

## まとめ

Terraform: AWSリソースの自動作成
Ansible: OS/パッケージ/ホスト名/VIP設定の自動化
手動: Pacemaker クラスタ作成、VIP/EBSリソースの登録
