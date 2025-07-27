# sample-aws-ecs-blue-green-deploy
ECS を Blue / Green デプロイするサンプル

## 概要
AWS ECS Fargateを使用したコンテナ実行環境の構築サンプルです。
現在はシンプルなECSサービスが実装されており、将来的にCodeDeployを使用したBlue/Greenデプロイメント機能を追加予定です。

## アーキテクチャ

### 現在の実装
- **VPC**: 10.0.0.0/16
- **Public Subnets**: 10.0.1.0/24, 10.0.2.0/24 (ALB配置)
- **Private Subnets**: 10.0.11.0/24, 10.0.12.0/24 (ECSタスク配置)
- **ECS Fargate**: シンプルな2タスク構成
- **Application Load Balancer**: インターネット向けトラフィック制御
- **ECR**: コンテナイメージ保存

### 将来の拡張予定
- **CodeDeploy**: Blue/Greenデプロイメント管理
- **GitHub Actions**: CI/CDパイプライン

## デプロイ手順

### 1. GitHub OIDC設定
**OIDCプロバイダーの作成（初回のみ）:**
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

**IAMロールの作成:**
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-github-oidc \
  --template-body file://aws/cloudformation/github-oidc.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=GitHubOrg,ParameterValue=YOUR_GITHUB_USERNAME \
               ParameterKey=GitHubRepo,ParameterValue=sample-aws-ecs-blue-green-deploy \
  --capabilities CAPABILITY_NAMED_IAM
```

> **注意:** 
> - `YOUR_GITHUB_USERNAME` をあなたのGitHubユーザー名に置き換えてください。
> - OIDCプロバイダーが既に存在する場合は、最初のコマンドはスキップしてください。

**IAMロールARNの取得:**
```bash
aws cloudformation describe-stacks \
  --stack-name ecs-bg-deploy-github-oidc \
  --query 'Stacks[0].Outputs[?OutputKey==`GitHubActionsRoleArn`].OutputValue' \
  --output text
```

### 2. ネットワーク構築
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-network \
  --template-body file://aws/cloudformation/network.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy
```

### 3. ECRリポジトリ構築
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-ecr \
  --template-body file://aws/cloudformation/ecr.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy
```

### 4. 初回イメージのプッシュ
```bash
# ECRにログイン
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com

# AMD64プラットフォーム用イメージをビルド・プッシュ
docker build --platform linux/amd64 -t ecs-bg-deploy-app .
docker tag ecs-bg-deploy-app:latest <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:latest
docker push <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:latest
```

> **重要:** ECSサービスが起動時にイメージを参照するため、ECSリソース構築前にイメージをプッシュしてください。

### 5. ECS リソース構築
```bash
# 最新イメージを使用する場合
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-ecs \
  --template-body file://aws/cloudformation/ecs-simple.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
  --capabilities CAPABILITY_IAM

# 特定のイメージタグを指定する場合（推奨）
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-ecs \
  --template-body file://aws/cloudformation/ecs-simple.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=ImageTag,ParameterValue=v1.0.0 \
  --capabilities CAPABILITY_IAM
```

### 6. 動作確認
```bash
# ECSサービスの状態確認
aws ecs describe-services --cluster ecs-bg-deploy-cluster --services ecs-bg-deploy-service --query 'services[0].{Status:status,RunningCount:runningCount,DesiredCount:desiredCount}'

# ロードバランサーのDNS名取得
aws cloudformation describe-stacks --stack-name ecs-bg-deploy-ecs --query 'Stacks[0].Outputs[0].OutputValue' --output text
```

### 7. GitHub Secrets設定（将来のCI/CD用）
GitHubリポジトリの Settings > Secrets and variables > Actions で以下を設定:
- `AWS_ROLE_ARN`: 手順1で作成したIAMロールARN

### 8. Blue/Greenデプロイメントへの移行

**既存環境の削除:**
```bash
aws cloudformation delete-stack --stack-name ecs-bg-deploy-ecs
```

**Blue/Green環境の構築:**
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-bluegreen \
  --template-body file://aws/cloudformation/ecs-bluegreen.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=ImageTag,ParameterValue=latest \
  --capabilities CAPABILITY_IAM
```

**新バージョンのデプロイ:**
```bash
# スクリプトを使用（推奨）
./scripts/deploy.sh v2.0.0

# または手動でCodeDeployを実行
# 詳細は docs/blue-green-deploy.md を参照
```

## ディレクトリ構成
```
.
├── aws/
│   └── cloudformation/
│       ├── github-oidc.yaml    # GitHub OIDC設定
│       ├── network.yaml        # ネットワーク構成
│       ├── ecr.yaml            # ECRリポジトリ
│       ├── ecs-simple.yaml     # シンプルECSサービス
│       └── ecs-bluegreen.yaml  # Blue/Green ECSサービス
├── docs/
│   ├── ecs-setup.md        # ECS構築ガイド
│   ├── oidc-setup.md       # OIDC設定ガイド
│   └── blue-green-deploy.md # Blue/Greenデプロイ手順
├── scripts/
│   └── deploy.sh           # Blue/Greenデプロイスクリプト
├── .github/
│   └── workflows/
│       └── deploy.yml          # GitHub Actions（未完成）
├── appspec.yaml                # CodeDeploy設定
├── Dockerfile                  # アプリケーションイメージ
├── index.html                 # サンプルアプリ
└── README.md
```
