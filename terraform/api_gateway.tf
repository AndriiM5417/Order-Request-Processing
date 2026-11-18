data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# REST API (not HTTP API) uses AWS-service integration directly with SQS.
# There is intentionally NO Order Submission Lambda and no JSON schema validator.
resource "aws_api_gateway_rest_api" "orders" {
  name        = "quickcart-order-api"
  description = "Direct order intake into the SQS main queue"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  parent_id   = aws_api_gateway_rest_api.orders.root_resource_id
  path_part   = "orders"
}

# API key + usage plan are a demo cost-control gate, NOT user authentication.
# A production customer-facing API needs appropriate authentication.
resource "aws_api_gateway_method" "post_orders" {
  rest_api_id      = aws_api_gateway_rest_api.orders.id
  resource_id      = aws_api_gateway_resource.orders.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "orders_to_sqs" {
  rest_api_id             = aws_api_gateway_rest_api.orders.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.post_orders.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  credentials             = aws_iam_role.api_gateway_sqs_role.arn
  uri                     = "arn:aws:apigateway:${data.aws_region.current.region}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.order_queue.name}"
  passthrough_behavior    = "NEVER"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode($input.body)"
  }

  depends_on = [aws_iam_role_policy.api_gateway_send_message]
}

resource "aws_api_gateway_method_response" "accepted" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.post_orders.http_method
  status_code = "202"

  response_models = { "application/json" = "Empty" }
}

resource "aws_api_gateway_integration_response" "accepted" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.post_orders.http_method
  status_code = aws_api_gateway_method_response.accepted.status_code

  response_templates = {
    "application/json" = jsonencode({ message = "Order accepted for processing" })
  }

  depends_on = [aws_api_gateway_integration.orders_to_sqs]
}

# Map SQS request failures to an error instead of falsely declaring success.
resource "aws_api_gateway_method_response" "bad_request" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.post_orders.http_method
  status_code = "400"
}

resource "aws_api_gateway_integration_response" "bad_request" {
  rest_api_id       = aws_api_gateway_rest_api.orders.id
  resource_id       = aws_api_gateway_resource.orders.id
  http_method       = aws_api_gateway_method.post_orders.http_method
  status_code       = aws_api_gateway_method_response.bad_request.status_code
  selection_pattern = "4\\d{2}"

  depends_on = [aws_api_gateway_integration.orders_to_sqs]
}

resource "aws_api_gateway_method_response" "server_error" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.post_orders.http_method
  status_code = "500"
}

resource "aws_api_gateway_integration_response" "server_error" {
  rest_api_id       = aws_api_gateway_rest_api.orders.id
  resource_id       = aws_api_gateway_resource.orders.id
  http_method       = aws_api_gateway_method.post_orders.http_method
  status_code       = aws_api_gateway_method_response.server_error.status_code
  selection_pattern = "5\\d{2}"

  depends_on = [aws_api_gateway_integration.orders_to_sqs]
}

# REST API deployments are snapshots: changing mappings needs a redeployment.
resource "aws_api_gateway_deployment" "orders" {
  rest_api_id = aws_api_gateway_rest_api.orders.id

  triggers = {
    redeployment = sha1(jsonencode({
      integration           = aws_api_gateway_integration.orders_to_sqs.id
      request_templates     = aws_api_gateway_integration.orders_to_sqs.request_templates
      request_parameters    = aws_api_gateway_integration.orders_to_sqs.request_parameters
      method                = aws_api_gateway_method.post_orders.id
      accepted_response     = aws_api_gateway_integration_response.accepted.id
      bad_request_response  = aws_api_gateway_integration_response.bad_request.id
      server_error_response = aws_api_gateway_integration_response.server_error.id
    }))
  }

  lifecycle { create_before_destroy = true }

  depends_on = [
    aws_api_gateway_integration_response.accepted,
    aws_api_gateway_integration_response.bad_request,
    aws_api_gateway_integration_response.server_error,
  ]
}

resource "aws_api_gateway_stage" "dev" {
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  deployment_id = aws_api_gateway_deployment.orders.id
  stage_name    = "dev"
}

resource "aws_api_gateway_api_key" "demo" {
  name    = "quickcart-demo-api-key"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "demo" {
  name = "quickcart-demo-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.orders.id
    stage  = aws_api_gateway_stage.dev.stage_name
  }

  throttle_settings {
    rate_limit  = 100
    burst_limit = 200
  }

  quota_settings {
    limit  = 20000
    period = "MONTH"
  }
}

resource "aws_api_gateway_usage_plan_key" "demo" {
  key_id        = aws_api_gateway_api_key.demo.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.demo.id
}
