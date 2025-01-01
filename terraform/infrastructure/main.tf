provider "aws" {
  region = var.aws_region
}

# Create a remote backend for your terraform
terraform {
  backend "s3" {
    bucket = "austinobioma-backend-bkt"
    dynamodb_table = "austin-locks"
    key    = "LockID"
    region = "us-east-1"
  }
}

# S3 Bucket for datasets
resource "aws_s3_bucket" "datasets" {
  bucket = "austinobioma-datasets"
  acl    = "private"

  tags = {
    Name = "Dataset Bucket"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      tags,
      acl
    ]
  }
}

# IAM Role for Lambda execution
resource "aws_iam_role" "lambda_exec" {
  name               = "lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "Lambda Execution Role"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      tags
    ]
  }
}

# Attach the basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_execution_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_exec_policy" {
  name   = "lambda-exec-policy"
  role   = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject"
        ],
        Resource = [
          "arn:aws:s3:::austinobioma-datasets",
          "arn:aws:s3:::austinobioma-datasets/*"
        ]
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "merge_function" {
  filename         = "lambda_function.zip"
  function_name    = "merge-homeless-data"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.8"
  source_code_hash = filebase64sha256("lambda_function.zip")
  timeout      = 900
  memory_size  = 512
  # Add the AWS Data Wrangler Layer
  layers = [
    "arn:aws:lambda:us-east-1:336392948345:layer:AWSSDKPandas-Python38:27"
  ]

  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.datasets.bucket
    }
  }
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = var.api_gateway_name
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 3600
  }
}

# API Gateway Lambda Integration
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.merge_function.invoke_arn
  payload_format_version = "2.0"
}

# API Gateway Route
resource "aws_apigatewayv2_route" "http_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /data"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# API Gateway Deployment
resource "aws_apigatewayv2_stage" "http_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "default"
  auto_deploy = true
}

# Lambda Permission to Allow API Gateway Invocation
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.merge_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# Iterate over all CSV files in the files directory and upload them
resource "aws_s3_object" "csv_files" {
  for_each = fileset("${path.module}/../../files", "*.csv") # Path to the local directory containing CSV files
  bucket   = aws_s3_bucket.datasets.bucket
  key      = each.value
  source   = "${path.module}/../../files/${each.value}"

  tags = {
    UploadedBy = "Terraform"
  }
}

