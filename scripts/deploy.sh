#!/bin/bash
# Blue/Green デプロイメントスクリプト（既存イメージ使用）
# 使用方法: ./scripts/deploy.sh <VERSION>

set -e

PROJECT_NAME="ecs-bg-deploy"
REGION="ap-northeast-1"

if [ $# -ne 1 ]; then
    echo "使用方法: $0 <VERSION>"
    echo "例: $0 v2.0.0"
    exit 1
fi

VERSION=$1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${PROJECT_NAME}-app"

echo "=== Blue/Greenデプロイメント開始 ==="
echo "バージョン: $VERSION"
echo "イメージ: ${ECR_URI}:${VERSION}"

# 1. 新しいタスク定義を登録
echo "1. 新しいタスク定義を登録中..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --family ${PROJECT_NAME}-task \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 256 \
  --memory 512 \
  --execution-role-arn $(aws iam list-roles --query "Roles[?contains(RoleName, '${PROJECT_NAME}') && contains(RoleName, 'TaskExecutionRole')].Arn" --output text) \
  --container-definitions "[{
    \"name\": \"app\",
    \"image\": \"${ECR_URI}:${VERSION}\",
    \"portMappings\": [{\"containerPort\": 80}],
    \"logConfiguration\": {
      \"logDriver\": \"awslogs\",
      \"options\": {
        \"awslogs-group\": \"/ecs/${PROJECT_NAME}\",
        \"awslogs-region\": \"${REGION}\",
        \"awslogs-stream-prefix\": \"ecs\"
      }
    }
  }]" \
  --query 'taskDefinition.taskDefinitionArn' --output text)

echo "タスク定義ARN: $TASK_DEF_ARN"

# 2. CodeDeployでデプロイ実行
echo "2. CodeDeployでデプロイ実行中..."
APPSPEC_CONTENT=$(jq -n -r --arg taskDef "$TASK_DEF_ARN" '{
  "version": 0.0,
  "Resources": [{
    "TargetService": {
      "Type": "AWS::ECS::Service",
      "Properties": {
        "TaskDefinition": $taskDef,
        "LoadBalancerInfo": {
          "ContainerName": "app",
          "ContainerPort": 80
        }
      }
    }
  }]
}' | jq -c . | sed 's/"/\\"/g')

DEPLOYMENT_ID=$(aws deploy create-deployment \
  --application-name ${PROJECT_NAME}-app \
  --deployment-group-name ${PROJECT_NAME}-dg \
  --revision "revisionType=AppSpecContent,appSpecContent={content=\"$APPSPEC_CONTENT\"}" \
  --query 'deploymentId' --output text)

echo "デプロイメントID: $DEPLOYMENT_ID"
echo "デプロイメント状況を監視中..."

# 3. デプロイメント完了まで待機
while true; do
    STATUS=$(aws deploy get-deployment --deployment-id $DEPLOYMENT_ID --query 'deploymentInfo.status' --output text)
    echo "現在のステータス: $STATUS"
    
    if [ "$STATUS" = "Succeeded" ]; then
        echo "=== デプロイメント成功 ==="
        break
    elif [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Stopped" ]; then
        echo "=== デプロイメント失敗 ==="
        exit 1
    fi
    
    sleep 30
done

# 4. 検証
ALB_DNS=$(aws elbv2 describe-load-balancers --names ${PROJECT_NAME}-alb --query 'LoadBalancers[0].DNSName' --output text)
echo "エンドポイント: http://$ALB_DNS"
echo "デプロイメント完了: $VERSION"