# Keep the existing Terraform resource address so the main queue is updated
# in place, not recreated.
resource "aws_sqs_queue" "order_queue" {
  name                       = "order-request-queue"
  visibility_timeout_seconds = 60 # Lambda timeout (10s) x 6, per AWS guidance.
  message_retention_seconds  = 345600
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter_queue.arn
    maxReceiveCount     = 3 # Three deliveries TOTAL (initial + up to 2 retries).
  })
}

resource "aws_sqs_queue" "dead_letter_queue" {
  name                      = "order-request-dlq"
  message_retention_seconds = 1209600 # 14 days, SQS maximum.
  sqs_managed_sse_enabled   = true
}

# Only our main queue may redrive messages into this DLQ.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dead_letter_queue.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.order_queue.arn]
  })
}
