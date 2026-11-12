# IMPORTANT: If Lambda has already created this group, import it into the
# current Terraform state BEFORE running apply. See README.md.
resource "aws_cloudwatch_log_group" "processor" {
  name              = "/aws/lambda/order-processor"
  retention_in_days = 7
}

# Standard SQS/Lambda service metrics are already published to CloudWatch.
# The alarms below make processing failures and DLQ backlog visible.
resource "aws_cloudwatch_metric_alarm" "dlq_messages_visible" {
  alarm_name          = "quickcart-dlq-has-messages"
  alarm_description   = "At least one unprocessed order has reached the DLQ."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dead_letter_queue.name }
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "processor_errors" {
  alarm_name          = "quickcart-order-processor-errors"
  alarm_description   = "The order processor Lambda has reported an error."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.processor.function_name }
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
}
