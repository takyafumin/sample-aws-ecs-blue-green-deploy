#!/bin/bash
# Blue/Greenデプロイ統合テスト
# 使用方法: ./test/test-deploy.sh

set -e

PROJECT_NAME="ecs-bg-deploy"
TEST_VERSION="test-$(date +%s)"

echo "=== Blue/Greenデプロイ統合テスト ==="
echo "テストバージョン: $TEST_VERSION"

# 1. 事前検証
echo "1. 事前検証実行"
./test/verify.sh

# 2. デプロイ前の状態記録
echo "2. デプロイ前状態記録"
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names ${PROJECT_NAME}-alb \
  --query 'LoadBalancers[0].DNSName' --output text)

BEFORE_RESPONSE=$(curl -s http://$ALB_DNS | grep -o "Version: [^<]*" || echo "Version: unknown")
echo "デプロイ前バージョン: $BEFORE_RESPONSE"

# 3. テスト用イメージ作成
echo "3. テスト用イメージ作成"
# index.htmlを一時的に変更
cp index.html index.html.bak
sed -i.tmp "s/Version: [^<]*/Version: $TEST_VERSION/" index.html

# 4. ビルド・デプロイ実行
echo "4. ビルド・デプロイ実行"
./scripts/dev-deploy.sh $TEST_VERSION

# 5. デプロイ後検証
echo "5. デプロイ後検証"
sleep 10  # ALBの反映待ち

AFTER_RESPONSE=$(curl -s http://$ALB_DNS | grep -o "Version: [^<]*" || echo "Version: unknown")
echo "デプロイ後バージョン: $AFTER_RESPONSE"

# 6. 結果判定
if [[ "$AFTER_RESPONSE" == *"$TEST_VERSION"* ]]; then
    echo "✅ テスト成功: バージョンが正しく更新されました"
    TEST_RESULT="SUCCESS"
else
    echo "❌ テスト失敗: バージョンが更新されていません"
    TEST_RESULT="FAILED"
fi

# 7. クリーンアップ
echo "7. クリーンアップ"
mv index.html.bak index.html
rm -f index.html.tmp

echo ""
echo "=== テスト結果: $TEST_RESULT ==="
echo "テストバージョン: $TEST_VERSION"
echo "エンドポイント: http://$ALB_DNS"

if [ "$TEST_RESULT" = "FAILED" ]; then
    exit 1
fi