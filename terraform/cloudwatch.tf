# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

# CloudWatch Alarms for Lambda
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period             = "300"
  statistic          = "Sum"
  threshold          = "0"
  alarm_description  = "Lambda function errors"
  alarm_actions      = [aws_sns_topic.alerts.arn]
  dimensions = {
    FunctionName = aws_lambda_function.app_review_lambda.function_name
  }
  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# CloudWatch Alarms for API Gateway
resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name          = "${var.project_name}-api-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period             = "300"
  statistic          = "Sum"
  threshold          = "0"
  alarm_description  = "API Gateway 5XX errors"
  alarm_actions      = [aws_sns_topic.alerts.arn]
  dimensions = {
    ApiName = aws_api_gateway_rest_api.app_review_api.name
    Stage   = aws_api_gateway_stage.api_stage.stage_name
  }
  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# CloudWatch Alarms for DynamoDB
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "${var.project_name}-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period             = "300"
  statistic          = "Sum"
  threshold          = "0"
  alarm_description  = "DynamoDB throttled requests"
  alarm_actions      = [aws_sns_topic.alerts.arn]
  dimensions = {
    TableName = aws_dynamodb_table.app_reviews.name
  }
  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
} 