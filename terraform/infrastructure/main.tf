provider "aws" {
  region = var.aws_region
}

# S3 Bucket for datasets
resource "aws_s3_bucket" "datasets" {
  bucket = "friday-ugbebor-datasets"
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
          "s3:GetObject",
          "s3:PutObject"
        ],
        Resource = [
          "arn:aws:s3:::friday-ugbebor-datasets/*"
        ]
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

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.datasets.bucket
    }
  }
}

