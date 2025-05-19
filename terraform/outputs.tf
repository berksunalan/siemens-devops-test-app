output "api_endpoint_url" {
  description = "The invoke URL for the API Gateway stage (before custom domain)."
  value       = aws_api_gateway_stage.api_stage.invoke_url
}

output "api_custom_domain_url" {
  description = "The custom domain URL for the API."
  value       = "https://${aws_api_gateway_domain_name.custom_domain.domain_name}/reviews"
}

output "lambda_function_name" {
  description = "The name of the Lambda function."
  value       = aws_lambda_function.app_review_lambda.function_name
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table."
  value       = aws_dynamodb_table.app_reviews.name
}

output "waf_web_acl_arn" {
  description = "The ARN of the WAF WebACL."
  value       = aws_wafv2_web_acl.api_waf.arn
} 