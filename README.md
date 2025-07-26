# sample-aws-ecs-blue-green-deploy
ECS を Blue / Green デプロイするサンプル

## 概要
AWS ECS と CodeDeploy を使用した Blue/Green デプロイメント環境の構築サンプルです。
GitHub Actions を使用してビルドとデプロイを自動化します。

## アーキテクチャ
- **VPC**: 10.0.0.0/16
- **Public Subnets**: 10.0.1.0/24, 10.0.2.0/24
- **Private Subnets**: 10.0.11.0/24, 10.0.12.0/24
- **ECS Fargate**: Blue/Green デプロイメント
- **CodeDeploy**: デプロイメント管理
- **Application Load Balancer**: トラフィック制御

## デプロイ手順

### 1. ネットワーク構築
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-network \
  --template-body file://aws/cloudformation/network.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy
```

### 2. ECS リソース構築
```bash
# 後で追加予定
```

## ディレクトリ構成
```
.
├── aws/
│   └── cloudformation/
│       ├── network.yaml      # ネットワーク構成
│       └── ecs.yaml          # ECS関連リソース（予定）
├── .github/
│   └── workflows/
│       └── deploy.yml        # GitHub Actions（予定）
└── README.md
```
