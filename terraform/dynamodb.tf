resource "aws_dynamodb_table" "app_reviews" {
  name             = "${var.project_name}-AppReviews"
  billing_mode     = "PAY_PER_REQUEST" // Cost-efficient for unpredictable workloads
  hash_key         = "AppName"         // Partition key
  range_key        = "CreateDate"      // Sort key

  attribute {
    name = "AppName"
    type = "S" // String
  }

  attribute {
    name = "CreateDate"
    type = "S" // String (e.g., ISO 8601 timestamp for sortability)
  }

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption by default (AWS owned CMK)
  # For customer managed CMK, configure server_side_encryption block
  server_side_encryption {
    enabled = true
  }

  tags = {
    Name      = "${var.project_name}-AppReviewsTable"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
} 