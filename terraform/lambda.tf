# ── BGP Status API — Lambda + API Gateway HTTP API ───────────────────────────
#
# Exposes four read-only vtysh show commands via a public HTTPS endpoint.
# Supports both routers via ?router=cloud|onprem query parameter.
# The site widget calls the API Gateway URL; no shell access is granted.
#
# Note: Lambda Function URLs are blocked at the account level for public access.
# API Gateway HTTP API is used instead (un70wfsu34.execute-api.us-east-1.amazonaws.com).

data "archive_file" "bgp_status" {
  type        = "zip"
  source_file = "${path.module}/../lambda/bgp_status.py"
  output_path = "${path.module}/../lambda/bgp_status.zip"
}

# IAM role for Lambda

resource "aws_iam_role" "bgp_lambda" {
  name = "bgp-status-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "bgp_lambda" {
  name = "bgp-lambda-policy"
  role = aws_iam_role.bgp_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:SendCommand"]
        Resource = [
          "arn:aws:ec2:${var.region}:*:instance/${aws_instance.cloud_router.id}",
          "arn:aws:ec2:${var.region}:*:instance/${aws_instance.onprem_router.id}",
          "arn:aws:ssm:*::document/AWS-RunShellScript",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

# SSM instance profile — attached to both routers so they can receive SSM commands

resource "aws_iam_instance_profile" "cloud_router_ssm" {
  name = "bgp-cloud-router-ssm-profile"
  role = aws_iam_role.cloud_router_ssm.name
}

resource "aws_iam_role" "cloud_router_ssm" {
  name = "bgp-cloud-router-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloud_router_ssm" {
  role       = aws_iam_role.cloud_router_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Lambda function

resource "aws_lambda_function" "bgp_status" {
  filename         = data.archive_file.bgp_status.output_path
  source_code_hash = data.archive_file.bgp_status.output_base64sha256
  function_name    = "bgp-status"
  role             = aws_iam_role.bgp_lambda.arn
  handler          = "bgp_status.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  reserved_concurrent_executions = 5

  environment {
    variables = {
      CLOUD_INSTANCE_ID  = aws_instance.cloud_router.id
      ONPREM_INSTANCE_ID = aws_instance.onprem_router.id
    }
  }
}

# API Gateway HTTP API — handles CORS, no Lambda Function URL needed

resource "aws_apigatewayv2_api" "bgp_status" {
  name          = "bgp-status-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [
      "https://jacksalamone.com",
      "https://main.doazuavx82vh4.amplifyapp.com",
    ]
    allow_methods = ["GET"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "bgp_status" {
  api_id             = aws_apigatewayv2_api.bgp_status.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.bgp_status.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "bgp_status" {
  api_id    = aws_apigatewayv2_api.bgp_status.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.bgp_status.id}"
}

resource "aws_apigatewayv2_stage" "bgp_status" {
  api_id      = aws_apigatewayv2_api.bgp_status.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "bgp_status_apigw" {
  statement_id  = "apigateway-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bgp_status.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.bgp_status.execution_arn}/*/*"
}

output "bgp_api_url" {
  description = "API Gateway endpoint — used in js/bgp-widget.js as API_URL"
  value       = aws_apigatewayv2_api.bgp_status.api_endpoint
}
