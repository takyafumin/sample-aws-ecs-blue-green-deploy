#!/bin/bash

set -e

PROJECT_NAME="ecs-bg-deploy"
REGION="ap-northeast-1"

# 引数チェック
if [ $# -ne 1 ]; then
    echo "使用方法: $0 <IMAGE_TAG>"
    echo "例: $0 v2.0.0"
    exit 1
fi

IMAGE_TAG=$1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Blue/Greenデプロイメント開始 ==="
echo "イメージタグ: $IMAGE_TAG"

# 新しいタスク定義を登録
echo "新しいタスク定義を登録中..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --family ${PROJECT_NAME}-task \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 256 \
  --memory 512 \
  --execution-role-arn $(aws iam list-roles --query "Roles[?contains(RoleName, '${PROJECT_NAME}') && contains(RoleName, 'TaskExecutionRole')].Arn" --output text) \
  --container-definitions "[{
    \"name\": \"app\",
    \"image\": \"${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${PROJECT_NAME}-app:${IMAGE_TAG}\",
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

# CodeDeployでデプロイ実行
echo "CodeDeployでデプロイ実行中..."
DEPLOYMENT_ID=$(aws deploy create-deployment \
  --application-name ${PROJECT_NAME}-app \
  --deployment-group-name ${PROJECT_NAME}-dg \
  --revision revisionType=AppSpecContent,appSpecContent="{
    \"version\": 0.0,
    \"Resources\": [{
      \"TargetService\": {
        \"Type\": \"AWS::ECS::Service\",
        \"Properties\": {
          \"TaskDefinition\": \"${TASK_DEF_ARN}\",
          \"LoadBalancerInfo\": {
            \"ContainerName\": \"app\",
            \"ContainerPort\": 80
          }
        }
      }
    }]
  }" \
  --query 'deploymentId' --output text)

echo "デプロイメントID: $DEPLOYMENT_ID"
echo "デプロイメント状況を監視中..."

# デプロイメント完了まで待機
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

echo "デプロイメント完了"