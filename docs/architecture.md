# システムアーキテクチャ

## 概要
AWS ECS Fargateを使用したコンテナ実行環境で、Blue/Greenデプロイメントに対応したアーキテクチャです。

## システム構成図

### Blue/Green構成（ecs-bluegreen.yaml）
```mermaid
graph TB
    Internet([Internet])
    
    subgraph VPC ["VPC (10.0.0.0/16)"]
        subgraph PublicSubnets ["Public Subnets"]
            PubSub1["Public Subnet 1<br/>10.0.1.0/24<br/>ap-northeast-1a"]
            PubSub2["Public Subnet 2<br/>10.0.2.0/24<br/>ap-northeast-1c"]
        end
        
        ALB["Application Load Balancer<br/>(internet-facing)"]
        IGW["Internet Gateway"]
        NAT["NAT Gateway"]
        
        CodeDeploy["CodeDeploy<br/>Blue/Green Traffic Control"]
        
        subgraph PrivateSubnets ["Private Subnets"]
            PrivSub1["Private Subnet 1<br/>10.0.11.0/24<br/>ap-northeast-1a"]
            PrivSub2["Private Subnet 2<br/>10.0.12.0/24<br/>ap-northeast-1c"]
        end
        
        subgraph BlueEnv ["Blue Environment"]
            BlueTask1["ECS Task<br/>(Current Version)"]
        end
        
        subgraph GreenEnv ["Green Environment"]
            GreenTask1["ECS Task<br/>(New Version)"]
        end
        
        ECR["ECR Repository"]
    end
    
    Internet --> IGW
    IGW --> ALB
    ALB --> CodeDeploy
    CodeDeploy --> BlueTask1
    CodeDeploy --> GreenTask1
    
    BlueTask1 --> PrivSub1
    GreenTask1 --> PrivSub2
    
    PrivSub1 --> NAT
    PrivSub2 --> NAT
    NAT --> PubSub1
    PubSub1 --> IGW
    
    BlueTask1 -.-> ECR
    GreenTask1 -.-> ECR
    
    ALB --> PubSub1
    ALB --> PubSub2
    
    classDef publicSubnet fill:#e1f5fe
    classDef privateSubnet fill:#f3e5f5
    classDef blueEnv fill:#e8f5e8
    classDef greenEnv fill:#fff3e0
    classDef codeDeploy fill:#ffebee
    
    class PubSub1,PubSub2 publicSubnet
    class PrivSub1,PrivSub2 privateSubnet
    class BlueEnv,BlueTask1 blueEnv
    class GreenEnv,GreenTask1 greenEnv
    class CodeDeploy codeDeploy
```

### デプロイフロー
```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub Actions
    participant ECR as ECR Repository
    participant CD as CodeDeploy
    participant ALB as Application Load Balancer
    participant Blue as Blue Environment
    participant Green as Green Environment
    
    Dev->>GH: Push new code
    GH->>ECR: Build & Push new image
    GH->>CD: Trigger deployment
    
    CD->>Green: Create new task definition
    CD->>Green: Start Green environment
    Green->>ECR: Pull new image
    
    CD->>Green: Health check
    Green-->>CD: Healthy
    
    CD->>ALB: Switch traffic to Green
    ALB->>Green: Route 100% traffic
    
    CD->>Blue: Terminate Blue environment
    
    Note over CD: Deployment Complete
```

## ネットワーク設計

### VPC構成
- **CIDR**: 10.0.0.0/16
- **DNS解決**: 有効
- **DNSホスト名**: 有効

### サブネット設計
| サブネット | CIDR | AZ | 用途 |
|-----------|------|----|----- |
| Public Subnet 1 | 10.0.1.0/24 | ap-northeast-1a | ALB, NAT Gateway |
| Public Subnet 2 | 10.0.2.0/24 | ap-northeast-1c | ALB |
| Private Subnet 1 | 10.0.11.0/24 | ap-northeast-1a | ECS Tasks |
| Private Subnet 2 | 10.0.12.0/24 | ap-northeast-1c | ECS Tasks |

### ルーティング
- **Public Subnets**: Internet Gateway経由でインターネットアクセス
- **Private Subnets**: NAT Gateway経由でアウトバウンドのみ

## セキュリティ設計

### セキュリティグループ
| 名前 | 方向 | プロトコル | ポート | ソース/宛先 | 用途 |
|------|------|-----------|--------|-------------|------|
| ALB-SG | Inbound | TCP | 80 | 0.0.0.0/0 | インターネットからのHTTPアクセス |
| ECS-SG | Inbound | TCP | 80 | ALB-SG | ALBからコンテナへのアクセス |

### IAMロール
| ロール名 | 用途 | 権限 |
|----------|------|------|
| TaskExecutionRole | ECSタスク実行 | ECRアクセス、CloudWatch Logs書き込み |
| CodeDeployServiceRole | CodeDeploy実行 | ECSサービス制御、ALB制御 |
| GitHubActionsRole | CI/CD | ECR、ECS、CodeDeploy操作 |

## コンピューティングリソース

### ECS設定
- **起動タイプ**: Fargate
- **CPU**: 256 (0.25 vCPU)
- **メモリ**: 512 MB
- **タスク数**: 2 (冗長構成)
- **ネットワークモード**: awsvpc

### ロードバランサー設定
- **タイプ**: Application Load Balancer
- **スキーム**: internet-facing
- **ヘルスチェック**: HTTP GET /
- **ヘルスチェック間隔**: 30秒

## 監視・ログ

### CloudWatch Logs
- **ロググループ**: `/ecs/ecs-bg-deploy`
- **保持期間**: 7日間
- **ログドライバー**: awslogs

### メトリクス
- ECSサービスメトリクス（CPU使用率、メモリ使用率）
- ALBメトリクス（リクエスト数、レスポンス時間）
- ターゲットグループヘルスチェック

## Blue/Greenデプロイメント

### CodeDeploy設定
- **デプロイ設定**: CodeDeployDefault.ECSAllAtOnceBlueGreen
- **トラフィック制御**: ALBリスナールール切り替え
- **ロールバック**: 自動（失敗時、アラーム時）
- **Blue環境終了**: 成功後5分

### デプロイフロー
1. **新しいタスク定義作成**: Green環境用の新しいタスク定義を作成
2. **Green環境起動**: 新しいバージョンでタスクを起動
3. **ヘルスチェック**: Green環境の正常性を確認
4. **トラフィック切り替え**: ALBのトラフィックをGreenに切り替え
5. **Blue環境終了**: 旧バージョン（Blue）を終了

## 拡張性・可用性

### 高可用性
- マルチAZ構成（2つのAZ）
- 複数タスクでの冗長化
- ALBによる自動フェイルオーバー

### スケーラビリティ
- ECS Service Auto Scaling（将来拡張）
- ALBによる負荷分散
- Fargateによる自動リソース管理

## コスト最適化

### リソース最適化
- Fargateによる従量課金
- 最小限のCPU/メモリ設定
- CloudWatch Logs短期保持
- NAT Gateway単一AZ配置

### 推定月額コスト（東京リージョン）
- Fargate: 約$15-20（2タスク常時稼働）
- ALB: 約$20-25
- NAT Gateway: 約$45
- その他（ECR、CloudWatch）: 約$5
- **合計**: 約$85-95/月