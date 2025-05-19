# API Gateway v1 (REST API)
resource "aws_api_gateway_rest_api" "app_review_api" {
  name        = "${var.project_name}-AppReviewAPI"
  description = "API for submitting app reviews."

  endpoint_configuration {
    types = ["EDGE"] # Edge-optimized for better global performance
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Environment = "production"
  }
}

# API Key
resource "aws_api_gateway_api_key" "api_key" {
  name = "${var.project_name}-api-key"
  enabled = true
  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Environment = "production"
  }
}

# Usage Plan
resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.project_name}-usage-plan"
  
  api_stages {
    api_id = aws_api_gateway_rest_api.app_review_api.id
    stage  = aws_api_gateway_stage.api_stage.stage_name
  }

  quota_settings {
    limit  = 10000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Environment = "production"
  }
}

# Usage Plan Key
resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  key_id        = aws_api_gateway_api_key.api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
}

# Resource for the API (e.g., /reviews)
resource "aws_api_gateway_resource" "reviews_resource" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  parent_id   = aws_api_gateway_rest_api.app_review_api.root_resource_id
  path_part   = "reviews" # API will be accessible at /reviews
}

# POST method for the /reviews resource
resource "aws_api_gateway_method" "post_review_method" {
  rest_api_id   = aws_api_gateway_rest_api.app_review_api.id
  resource_id   = aws_api_gateway_resource.reviews_resource.id
  http_method   = "POST"
  authorization = "NONE" # Authentication will be handled in Lambda
}

# Integration with Lambda function
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.post_review_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY" # For Lambda proxy integration
  uri                     = aws_lambda_function.app_review_lambda.invoke_arn
}

# Deployment of the API
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id

  # Triggers new deployment on API changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.reviews_resource.id,
      aws_api_gateway_method.post_review_method.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_method.options_method # Ensure OPTIONS is set up before deployment
  ]
}

# Stage for the deployment (e.g., v1)
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.app_review_api.id
  stage_name    = "v1"

  # Enable CloudWatch logging for API Gateway
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format          = jsonencode({
      requestId               = "$context.requestId"
      ip                      = "$context.identity.sourceIp"
      caller                  = "$context.identity.caller"
      user                    = "$context.identity.user"
      requestTime             = "$context.requestTime"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      status                  = "$context.status"
      protocol                = "$context.protocol"
      responseLength          = "$context.responseLength"
      extendedRequestId       = "$context.extendedRequestId"
      path                    = "$context.path"
      authorizerPrincipalId   = "$context.authorizer.principalId"
      integrationErrorMessage = "$context.integrationErrorMessage"
      error_message           = "$context.error.message"
      error_responseType      = "$context.error.responseType"
    })
  }

  variables = {
    lambdaFunctionName = aws_lambda_function.app_review_lambda.function_name
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# CloudWatch Log Group for API Gateway access logs
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "API-Gateway-Access-Logs_${aws_api_gateway_rest_api.app_review_api.name}_${aws_api_gateway_stage.api_stage.stage_name}"
  retention_in_days = 7

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# Lambda permission for API Gateway to invoke the function
resource "aws_lambda_permission" "api_gateway_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app_review_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # Restrict to the specific API Gateway ARN
  source_arn = "${aws_api_gateway_rest_api.app_review_api.execution_arn}/*/*/*"
}

# Custom Domain Name for API Gateway
resource "aws_api_gateway_domain_name" "custom_domain" {
  domain_name              = var.api_domain_name
  regional_certificate_arn = var.acm_certificate_arn_us_east_1 # For EDGE optimized, cert must be in us-east-1
  # certificate_arn = var.acm_certificate_arn # Use this if using REGIONAL endpoint and cert is in the same region

  endpoint_configuration {
    types = ["EDGE"]
  }

  security_policy = "TLS_1_2"

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# Base Path Mapping for Custom Domain
resource "aws_api_gateway_base_path_mapping" "api_mapping" {
  domain_name = aws_api_gateway_domain_name.custom_domain.domain_name
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  stage_name  = aws_api_gateway_stage.api_stage.stage_name
  # base_path = "myapp" # Optional: if you want the API to be under a specific path like api.testdevops.com/myapp
}

# Route 53 record for the custom domain
data "aws_route53_zone" "selected_zone" {
  name         = var.hosted_zone_name
  private_zone = false
}

resource "aws_route53_record" "api_dns_record" {
  zone_id = data.aws_route53_zone.selected_zone.zone_id
  name    = aws_api_gateway_domain_name.custom_domain.domain_name
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.custom_domain.cloudfront_domain_name
    zone_id                = aws_api_gateway_domain_name.custom_domain.cloudfront_zone_id
    evaluate_target_health = true
  }
}

# CORS Configuration: OPTIONS method
resource "aws_api_gateway_method" "options_method" {
  rest_api_id   = aws_api_gateway_rest_api.app_review_api.id
  resource_id   = aws_api_gateway_resource.reviews_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  depends_on = [aws_api_gateway_method.options_method]
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.allowed_origin_pattern}'"
  }
  response_templates = {
    "application/json" = ""
  }
  depends_on = [aws_api_gateway_method_response.options_200]
}

# Add CORS headers for POST method responses as well
resource "aws_api_gateway_method_response" "post_200" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.post_review_method.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty" # Or a specific model if you define one
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# This resource is needed to ensure the method response for POST has the CORS header
resource "aws_api_gateway_integration_response" "post_integration_response_200" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.post_review_method.http_method
  status_code = aws_api_gateway_method_response.post_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'${var.allowed_origin_pattern}'"
  }

  # If you expect different status codes from Lambda (e.g., 400, 500) and want to map them with CORS headers,
  # you would add more aws_api_gateway_integration_response blocks and corresponding aws_api_gateway_method_response blocks.
  depends_on = [aws_api_gateway_integration.lambda_integration]
}

# Error Response Configurations
resource "aws_api_gateway_method_response" "post_400" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.post_review_method.http_method
  status_code = "400"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_method_response" "post_401" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.post_review_method.http_method
  status_code = "401"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_method_response" "post_403" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.post_review_method.http_method
  status_code = "403"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_method_response" "post_500" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.post_review_method.http_method
  status_code = "500"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Integration Responses for Error Codes
resource "aws_api_gateway_integration_response" "post_integration_response_400" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.post_review_method.http_method
  status_code = aws_api_gateway_method_response.post_400.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'${var.allowed_origin_pattern}'"
  }
  depends_on = [aws_api_gateway_integration.lambda_integration]
}

resource "aws_api_gateway_integration_response" "post_integration_response_401" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.post_review_method.http_method
  status_code = aws_api_gateway_method_response.post_401.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'${var.allowed_origin_pattern}'"
  }
  depends_on = [aws_api_gateway_integration.lambda_integration]
}

resource "aws_api_gateway_integration_response" "post_integration_response_403" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.post_review_method.http_method
  status_code = aws_api_gateway_method_response.post_403.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'${var.allowed_origin_pattern}'"
  }
  depends_on = [aws_api_gateway_integration.lambda_integration]
}

resource "aws_api_gateway_integration_response" "post_integration_response_500" {
  rest_api_id = aws_api_gateway_rest_api.app_review_api.id
  resource_id = aws_api_gateway_resource.reviews_resource.id
  http_method = aws_api_gateway_method.post_review_method.http_method
  status_code = aws_api_gateway_method_response.post_500.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'${var.allowed_origin_pattern}'"
  }
  depends_on = [aws_api_gateway_integration.lambda_integration]
} 