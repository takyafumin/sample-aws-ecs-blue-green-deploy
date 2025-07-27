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

## ユースケース別手順

### 初期構築（インフラ構築）

#### 1. AWSリソース構築
```bash
# ネットワーク
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-network \
  --template-body file://aws/cloudformation/network.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy

# ECRリポジトリ
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-ecr \
  --template-body file://aws/cloudformation/ecr.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy

# 初回イメージプッシュ
./scripts/build.sh v1.0.0

# Blue/Green環境構築
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-bluegreen \
  --template-body file://aws/cloudformation/ecs-bluegreen.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=ImageTag,ParameterValue=v1.0.0 \
  --capabilities CAPABILITY_IAM
```

#### 2. GitHub Actions用OIDC設定（CI/CD使用時のみ）
```bash
# OIDCプロバイダー作成（初回のみ）
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# IAMロール作成
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-github-oidc \
  --template-body file://aws/cloudformation/github-oidc.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=GitHubOrg,ParameterValue=YOUR_GITHUB_USERNAME \
               ParameterKey=GitHubRepo,ParameterValue=sample-aws-ecs-blue-green-deploy \
  --capabilities CAPABILITY_NAMED_IAM

# GitHub Secrets設定
# Settings > Secrets and variables > Actions で AWS_ROLE_ARN を設定
```

### 開発（ローカルでの検証）

#### ソース修正からデプロイまで
```bash
# 1. ソースコード修正
vim index.html

# 2. 事前検証（オプション）
./test/verify.sh

# 3. 統合テスト（オプション）
./test/test-deploy.sh

# 4. 本番デプロイ
./scripts/dev-deploy.sh v2.0.0
```

#### 段階的実行
```bash
# ビルドのみ
./scripts/build.sh v2.0.0

# デプロイのみ（既存イメージ使用）
./scripts/deploy.sh v2.0.0
```

### GitHub Actionsでのデプロイ

#### 自動デプロイ
```bash
# タグプッシュで自動実行
git tag v2.0.0
git push origin v2.0.0
```

#### 手動実行
- GitHub > Actions > "Blue/Green Deploy" > "Run workflow"
- バージョンを入力して実行

> **詳細:** [docs/blue-green-deploy.md](docs/blue-green-deploy.md) を参照

## ドキュメント

- **[Blue/Greenデプロイ手順](docs/blue-green-deploy.md)**: デプロイの実行方法
- **[スクリプト責務設計](docs/scripts-responsibility.md)**: 各スクリプトの役割と使い分け

## ディレクトリ構成
```
.
├── aws/cloudformation/     # CloudFormationテンプレート
├── docs/                   # ドキュメント
│   ├── blue-green-deploy.md
│   └── scripts-responsibility.md
├── scripts/               # デプロイスクリプト
│   ├── build.sh           # イメージビルド・プッシュ
│   ├── deploy.sh          # Blue/Greenデプロイ
│   └── dev-deploy.sh      # 統合デプロイ
├── test/                  # テスト・検証スクリプト
│   ├── verify.sh          # 事前検証
│   └── test-deploy.sh     # 統合テスト
├── .github/workflows/     # GitHub Actions
├── appspec.yaml          # CodeDeploy設定
├── Dockerfile            # アプリケーションイメージ
└── index.html            # サンプルアプリ
```