# A small managed database for order results; the project brief does not
# mandate a specific database, so DynamoDB is an explicit design choice.
resource "aws_dynamodb_table" "orders" {
  name         = "quickcart-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  # DynamoDB enables server-side encryption at rest by default.
}
