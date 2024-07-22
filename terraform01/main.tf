terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-south-1"
  access_key = "*****************"
  secret_key = "**************************"
}

# Create DynamoDB table
resource "aws_dynamodb_table" "resume_table" {
  name             = "Ter_resume_table"
  hash_key         = "id"
  billing_mode     = "PAY_PER_REQUEST"

  attribute {
    name = "id"
    type = "S"
  }
}

# Read data.json content and create DynamoDB item content
locals {
  data_content = file("/home/ubuntu/terraform/source.json")
}

# Add item/content to the DynamoDB table using item id from local block
resource "aws_dynamodb_table_item" "resume_json" {
  table_name = aws_dynamodb_table.resume_table.name
  hash_key   = "id"

  item = local.data_content

  depends_on = [aws_dynamodb_table.resume_table]
}

# Create Lambda function with Python runtime
resource "aws_lambda_function" "test_lambda" {
  filename      = "/home/ubuntu/terraform/lambda_function.zip"
  function_name = "Ter_Lambda_001"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "app.lambda_handler"

  source_code_hash = filebase64sha256("/home/ubuntu/terraform/lambda_function.zip")

  runtime = "python3.9"
}

# Create IAM role for Lambda
resource "aws_iam_role" "iam_for_lambda" {
  name = "Ter_resume_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach AWSLambdaBasicExecutionRole policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role      = aws_iam_role.iam_for_lambda.name
}

# Attach AmazonS3FullAccess policy to Lambda role
resource "aws_iam_role_policy_attachment" "s3_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role      = aws_iam_role.iam_for_lambda.name
}

# Create DynamoDB read policy and attach to Lambda role
resource "aws_iam_role_policy" "dynamodb_read_policy" {
  name   = "dynamodb_read_policy"
  role   = aws_iam_role.iam_for_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "dynamodb:GetItem",
        "dynamodb:Scan",
      ]
      Resource = aws_dynamodb_table.resume_table.arn
    }]
  })
}

# Create S3 bucket
resource "aws_s3_bucket" "resume_bucket" {
  bucket = "ter-bucket-01"
}

# Allow public access to the bucket
resource "aws_s3_bucket_public_access_block" "resume_public_access" {
  bucket = aws_s3_bucket.resume_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Enable static website hosting
resource "aws_s3_bucket_website_configuration" "resume_website" {
  bucket = aws_s3_bucket.resume_bucket.id

  index_document {
    suffix = "index.html"
  }
}

# Create Bucket policy to allow public access to index.html and restrict statefile access
resource "aws_s3_bucket_policy" "resume_bucket_policy" {
  bucket = aws_s3_bucket.resume_bucket.id

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "allow public access to the bucket objects",
        "Principal": "*",
        "Effect": "Allow",
        "Action": [
          "s3:GetObject"
        ],
        "Resource": [
          "${aws_s3_bucket.resume_bucket.arn}/*"
        ]
      },
      {
        "Sid": "RestrictStateFileAccess",
        "Effect": "Deny",
        "Principal": "*",
        "Action": "s3:*",
        "Resource": "${aws_s3_bucket.resume_bucket.arn}/terraform.tfstate"
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.resume_public_access
  ]
}

# Upload index.html to S3
resource "aws_s3_object" "index_html" {
  bucket = aws_s3_bucket.resume_bucket.id
  key    = "index.html"
  source = "/home/ubuntu/terraform/index.html"

  depends_on = [
    aws_s3_bucket.resume_bucket,
    aws_s3_bucket_public_access_block.resume_public_access,
    aws_s3_bucket_policy.resume_bucket_policy
  ]
}
# Upload source.json to S3
resource "aws_s3_object" "source_json" {
  bucket = aws_s3_bucket.resume_bucket.id
  key    = "source.json"
  source = "/home/ubuntu/terraform/source.json"

  depends_on = [
    aws_s3_bucket.resume_bucket,
    aws_s3_bucket_public_access_block.resume_public_access,
    aws_s3_bucket_policy.resume_bucket_policy
  ]
}
# Create S3 event notification for Lambda
resource "aws_s3_bucket_notification" "resume_bucket_notification" {
  bucket = aws_s3_bucket.resume_bucket.id

  lambda_function {
    events = ["s3:ObjectCreated:*"]
    lambda_function_arn = aws_lambda_function.test_lambda.arn
  }

  depends_on = [
    aws_lambda_permission.s3
  ]
}

# Allow S3 to invoke Lambda function
resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda.function_name
  principal     = "s3.amazonaws.com"

  source_arn = aws_s3_bucket.resume_bucket.arn
}
