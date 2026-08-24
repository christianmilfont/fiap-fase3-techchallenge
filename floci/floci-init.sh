#!/bin/bash
set -e

echo ">>> SQS: togglemaster-queue"
aws --endpoint-url http://localhost:4566 \
    --region us-east-1 \
    --no-sign-request \
    sqs create-queue --queue-name togglemaster-queue

echo ">>> DynamoDB: ToggleMasterAnalytics"
aws --endpoint-url http://localhost:4566 \
    --region us-east-1 \
    --no-sign-request \
    dynamodb create-table \
    --table-name ToggleMasterAnalytics \
    --attribute-definitions AttributeName=event_id,AttributeType=S \
    --key-schema AttributeName=event_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST

echo ">>> ElastiCache: togglemaster-redis (valkey na 6379)"
aws --endpoint-url http://localhost:4566 \
    --region us-east-1 \
    --no-sign-request \
    elasticache create-replication-group \
    --replication-group-id togglemaster-redis \
    --replication-group-description "ToggleMaster Redis" \
    --cache-node-type cache.t3.micro \
    --engine redis \
    --num-cache-clusters 1

echo ">>> RDS: auth-db (7001), flag-db (7002), targeting-db (7003)"
for DB in auth-db flag-db targeting-db; do
  aws --endpoint-url http://localhost:4566 \
      --region us-east-1 \
      --no-sign-request \
      rds create-db-instance \
      --db-instance-identifier "$DB" \
      --db-instance-class db.t3.micro \
      --engine postgres \
      --master-username postgres \
      --master-user-password postgres \
      --allocated-storage 20
done

echo ">>> Confirmar portas RDS (esperado: auth-db=7001, flag-db=7002, targeting-db=7003)"
aws --endpoint-url http://localhost:4566 \
    --region us-east-1 \
    --no-sign-request \
    rds describe-db-instances \
    --query 'DBInstances[*].[DBInstanceIdentifier,Endpoint.Port]'

echo ">>> ECR: 5 repositórios"
for SVC in auth-service flag-service targeting-service evaluation-service analytics-service; do
  aws --endpoint-url http://localhost:4566 \
      --region us-east-1 \
      --no-sign-request \
      ecr create-repository --repository-name "togglemaster/$SVC"
done

echo ">>> docker login ECR"
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 \
aws ecr get-login-password --endpoint-url http://localhost:4566 | \
  docker login --username AWS --password-stdin localhost:5100

echo ">>> floci-init: pronto."
