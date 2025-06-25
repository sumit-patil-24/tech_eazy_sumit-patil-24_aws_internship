#!/bin/bash

# Stop script on any error
set -e

JAVA_VERSION="${java_version}"
REPO_DIR_NAME="${repo_dir_name}"
STOP_INSTANCE="${stop_after_minutes}"
S3_BUCKET_NAME="${s3_bucket_name}"
SECRET_NAME="github/pat/my-private-repo-token" # Ensure this matches your GitHub Actions secret name
AWS_REGION_FOR_SCRIPT="${aws_region}"

sudo apt update 
# Check if unzip is installed, and install if not (needed for awscli v2 install)
if ! command -v unzip &> /dev/null; then
  sudo apt install -y unzip
fi
if ! command -v aws &> /dev/null; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
fi
sudo apt install "$JAVA_VERSION" -y
sudo apt install maven -y


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

CLONE_URL=$(echo "${REPO_URL}" | sed "s/https:\/\//https:\/\/${GITHUB_PAT}@/")
git clone "${CLONE_URL}"
# Clean up sensitive token
unset GITHUB_PAT

 
cd "$REPO_DIR_NAME"
chmod +x mvnw

#build artifact
./mvnw clean package

# Run the app
nohup $JAVA_HOME/bin/java -jar target/*.jar > app.log 2>&1 &


# --- Upload cloud-init logs to S3 ---
echo "Uploading cloud-init-output.log to S3 bucket ${S3_BUCKET_NAME}..."
# Give cloud-init a moment to finish writing its logs.
sleep 10
# Upload the log. The '|| true' prevents the script from exiting if upload fails
# (e.g., due to transient S3 issues), allowing the rest of the script to complete.
aws s3 cp /var/log/cloud-init-output.log "s3://${S3_BUCKET_NAME}/app/logs/cloud-init-output-$(hostname)-$(date +%Y%m%d%H%M%S).log" \
    --region "${AWS_REGION_FOR_SCRIPT}" || true # CRITICAL: --region must be here!
echo "Cloud-init log upload attempted."


sudo shutdown -h +"$STOP_INSTANCE"  
