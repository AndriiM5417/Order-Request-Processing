output "order_queue_url" {
  value = aws_sqs_queue.order_queue.url
}

output "order_queue_arn" {
  value = aws_sqs_queue.order_queue.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dead_letter_queue.url
}

output "orders_table_name" {
  value = aws_dynamodb_table.orders.name
}

output "orders_api_url" {
  value = "https://${aws_api_gateway_rest_api.orders.id}.execute-api.${data.aws_region.current.region}.amazonaws.com/${aws_api_gateway_stage.dev.stage_name}/orders"
}

# Only output the API key ID, never its secret value.
output "orders_api_key_id" {
  value = aws_api_gateway_api_key.demo.id
}
