#!/bin/bash

# Stop script on any error
set -e

REPO_URL="${repo_url}"
JAVA_VERSION="${java_version}"
REPO_DIR_NAME="${repo_dir_name}"
STOP_INSTANCE="${stop_after_minutes}"
SECRET_NAME="github/pat/my-private-repo-token" # Ensure this matches your GitHub Actions secret name
CLONE_URL=$(echo "${REPO_URL}" | sed "s/https:\/\//https:\/\/${GITHUB_PAT}@/")


echo "Attempting to retrieve GitHub PAT from AWS Secrets Manager: ${SECRET_NAME} in region ${AWS_REGION_FOR_SCRIPT}..."
GITHUB_PAT=$(aws secretsmanager get-secret-value \
    --secret-id "${SECRET_NAME}" \
    --query SecretString \
    --output text \
    --region "${AWS_REGION_FOR_SCRIPT}")

# Check if the PAT was retrieved successfully
if [ -z "$GITHUB_PAT" ]; then
  echo "Error: Failed to retrieve GitHub PAT from Secrets Manager. Exiting."
  echo "Possible issues: incorrect secret name, invalid AWS region, or EC2 instance IAM role lacks 'secretsmanager:GetSecretValue' permissions for this secret."
  exit 1
fi
echo "GitHub PAT successfully retrieved."

git clone "${CLONE_URL}"
sudo apt update  
sudo apt install "$JAVA_VERSION" -y
apt install maven -y
cd "$REPO_DIR_NAME"
mvn spring-boot:run &

aws s3 cp /var/log/cloud-init-output.log s3://"${s3_bucket_name}"/app/logs/cloud-init-output-$(hostname)-$(date +%Y%m%d%H%M%S).log
sudo shutdown -h +"$STOP_INSTANCE"  
