# ── BGP Status API — Lambda + Function URL ───────────────────────────────────
#
# Exposes four read-only vtysh show commands via a public HTTPS endpoint.
# The site widget calls this URL; no shell access is granted.

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
        # SSM: only SendCommand to this specific instance
        Effect = "Allow"
        Action = ["ssm:SendCommand"]
        Resource = [
          "arn:aws:ec2:${var.region}:*:instance/${aws_instance.cloud_router.id}",
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

# SSM instance profile so the EC2 can receive SSM commands

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

  environment {
    variables = {
      INSTANCE_ID = aws_instance.cloud_router.id
    }
  }
}

# Public HTTPS endpoint — no API Gateway needed, no cost

resource "aws_lambda_function_url" "bgp_status" {
  function_name      = aws_lambda_function.bgp_status.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["https://jacksalamone.com"]
    allow_methods = ["GET"]
    max_age       = 300
  }
}

output "bgp_api_url" {
  description = "Paste this into js/bgp-widget.js as API_URL"
  value       = aws_lambda_function_url.bgp_status.function_url
}
