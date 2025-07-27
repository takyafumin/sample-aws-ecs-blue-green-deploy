# デプロイメントガイド

## 概要
このガイドでは、AWS ECS Blue/Greenデプロイメント環境の構築から運用まで、段階的な手順を説明します。

## 前提条件

### 必要なツール
- AWS CLI v2
- Docker
- Git

### AWS権限
以下の権限を持つIAMユーザーまたはロールが必要：
- CloudFormation: フルアクセス
- ECS: フルアクセス
- ECR: フルアクセス
- IAM: ロール作成権限
- VPC: フルアクセス

## Phase 1: 初期環境構築

### 1. GitHub OIDC設定（CI/CD用）

#### OIDCプロバイダー作成（初回のみ）
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

#### IAMロール作成
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-github-oidc \
  --template-body file://aws/cloudformation/github-oidc.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=GitHubOrg,ParameterValue=YOUR_GITHUB_USERNAME \
               ParameterKey=GitHubRepo,ParameterValue=sample-aws-ecs-blue-green-deploy \
  --capabilities CAPABILITY_NAMED_IAM
```

### 2. ネットワーク基盤構築
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-network \
  --template-body file://aws/cloudformation/network.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy
```

**作成されるリソース**:
- VPC (10.0.0.0/16)
- パブリックサブネット × 2
- プライベートサブネット × 2
- Internet Gateway
- NAT Gateway

### 3. ECRリポジトリ作成
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-ecr \
  --template-body file://aws/cloudformation/ecr.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy
```

### 4. 初回コンテナイメージプッシュ

#### ECRログイン
```bash
aws ecr get-login-password --region ap-northeast-1 | \
docker login --username AWS --password-stdin <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com
```

#### イメージビルド・プッシュ
```bash
# AMD64プラットフォーム指定でビルド
docker build --platform linux/amd64 -t ecs-bg-deploy-app .

# タグ付け
docker tag ecs-bg-deploy-app:latest \
  <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:latest

# プッシュ
docker push <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:latest
```

## Phase 2: Blue/Green ECS環境構築

### 5. Blue/Green環境作成
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-bluegreen \
  --template-body file://aws/cloudformation/ecs-bluegreen.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=ImageTag,ParameterValue=v1.0.0 \
  --capabilities CAPABILITY_IAM
```

**作成されるリソース**:
- ECSクラスター
- タスク定義
- ECSサービス（Blue/Green対応）
- Application Load Balancer
- ターゲットグループ × 2（Blue/Green用）
- ALBリスナー × 2（本番:80、テスト:8080）
- CodeDeployアプリケーション・デプロイメントグループ
- セキュリティグループ

### 6. 動作確認

#### ECSサービス状態確認
```bash
aws ecs describe-services \
  --cluster ecs-bg-deploy-cluster \
  --services ecs-bg-deploy-service \
  --query 'services[0].{Status:status,RunningCount:runningCount,DesiredCount:desiredCount}'
```

#### ALB DNS名取得
```bash
aws cloudformation describe-stacks \
  --stack-name ecs-bg-deploy-ecs \
  --query 'Stacks[0].Outputs[0].OutputValue' \
  --output text
```

#### アプリケーション確認
```bash
curl http://<ALB_DNS_NAME>
```

## Phase 3: Blue/Green環境への移行

### 7. 既存環境削除
```bash
aws cloudformation delete-stack --stack-name ecs-bg-deploy-ecs

# 削除完了まで待機
aws cloudformation wait stack-delete-complete --stack-name ecs-bg-deploy-ecs
```

### 8. Blue/Green環境構築
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-bluegreen \
  --template-body file://aws/cloudformation/ecs-bluegreen.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=ImageTag,ParameterValue=latest \
  --capabilities CAPABILITY_IAM
```

**追加されるリソース**:
- CodeDeployアプリケーション
- CodeDeployデプロイメントグループ
- Blue/Green対応ECSサービス

## Phase 4: Blue/Greenデプロイメント

### 9. 新バージョンのデプロイ

#### 新しいイメージの準備
```bash
# 新バージョンのビルド
docker build --platform linux/amd64 -t ecs-bg-deploy-app:v2.0.0 .

# タグ付け・プッシュ
docker tag ecs-bg-deploy-app:v2.0.0 \
  <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:v2.0.0
docker push <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:v2.0.0
```

#### デプロイスクリプト実行
```bash
./scripts/deploy.sh v2.0.0
```

または手動でCodeDeployを実行：

#### 新しいタスク定義作成
```bash
# 現在のタスク定義を取得
TASK_DEFINITION=$(aws ecs describe-task-definition \
  --task-definition ecs-bg-deploy-task \
  --query 'taskDefinition')

