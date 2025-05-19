import json
import os
import logging
import boto3
import requests
from datetime import datetime, timezone
import re

# Configure logging
LOG_LEVEL = os.environ.get("LOG_LEVEL", "DEBUG").upper()
logger = logging.getLogger()
logger.setLevel(LOG_LEVEL)

# Initialize AWS clients (outside the handler for reuse)
dynamodb = boto3.resource("dynamodb")
DYNAMODB_TABLE_NAME = os.environ.get("DYNAMODB_TABLE_NAME")
TOKEN_VALIDATION_ENDPOINT = os.environ.get("TOKEN_VALIDATION_ENDPOINT")

MAX_APP_NAME_LENGTH = 50
MAX_DESCRIPTION_LENGTH = 2000

# Only allow subdomains of testdevops.com
ALLOWED_DOMAIN_REGEX = re.compile(r"^https://([a-zA-Z0-9-]+\.)*testdevops\.com(:\d+)?$")

# Simple malicious pattern detection (expand as needed)
MALICIOUS_PATTERNS = [
    r"<script.*?>.*?</script.*?>",  # XSS
    r"(;|\|\||&&|\$\(|`|\bDROP\b|\bDELETE\b|\bINSERT\b|\bUPDATE\b|\bSELECT\b|\bUNION\b)",  # SQLi/command
    r"\.\./",  # Path traversal
    r"\$\{.*?\}",  # Template injection
    r"\{\$.*?\}",  # NoSQL injection
]
MALICIOUS_REGEXES = [re.compile(pat, re.IGNORECASE) for pat in MALICIOUS_PATTERNS]

def build_response(status_code, body, origin=None):
    headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token",
        "Access-Control-Allow-Methods": "POST,OPTIONS"
    }
    if origin and ALLOWED_DOMAIN_REGEX.match(origin):
        headers["Access-Control-Allow-Origin"] = origin
    else:
        headers["Access-Control-Allow-Origin"] = "https://api.testdevops.com"  # fallback, restrictive
    return {
        "statusCode": status_code,
        "headers": headers,
        "body": json.dumps(body)
    }

def is_malicious(value):
    if not isinstance(value, str):
        return False
    for regex in MALICIOUS_REGEXES:
        if regex.search(value):
            return True
    return False

def validate_token(token):
    if not TOKEN_VALIDATION_ENDPOINT:
        logger.error("Token validation endpoint is not configured.")
        return False
    if not token:
        logger.warning("No token provided for validation.")
        return False
    headers = {"Authorization": token}
    try:
        logger.debug(f"Validating token at endpoint: {TOKEN_VALIDATION_ENDPOINT}")
        response = requests.post(TOKEN_VALIDATION_ENDPOINT, headers=headers, timeout=5)
        if response.status_code == 200:
            logger.info("Token validation successful.")
            return True
        else:
            logger.warning(f"Token validation failed with status {response.status_code}: {response.text}")
            return False
    except requests.exceptions.RequestException as e:
        logger.error(f"Error calling token validation endpoint: {e}")
        return False

def lambda_handler(event, context):
    logger.debug(f"Received event: {json.dumps(event)}")
    origin = event.get("headers", {}).get("Origin")

    # Check required environment variables
    if not DYNAMODB_TABLE_NAME:
        logger.error("DYNAMODB_TABLE_NAME environment variable not set.")
        return build_response(400, {"error": "Bad Request", "message": "DYNAMODB_TABLE_NAME environment variable is required"}, origin)

    if not TOKEN_VALIDATION_ENDPOINT:
        logger.error("TOKEN_VALIDATION_ENDPOINT environment variable not set.")
        return build_response(400, {"error": "Bad Request", "message": "TOKEN_VALIDATION_ENDPOINT environment variable is required"}, origin)

    # Initialize table after environment checks
    table = dynamodb.Table(DYNAMODB_TABLE_NAME)

    # Handle OPTIONS request for CORS preflight
    if event.get("httpMethod") == "OPTIONS":
        logger.info("Handling OPTIONS request for CORS preflight.")
        if origin and ALLOWED_DOMAIN_REGEX.match(origin):
            return build_response(200, {"message": "CORS preflight check successful"}, origin)
        else:
            return build_response(403, {"error": "Forbidden", "message": "Origin not allowed."}, origin)

    # CORS domain check
    if not (origin and ALLOWED_DOMAIN_REGEX.match(origin)):
        logger.warning(f"Request from disallowed origin: {origin}")
        return build_response(403, {"error": "Forbidden", "message": "Origin not allowed."}, origin)

    # Authentication
    auth_header = event.get("headers", {}).get("Authorization")
    if not auth_header:
        auth_header_lower = event.get("headers", {}).get("authorization")
        if not auth_header_lower:
            logger.warning("Missing Authorization header.")
            return build_response(401, {"error": "Unauthorized", "message": "Authorization header is missing."}, origin)
        auth_header = auth_header_lower

    if not validate_token(auth_header):
        return build_response(401, {"error": "Unauthorized", "message": "Invalid or expired token."}, origin)

    # Ensure table is initialized
    if not table:
        logger.error("DynamoDB table is not initialized. Check DYNAMODB_TABLE_NAME.")
        return build_response(500, {"error": "Internal Server Error", "message": "Database not configured."}, origin)

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        logger.error("Invalid JSON in request body.")
        return build_response(400, {"error": "Bad Request", "message": "Invalid JSON format."}, origin)

    app_name = body.get("AppName")
    rating = body.get("Rating")
    description = body.get("Description")

    # Validate input
    errors = []
    if not app_name or not isinstance(app_name, str) or len(app_name) > MAX_APP_NAME_LENGTH:
        errors.append(f"AppName must be a string up to {MAX_APP_NAME_LENGTH} characters.")
    if not isinstance(rating, (int, float)) or not (1 <= rating <= 5):
        errors.append("Rating must be a number between 1 and 5.")
    if not description or not isinstance(description, str) or len(description) > MAX_DESCRIPTION_LENGTH:
        errors.append(f"Description must be a string up to {MAX_DESCRIPTION_LENGTH} characters.")

    # Malicious request detection
    for field, value in [("AppName", app_name), ("Description", description)]:
        if is_malicious(value):
            errors.append(f"Malicious content detected in {field}.")
    if isinstance(rating, str) and is_malicious(rating):
        errors.append("Malicious content detected in Rating.")

    if errors:
        logger.error(f"Validation errors: {errors}")
        return build_response(400, {"error": "Bad Request", "messages": errors}, origin)

    create_date = datetime.now(timezone.utc).isoformat()

    item = {
        "AppName": app_name,
        "CreateDate": create_date,
        "Rating": int(rating),
        "Description": description
    }

    try:
        logger.info(f"Attempting to put item into DynamoDB table {DYNAMODB_TABLE_NAME}: {item}")
        table.put_item(Item=item)
        logger.info("Successfully saved review to DynamoDB.")
        return build_response(201, {"message": "Review submitted successfully", "reviewId": f"{app_name}#{create_date}"}, origin)
    except Exception as e:
        logger.error(f"Error saving to DynamoDB: {e}")
        return build_response(500, {"error": "Internal Server Error", "message": "Could not save review."}, origin) 