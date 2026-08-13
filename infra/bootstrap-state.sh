#!/usr/bin/env bash
# One-time bootstrap: create the S3 state bucket + DynamoDB lock table, then
# write backend.tfvars. Requires the AWS CLI and valid credentials.
#
#   ./bootstrap-state.sh
#   terraform init -backend-config=backend.tfvars
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
BUCKET="linkify-mini-paas-tfstate-$(date +%s)" # S3 bucket names are globally unique
TABLE="linkify-mini-paas-tfstate-lock"

echo ">> creating state bucket ${BUCKET} in ${REGION}"
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" >/dev/null

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo ">> creating lock table ${TABLE}"
aws dynamodb create-table \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" >/dev/null

cat > backend.tfvars <<EOF
bucket         = "$BUCKET"
key            = "infra/terraform.tfstate"
region         = "$REGION"
dynamodb_table = "$TABLE"
encrypt        = true
EOF

echo
echo "backend.tfvars written. Next steps:"
echo "  cd infra"
echo "  terraform init -backend-config=backend.tfvars"
echo "  terraform plan"
