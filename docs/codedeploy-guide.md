# CodeDeploy Blue/Green デプロイガイド

## CodeDeploy構成

### アプリケーション設定

| 項目 | 値 | 説明 |
|------|---|------|
| **アプリケーション名** | `ecs-bg-deploy-app` | CodeDeployアプリケーション |
| **プラットフォーム** | `ECS` | コンテナベースデプロイ |
| **デプロイメントグループ** | `ecs-bg-deploy-dg` | デプロイ対象の管理単位 |

### デプロイ設定

| 設定項目 | 値 | 効果 |
|---------|---|------|
| **デプロイ設定** | `CodeDeployDefault.ECSAllAtOnceBlueGreen` | 全トラフィック一括切り替え |
| **デプロイタイプ** | `BLUE_GREEN` | 無停止デプロイメント |
| **トラフィック制御** | `WITH_TRAFFIC_CONTROL` | ALBによる段階的切り替え |

## Blue/Green環境管理

### 環境切り替えフロー

```mermaid
sequenceDiagram
    participant CD as CodeDeploy
    participant ALB as Application Load Balancer
    participant Blue as Blue Environment
    participant Green as Green Environment
    participant Tester as Manual Tester
    
    CD->>Green: 新タスク定義でGreen環境作成
    Green->>CD: ヘルスチェック完了通知
    CD->>ALB: テスト用ポート8080でGreen環境公開
    Tester->>Green: 手動テスト実行（10分間）
    Tester->>CD: 手動承認またはデプロイ停止
    CD->>ALB: 本番トラフィックをGreenに切り替え
    ALB->>Green: 本番トラフィック転送開始
    CD->>Blue: 5分後にBlue環境終了
```

### 環境設定

| 環境 | 役割 | エンドポイント | ライフサイクル |
|------|------|---------------|---------------|
| **Blue** | 現在の本番環境 | `:80` (本番) | デプロイ成功後5分で自動終了 |
| **Green** | 新しいデプロイ環境 | `:8080` (テスト) | ヘルスチェック後→手動テスト→本番昇格 |

## appspec.yaml設定

```yaml
version: 0.0
Resources:
  - TargetService:
      Type: AWS::ECS::Service
      Properties:
        TaskDefinition: <TASK_DEFINITION>  # 動的に置換
        LoadBalancerInfo:
          ContainerName: "app"
          ContainerPort: 80
```

### 設定項目説明

| 項目 | 説明 | 動作 |
|------|------|------|
| **TaskDefinition** | 新しいコンテナイメージ | デプロイ時に動的置換 |
| **ContainerName** | ターゲットコンテナ | `app`コンテナを指定 |
| **ContainerPort** | コンテナポート | HTTP:80でサービス提供 |

## 手動承認設定

### タイムアウト設定

```yaml
BlueGreenDeploymentConfiguration:
  TerminateBlueInstancesOnDeploymentSuccess:
    Action: TERMINATE
    TerminationWaitTimeInMinutes: 5  # Blue環境終了待機時間
  DeploymentReadyOption:
    ActionOnTimeout: STOP_DEPLOYMENT  # 手動承認必要
    WaitTimeInMinutes: 10  # 手動テスト時間
```

### 設定の詳細

| 設定項目 | 値 | 説明 |
|---------|---|------|
| **TerminationWaitTimeInMinutes** | `5` | デプロイ成功後、Blue環境を終了するまでの待機時間 |
| **Action** | `TERMINATE` | 待機時間経過後にBlue環境を自動終了 |
| **ActionOnTimeout** | `STOP_DEPLOYMENT` | タイムアウト時はデプロイ停止（手動承認必要） |
| **WaitTimeInMinutes** | `10` | 手動テストのための待機時間 |

## 手動テスト手順

### Green環境テスト

```bash
# 1. デプロイメントID取得
DEPLOYMENT_ID=$(aws deploy list-deployments \
  --application-name ecs-bg-deploy-app \
  --query 'deployments[0]' --output text)

# 2. Green環境でテスト実行
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names ecs-bg-deploy-alb \
  --query 'LoadBalancers[0].DNSName' --output text)

curl http://$ALB_DNS:8080/

# 3. 問題なければ手動承認
aws deploy continue-deployment --deployment-id $DEPLOYMENT_ID

# 4. 問題あれば停止
aws deploy stop-deployment --deployment-id $DEPLOYMENT_ID
```

