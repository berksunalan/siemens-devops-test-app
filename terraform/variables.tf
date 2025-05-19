variable "aws_region" {
  description = "AWS region for deployment. Frankfurt is eu-central-1."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "A unique name for the project to prefix resources."
  type        = string
  default     = "appReviewApi"
}

variable "api_domain_name" {
  description = "The custom domain name for the API Gateway (e.g., api.testdevops.com)."
  type        = string
  default     = "api.testdevops.com"
}

variable "hosted_zone_name" {
  description = "The Route 53 hosted zone name (e.g., testdevops.com)."
  type        = string
  default     = "testdevops.com"
}

variable "acm_certificate_arn_us_east_1" {
  description = "ARN of the ACM certificate in us-east-1 for API Gateway EDGE custom domain (must cover the api_domain_name). This is required in us-east-1 even if deploying to other regions."
  type        = string
  # This needs to be created manually or by a separate Terraform stack and the ARN provided here.
  # Example: arn:aws:acm:us-east-1:123456789012:certificate/your-certificate-id
}

variable "token_validation_endpoint" {
  description = "Endpoint URL for validating access tokens."
  type        = string
  sensitive   = true
}

variable "allowed_origin_pattern" {
  description = "CORS allowed origin pattern. e.g., https://*.testdevops.com"
  type        = string
  default     = "https://*.testdevops.com"
} 