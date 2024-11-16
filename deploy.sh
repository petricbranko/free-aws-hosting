#!/bin/bash

# Set variables
DOMAIN_NAME="example.com" # Replace with your domain
BUCKET_NAME="www.$DOMAIN_NAME" # S3 bucket name for your site content
CERTIFICATE_REGION="us-east-1" # ACM certificates for CloudFront must be in us-east-1

# Check if AWS CLI is installed
if ! [ -x "$(command -v aws)" ]; then
  echo "Error: AWS CLI is not installed." >&2
  exit 1
fi

# Create the S3 bucket
echo "Creating S3 bucket for website..."
aws s3api create-bucket --bucket "$BUCKET_NAME" --region us-east-1 --create-bucket-configuration LocationConstraint=us-east-1
aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Effect\": \"Allow\",
      \"Principal\": \"*\",
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::$BUCKET_NAME/*\"
    }
  ]
}"
aws s3 website s3://"$BUCKET_NAME" --index-document index.html --error-document error.html
echo "S3 bucket created and configured."

# Upload website content to S3
echo "Uploading website content to S3..."
aws s3 sync ./website s3://"$BUCKET_NAME" # Assumes a "website" folder in the current directory

# Request SSL certificate
echo "Requesting SSL certificate..."
CERT_ARN=$(aws acm request-certificate --domain-name "$DOMAIN_NAME" --validation-method DNS --region "$CERTIFICATE_REGION" \
  --query CertificateArn --output text)
echo "SSL certificate requested: $CERT_ARN"

# Wait for the user to validate the certificate using DNS
echo "Please validate the SSL certificate using the DNS records provided in AWS ACM."
echo "Visit the ACM console to get the DNS validation details: https://console.aws.amazon.com/acm/home?region=$CERTIFICATE_REGION#/certificates/"
read -p "Press Enter after validating the DNS record..."

# Create CloudFront distribution
echo "Creating CloudFront distribution..."
DISTRIBUTION_ID=$(aws cloudfront create-distribution --origin-domain-name "$BUCKET_NAME.s3.amazonaws.com" \
  --default-root-object index.html \
  --query 'Distribution.Id' --output text \
  --distribution-config "{
    \"CallerReference\": \"$DOMAIN_NAME-$(date +%s)\",
    \"Aliases\": {
      \"Quantity\": 1,
      \"Items\": [\"$DOMAIN_NAME\"]
    },
    \"Origins\": {
      \"Quantity\": 1,
      \"Items\": [
        {
          \"Id\": \"S3-$BUCKET_NAME\",
          \"DomainName\": \"$BUCKET_NAME.s3.amazonaws.com\",
          \"OriginPath\": \"\",
          \"CustomHeaders\": {\"Quantity\": 0},
          \"S3OriginConfig\": {
            \"OriginAccessIdentity\": \"\"
          }
        }
      ]
    },
    \"DefaultCacheBehavior\": {
      \"TargetOriginId\": \"S3-$BUCKET_NAME\",
      \"ViewerProtocolPolicy\": \"redirect-to-https\",
      \"AllowedMethods\": {
        \"Quantity\": 2,
        \"Items\": [\"GET\", \"HEAD\"],
        \"CachedMethods\": {
          \"Quantity\": 2,
          \"Items\": [\"GET\", \"HEAD\"]
        }
      },
      \"Compress\": true,
      \"DefaultTTL\": 86400,
      \"MaxTTL\": 31536000,
      \"MinTTL\": 0
    },
    \"ViewerCertificate\": {
      \"ACMCertificateArn\": \"$CERT_ARN\",
      \"SSLSupportMethod\": \"sni-only\",
      \"MinimumProtocolVersion\": \"TLSv1.2_2021\"
    },
    \"Enabled\": true
  }")
echo "CloudFront distribution created with ID: $DISTRIBUTION_ID"

# Output instructions for DNS configuration
echo "Update your DNS settings to point your domain to the CloudFront distribution."
echo "CloudFront Domain Name: $(aws cloudfront get-distribution --id $DISTRIBUTION_ID --query 'Distribution.DomainName' --output text)"
