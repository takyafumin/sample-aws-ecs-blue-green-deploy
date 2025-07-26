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

### 3. ECS リソース構築
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-ecs \
  --template-body file://aws/cloudformation/ecs.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
  --capabilities CAPABILITY_IAM
```

### 4. 初回イメージのプッシュ
```bash
# ECRにログイン
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com

# イメージをビルド・プッシュ
docker build -t ecs-bg-deploy-app .
docker tag ecs-bg-deploy-app:latest <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:latest
docker push <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:latest
```

### 5. GitHub Secrets設定
GitHubリポジトリの Settings > Secrets and variables > Actions で以下を設定:
- `AWS_ROLE_ARN`: 手順1で作成したIAMロールARN

### 6. デプロイ
mainブランチにプッシュすると自動でBlue/Greenデプロイが実行されます。

## ディレクトリ構成
```
.
├── aws/
│   └── cloudformation/
│       ├── github-oidc.yaml  # GitHub OIDC設定
│       ├── network.yaml      # ネットワーク構成
│       └── ecs.yaml          # ECS関連リソース
├── .github/
│   └── workflows/
│       └── deploy.yml        # GitHub Actions
├── Dockerfile                # アプリケーションイメージ
├── index.html               # サンプルアプリ
└── README.md
```
