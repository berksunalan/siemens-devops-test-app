data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../src/"
  output_path = "${path.module}/lambda_payload.zip"
}

resource "aws_lambda_function" "app_review_lambda" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "${var.project_name}-submit-review"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 10
  memory_size = 128

  environment {
    variables = {
      DYNAMODB_TABLE_NAME       = aws_dynamodb_table.app_reviews.name
      TOKEN_VALIDATION_ENDPOINT = var.token_validation_endpoint
      LOG_LEVEL                 = "DEBUG"
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_logging_attach]

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Environment = "production"
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.app_review_lambda.function_name}"
  retention_in_days = 14

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Environment = "production"
  }
} 