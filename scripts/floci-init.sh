#!/bin/bash
set -e

aws --endpoint-url http://localhost:4566 \
    --region us-east-1 \
    --no-sign-request \
    sqs create-queue --queue-name togglemaster-queue

aws --endpoint-url http://localhost:4566 \
    --region us-east-1 \
    --no-sign-request \
    dynamodb create-table \
    --table-name ToggleMasterAnalytics \
    --attribute-definitions AttributeName=event_id,AttributeType=S \
    --key-schema AttributeName=event_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST