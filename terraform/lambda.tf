data "archive_file" "processor_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/processor.py"
  output_path = "${path.module}/processor_lambda.zip"
}

resource "aws_lambda_function" "processor" {
  function_name = "order-processor" # Preserve current deployed function.

  role    = aws_iam_role.processor_lambda_role.arn
  runtime = "python3.12"
  handler = "processor.lambda_handler"

  filename         = data.archive_file.processor_lambda_zip.output_path
  source_code_hash = data.archive_file.processor_lambda_zip.output_base64sha256

  timeout = 10

  environment {
    variables = {
      ORDERS_TABLE_NAME    = aws_dynamodb_table.orders.name
      ENABLE_TEST_FAILURES = var.enable_test_failures ? "true" : "false"
    }
  }

  depends_on = [
    aws_iam_role_policy.processor_lambda_sqs_restricted,
    aws_iam_role_policy.processor_lambda_dynamodb,
    aws_cloudwatch_log_group.processor,
  ]
}

resource "aws_lambda_event_source_mapping" "order_queue_trigger" {
  event_source_arn = aws_sqs_queue.order_queue.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 1 # One failed message cannot cause others to be retried.

  depends_on = [
    aws_iam_role_policy.processor_lambda_sqs_restricted
  ]
}
