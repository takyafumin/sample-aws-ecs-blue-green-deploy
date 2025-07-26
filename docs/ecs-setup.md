# ECS構築ガイド

## 概要
AWS ECS Fargateを使用したシンプルなコンテナ実行環境の構築手順です。

## アーキテクチャ

### ネットワーク構成
- **VPC**: 10.0.0.0/16
- **Public Subnets**: 10.0.1.0/24, 10.0.2.0/24 (ALB配置)
- **Private Subnets**: 10.0.11.0/24, 10.0.12.0/24 (ECSタスク配置)

### リソース構成
- **ECS Cluster**: Fargateクラスター
- **Task Definition**: CPU 256, Memory 512のコンテナ定義
- **ECS Service**: 2タスクでの冗長構成
- **Application Load Balancer**: インターネット向けトラフィック制御
- **Target Group**: ECSタスクへのトラフィック転送

## CloudFormationテンプレート

### 1. ECRリポジトリ (`ecr.yaml`)
- **目的**: コンテナイメージの保存
- **リソース**: `AWS::ECR::Repository`
- **出力**: ECRリポジトリURI

### 2. ECSサービス (`ecs-simple.yaml`)
- **目的**: コンテナ実行環境
- **主要リソース**:
  - ECSクラスター
  - タスク定義
  - ECSサービス
  - ALB + ターゲットグループ
  - セキュリティグループ

## セキュリティ設定

### セキュリティグループ
- **ALB**: インターネットからポート80へのアクセス許可
- **ECS**: ALBからのみポート80へのアクセス許可

### IAMロール
- **TaskExecutionRole**: ECSタスク実行に必要な最小権限
  - ECRからのイメージプル
  - CloudWatch Logsへの書き込み

## 監視・ログ

### CloudWatch Logs
- **ロググループ**: `/ecs/ecs-bg-deploy`
- **保持期間**: 7日間
- **ログストリーム**: コンテナごとに自動作成

## トラブルシューティング

### よくある問題

#### 1. イメージプルエラー
```
CannotPullContainerError: image Manifest does not contain descriptor matching platform
```
**解決方法**: AMD64プラットフォーム指定でビルド
```bash
docker build --platform linux/amd64 -t ecs-bg-deploy-app .
```

#### 2. タスク起動失敗
```
Task failed to start
```
**確認手順**:
1. ECRにイメージが存在するか確認
2. タスク定義のイメージURIが正しいか確認
3. セキュリティグループの設定確認

#### 3. ヘルスチェック失敗
**確認手順**:
1. コンテナがポート80でリッスンしているか確認
2. ヘルスチェックパス(`/`)が正しく応答するか確認

## 動作確認コマンド

### ECSサービス状態確認
```bash
aws ecs describe-services \
  --cluster ecs-bg-deploy-cluster \
  --services ecs-bg-deploy-service \
  --query 'services[0].{Status:status,RunningCount:runningCount,DesiredCount:desiredCount}'
```

### ロードバランサーDNS取得
```bash
aws cloudformation describe-stacks \
  --stack-name ecs-bg-deploy-ecs \
  --query 'Stacks[0].Outputs[0].OutputValue' \
  --output text
```

### タスク詳細確認
```bash
aws ecs list-tasks --cluster ecs-bg-deploy-cluster
aws ecs describe-tasks --cluster ecs-bg-deploy-cluster --tasks <task-arn>
```

## 制限事項

### 現在の構成
- シンプルなECSサービス（Blue/Green未対応）
- 単一ターゲットグループ
- 手動デプロイのみ

### 今後の拡張予定
- CodeDeployによるBlue/Greenデプロイ
- GitHub Actionsによる自動デプロイ
- マルチターゲットグループ対応