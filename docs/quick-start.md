# クイックスタートガイド

## 概要
このガイドでは、最短手順でAWS ECS Blue/Green環境を構築できます。

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

## 6ステップで構築

### 1. ネットワーク基盤構築
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-network \
  --template-body file://aws/cloudformation/network.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy
```

**作成されるリソース**: VPC、サブネット、Internet Gateway、NAT Gateway

### 2. ECRリポジトリ作成
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-ecr \
  --template-body file://aws/cloudformation/ecr.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy
```

### 3. GitHub OIDC設定（GitHub Actions使用時）
GitHub Actionsからデプロイする場合は、OIDC認証を設定：

```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-github-oidc \
  --template-body file://aws/cloudformation/github-oidc.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=GitHubOrg,ParameterValue=<あなたのGitHubユーザー名またはOrg> \
               ParameterKey=GitHubRepo,ParameterValue=<リポジトリ名> \
  --capabilities CAPABILITY_NAMED_IAM
```

**注意**: 手動デプロイのみの場合はこのステップをスキップ可能

### 4. コンテナイメージプッシュ

#### ECRログイン
```bash
aws ecr get-login-password --region ap-northeast-1 | \
docker login --username AWS --password-stdin <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com
```

#### イメージビルド・プッシュ
```bash
# AMD64プラットフォーム指定でビルド
docker build --platform linux/amd64 -t ecs-bg-deploy-app .

# タグ付け・プッシュ
docker tag ecs-bg-deploy-app:latest <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:latest
docker push <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:latest
```

### 5. Blue/Green ECS環境構築
```bash
aws cloudformation create-stack \
  --stack-name ecs-bg-deploy-bluegreen \
  --template-body file://aws/cloudformation/ecs-bluegreen.yaml \
  --parameters ParameterKey=ProjectName,ParameterValue=ecs-bg-deploy \
               ParameterKey=ImageTag,ParameterValue=latest \
  --capabilities CAPABILITY_IAM
```

**作成されるリソース**: ECSクラスター、ALB、CodeDeployアプリケーション、セキュリティグループ

### 6. 動作確認

#### ALB DNS名取得
```bash
ALB_DNS=$(aws cloudformation describe-stacks \
  --stack-name ecs-bg-deploy-bluegreen \
  --query 'Stacks[0].Outputs[0].OutputValue' \
  --output text)

echo "ALB DNS: $ALB_DNS"
```

#### アプリケーション確認
```bash
curl http://$ALB_DNS
```

## 新バージョンのデプロイ

### 新しいイメージの準備
```bash
# 新バージョンのビルド
docker build --platform linux/amd64 -t ecs-bg-deploy-app:v2.0.0 .

# タグ付け・プッシュ
docker tag ecs-bg-deploy-app:v2.0.0 <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:v2.0.0
docker push <アカウントID>.dkr.ecr.ap-northeast-1.amazonaws.com/ecs-bg-deploy-app:v2.0.0
```

### デプロイ実行
```bash
./scripts/deploy.sh v2.0.0
```

## トラブルシューティング

### よくある問題

#### 1. イメージプルエラー
```
CannotPullContainerError: image manifest does not contain descriptor
```
**解決**: AMD64プラットフォーム指定でビルド
```bash
docker build --platform linux/amd64 -t ecs-bg-deploy-app .
```

#### 2. スタック作成失敗
```
CREATE_FAILED: The following resource(s) failed to create
```
**確認手順**:
1. CloudFormationコンソールでエラー詳細確認
2. 必要な権限があるか確認
3. リソース制限に達していないか確認

#### 3. ヘルスチェック失敗
**確認手順**:
1. コンテナがポート80でリッスンしているか確認
2. セキュリティグループ設定確認
3. ターゲットグループのヘルスチェック設定確認

### デバッグコマンド

#### ECSサービス状態確認
```bash
aws ecs describe-services \
  --cluster ecs-bg-deploy-cluster \
  --services ecs-bg-deploy-service \
  --query 'services[0].{Status:status,RunningCount:runningCount,DesiredCount:desiredCount}'
```

#### ターゲットグループ状態確認
```bash
# ターゲットグループARN取得
TG_ARN=$(aws elbv2 describe-target-groups \
  --names ecs-bg-deploy-tg-1 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# ヘルス状態確認
aws elbv2 describe-target-health --target-group-arn $TG_ARN
```

## 次のステップ

### CI/CD設定
GitHub Actionsによる自動デプロイを設定する場合は、[デプロイメントガイド](deployment-guide.md#phase-5-github-actions-cicd設定)を参照してください。

### 監視設定
CloudWatchアラートやダッシュボードの設定については、[システムアーキテクチャ](architecture.md#監視ログ)を参照してください。

### 本番運用
本格的な運用を開始する前に、[ECS構築ガイド](ecs-setup.md#ベストプラクティス)のベストプラクティスを確認してください。

## クリーンアップ

### 全リソース削除
```bash
# Blue/Green環境削除
aws cloudformation delete-stack --stack-name ecs-bg-deploy-bluegreen

# GitHub OIDC削除（設定していた場合）
aws cloudformation delete-stack --stack-name ecs-bg-deploy-github-oidc

# ECR削除（イメージも削除される）
aws cloudformation delete-stack --stack-name ecs-bg-deploy-ecr

# ネットワーク削除
aws cloudformation delete-stack --stack-name ecs-bg-deploy-network
```

削除は依存関係の逆順で実行してください。各スタックの削除完了を待ってから次のスタックを削除することを推奨します。