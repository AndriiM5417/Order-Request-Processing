# Existing Lambda role and SQS policy attachment: keep Terraform addresses.
resource "aws_iam_role" "processor_lambda_role" {
  name = "order-processor-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "processor_lambda_sqs" {
  role       = aws_iam_role.processor_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

# Lambda can write only to this project's order table.
resource "aws_iam_role_policy" "processor_lambda_dynamodb" {
  name = "put-orders-only"
  role = aws_iam_role.processor_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.orders.arn
      }
    ]
  })
}

# API Gateway assumes this role to invoke the SQS SendMessage operation.
resource "aws_iam_role" "api_gateway_sqs_role" {
  name = "quickcart-api-gateway-sqs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "apigateway.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_send_message" {
  name = "send-message-to-order-queue"
  role = aws_iam_role.api_gateway_sqs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.order_queue.arn
      }
    ]
  })
}