### テスト項目

| テスト項目 | コマンド | 期待結果 |
|-----------|---------|----------|
| **ヘルスチェック** | `curl -f http://$ALB_DNS:8080/` | HTTP 200 |
| **レスポンス内容** | `curl http://$ALB_DNS:8080/` | 新バージョンの内容 |
| **パフォーマンス** | `curl -w "%{time_total}" http://$ALB_DNS:8080/` | 1秒以下 |

### タイムアウト動作

- **10分以内**: 手動で承認または停止必要
- **10分経過**: 自動的にデプロイ停止

## 自動ロールバック設定

### ロールバック条件

| 条件 | トリガー | 動作 |
|------|---------|------|
| **DEPLOYMENT_FAILURE** | デプロイ失敗 | 自動的に前バージョンに復旧 |
| **DEPLOYMENT_STOP_ON_ALARM** | CloudWatchアラーム | 監視メトリクス異常時に復旧 |

### ロールバック設定

```yaml
AutoRollbackConfiguration:
  Enabled: true
  Events:
    - DEPLOYMENT_FAILURE
    - DEPLOYMENT_STOP_ON_ALARM
```

## トラフィック制御

### ALB設定

| コンポーネント | 設定 | 役割 |
|---------------|------|------|
| **本番リスナー** | HTTP:80 | 本番トラフィック受信 |
| **テストリスナー** | HTTP:8080 | Green環境テスト用 |
| **ターゲットグループ1** | `ecs-bg-deploy-tg-1` | Blue環境用 |
| **ターゲットグループ2** | `ecs-bg-deploy-tg-2` | Green環境用 |
| **ヘルスチェック** | `GET /` | コンテナ正常性監視 |

### セキュリティグループ

| グループ | 用途 | ルール |
|---------|------|--------|
| **ALBSecurityGroup** | ALB用 | インターネットからHTTP:80,8080許可 |
| **ECSSecurityGroup** | ECSタスク用 | ALBからのHTTP:80のみ許可 |

## デプロイ監視

### 状態確認コマンド

```bash
# デプロイ状況確認
aws deploy get-deployment --deployment-id <DEPLOYMENT_ID>

# ECSサービス状態確認
aws ecs describe-services \
  --cluster ecs-bg-deploy-cluster \
  --services ecs-bg-deploy-service

# タスク状態確認
aws ecs list-tasks \
  --cluster ecs-bg-deploy-cluster \
  --service-name ecs-bg-deploy-service
```

### 監視メトリクス

| メトリクス | 監視項目 | 閾値 |
|-----------|---------|------|
| **HealthyHostCount** | 正常なターゲット数 | 最低1台 |
| **ResponseTime** | レスポンス時間 | 1秒以下 |
| **HTTPCode_Target_5XX_Count** | サーバーエラー | 0件 |

## 運用上の注意点

### リソース使用量

| フェーズ | CPU使用量 | メモリ使用量 | 期間 |
|---------|-----------|-------------|------|
| **通常運用** | 256 CPU × 2タスク | 512MB × 2タスク | 常時 |
| **デプロイ中** | 256 CPU × 4タスク | 512MB × 4タスク | 約15分 |

### コスト影響

- **デプロイ中**: 一時的にリソース2倍使用（約15分間）
- **成功後**: Blue環境自動削除でコスト最適化
- **失敗時**: 自動ロールバックで追加コストなし

### 制限事項

| 項目 | 制限 | 対処法 |
|------|------|--------|
| **同時デプロイ** | 1つまで | 前回デプロイ完了後に実行 |
| **手動テスト時間** | 10分間 | 時間内に承認または停止必要 |
| **ロールバック期間** | デプロイ後24時間 | 手動でタスク定義を戻す |
| **ダウンタイム** | 0秒 | Blue/Green切り替えで無停止 |