# 新しいイメージで更新
echo $TASK_DEFINITION | jq '.containerDefinitions[0].image = "<アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:v2.0.0"' | \
jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)' > new-task-def.json

# 新しいタスク定義を登録
aws ecs register-task-definition --cli-input-json file://new-task-def.json
```

#### CodeDeployでデプロイ実行
```bash
# appspec.yamlを使用してデプロイ
aws deploy create-deployment \
  --application-name ecs-bg-deploy-app \
  --deployment-group-name ecs-bg-deploy-dg \
  --revision revisionType=AppSpecContent,appSpecContent="$(cat appspec.yaml)"
```

### 10. デプロイメント監視

#### デプロイメント状況確認
```bash
# 最新のデプロイメントID取得
DEPLOYMENT_ID=$(aws deploy list-deployments \
  --application-name ecs-bg-deploy-app \
  --query 'deployments[0]' \
  --output text)

# デプロイメント詳細確認
aws deploy get-deployment --deployment-id $DEPLOYMENT_ID
```

#### ECSサービス状況確認
```bash
aws ecs describe-services \
  --cluster ecs-bg-deploy-cluster \
  --services ecs-bg-deploy-service
```

## Phase 5: GitHub Actions CI/CD設定

### 11. GitHub Secrets設定

GitHubリポジトリの Settings > Secrets and variables > Actions で設定：

```
AWS_ROLE_ARN: arn:aws:iam::<アカウントID>:role/ecs-bg-deploy-github-actions-role
AWS_REGION: ap-northeast-1
ECR_REPOSITORY: <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app
```

### 12. GitHub Actions ワークフロー

`.github/workflows/deploy.yml` を作成：

```yaml
name: Deploy to ECS

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      image_tag:
        description: 'Image tag to deploy'
        required: true
        default: 'latest'

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
        aws-region: ${{ secrets.AWS_REGION }}
    
    - name: Login to Amazon ECR
      uses: aws-actions/amazon-ecr-login@v2
    
    - name: Build and push image
      run: |
        IMAGE_TAG=${{ github.event.inputs.image_tag || github.sha }}
        docker build --platform linux/amd64 -t ${{ secrets.ECR_REPOSITORY }}:$IMAGE_TAG .
        docker push ${{ secrets.ECR_REPOSITORY }}:$IMAGE_TAG
    
    - name: Deploy to ECS
      run: |
        IMAGE_TAG=${{ github.event.inputs.image_tag || github.sha }}
        ./scripts/deploy.sh $IMAGE_TAG
```

## 運用・監視

### ログ確認
```bash
# CloudWatch Logsでログ確認
aws logs describe-log-streams \
  --log-group-name /ecs/ecs-bg-deploy

# 最新ログストリームの内容確認
aws logs get-log-events \
  --log-group-name /ecs/ecs-bg-deploy \
  --log-stream-name <log-stream-name>
```

### メトリクス監視
- ECS Service CPU/Memory使用率
- ALB Request Count/Response Time
- Target Group Healthy Host Count

### アラート設定例
```bash
# CPU使用率アラート
aws cloudwatch put-metric-alarm \
  --alarm-name "ECS-HighCPU" \
  --alarm-description "ECS CPU usage high" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2
```

## トラブルシューティング

### デプロイ失敗時の対処

#### 1. ロールバック実行
```bash
aws deploy stop-deployment \
  --deployment-id <DEPLOYMENT_ID> \
  --auto-rollback-enabled
```

#### 2. 手動ロールバック
```bash
# 前のタスク定義リビジョンに戻す
aws ecs update-service \
  --cluster ecs-bg-deploy-cluster \
  --service ecs-bg-deploy-service \
  --task-definition ecs-bg-deploy-task:<前のリビジョン>
```

### よくある問題

#### イメージプルエラー
- ECRにイメージが存在するか確認
- プラットフォーム（linux/amd64）が正しいか確認

#### ヘルスチェック失敗
- コンテナがポート80でリッスンしているか確認
- セキュリティグループ設定確認

#### デプロイタイムアウト
- タスク定義のリソース設定確認
- ヘルスチェック設定の調整

## クリーンアップ

### 全リソース削除
```bash
# Blue/Green環境削除
aws cloudformation delete-stack --stack-name ecs-bg-deploy-bluegreen

# ECR削除
aws cloudformation delete-stack --stack-name ecs-bg-deploy-ecr

# ネットワーク削除
aws cloudformation delete-stack --stack-name ecs-bg-deploy-network

# GitHub OIDC削除
aws cloudformation delete-stack --stack-name ecs-bg-deploy-github-oidc
```

### ECRイメージ削除
```bash
aws ecr list-images --repository-name ecs-bg-deploy-app
aws ecr batch-delete-image \
  --repository-name ecs-bg-deploy-app \
  --image-ids imageTag=latest imageTag=v2.0.0
```