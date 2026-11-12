"""SQS order processor.

The SQS event source mapping uses batch_size=1. Any unhandled exception causes
Lambda to report a failed invocation, allowing SQS visibility timeout + redrive
policy to handle retry and eventually DLQ. No direct Lambda-to-DLQ write.
"""

import json
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError


_table = None


def get_table():
    global _table
    if _table is None:
        table_name = os.environ["ORDERS_TABLE_NAME"]
        _table = boto3.resource("dynamodb").Table(table_name)
    return _table


def process_record(record):
    message_id = record["messageId"]
    payload = json.loads(record["body"])
    if not isinstance(payload, dict):
        raise ValueError("Order message must contain a JSON object")

    # Reusing an order_id prevents duplicate writes when SQS delivers a message
    # more than once. If no ID was supplied, SQS messageId stays stable on retry.
    order_id = payload.get("order_id", message_id)
    if not isinstance(order_id, str) or not order_id.strip():
        raise ValueError("order_id must be a nonempty string when supplied")

    if os.environ.get("ENABLE_TEST_FAILURES", "false").lower() == "true":
        if payload.get("simulate_failure") is True:
            raise RuntimeError("Intentional failure for Week 3 retry/DLQ demo")

    item = {
        "order_id": order_id,
        "payload_json": record["body"],
        "status": "PROCESSED",
        "sqs_message_id": message_id,
        "processed_at": datetime.now(timezone.utc).isoformat(),
    }

    try:
        get_table().put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(order_id)",
        )
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            # Idempotent success: order with the same ID is already stored.
            print(json.dumps({"event": "duplicate_order_ignored", "order_id": order_id}))
            return
        raise

    # Log identifiers, never the full order payload (may contain private data).
    print(json.dumps({"event": "order_processed", "order_id": order_id}))


def lambda_handler(event, context):
    for record in event["Records"]:
        # Do not swallow failures: SQS needs to retry failed messages.
        process_record(record)
    return {"processed_records": len(event["Records"])}
