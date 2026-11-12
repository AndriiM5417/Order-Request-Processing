"""Local unit tests; no AWS credentials or live resources required."""

import importlib.util
import json
import os
import unittest
from pathlib import Path
from unittest.mock import patch

from botocore.exceptions import ClientError


SPEC = importlib.util.spec_from_file_location(
    "order_processor", Path(__file__).resolve().parents[1] / "lambda" / "processor.py"
)
processor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(processor)


class FakeTable:
    def __init__(self):
        self.items = {}
        self.error_code = None

    def put_item(self, *, Item, ConditionExpression):
        assert ConditionExpression == "attribute_not_exists(order_id)"
        if self.error_code:
            raise ClientError({"Error": {"Code": self.error_code, "Message": "Failure"}}, "PutItem")
        if Item["order_id"] in self.items:
            raise ClientError(
                {"Error": {"Code": "ConditionalCheckFailedException", "Message": "Exists"}},
                "PutItem",
            )
        self.items[Item["order_id"]] = Item.copy()


def event(body, message_id="sqs-message-1"):
    return {"Records": [{"messageId": message_id, "body": body}]}


class TestOrderProcessor(unittest.TestCase):
    def setUp(self):
        self.table = FakeTable()
        processor._table = self.table

    def tearDown(self):
        processor._table = None

    def test_valid_order_is_saved(self):
        response = processor.lambda_handler(event(json.dumps({"order_id": "test-101"})), None)
        self.assertEqual(response, {"processed_records": 1})
        self.assertEqual(self.table.items["test-101"]["status"], "PROCESSED")

    def test_missing_order_id_uses_sqs_message_id(self):
        processor.lambda_handler(event('{"items":["one"]}', "message-2"), None)
        self.assertIn("message-2", self.table.items)

    def test_duplicate_is_idempotent(self):
        message = event('{"order_id":"test-202"}')
        processor.lambda_handler(message, None)
        processor.lambda_handler(message, None)
        self.assertEqual(len(self.table.items), 1)

    def test_invalid_json_raises_for_sqs_retry(self):
        with self.assertRaises(json.JSONDecodeError):
            processor.lambda_handler(event("{broken"), None)
        self.assertEqual(self.table.items, {})

    def test_non_object_json_raises(self):
        with self.assertRaises(ValueError):
            processor.lambda_handler(event('["not", "an", "order"]'), None)

    def test_deliberate_failure_only_when_enabled(self):
        message = event('{"order_id":"test-303","simulate_failure":true}')
        with patch.dict(os.environ, {"ENABLE_TEST_FAILURES": "false"}):
            processor.lambda_handler(message, None)
        self.assertIn("test-303", self.table.items)
        self.table.items.clear()
        with patch.dict(os.environ, {"ENABLE_TEST_FAILURES": "true"}):
            with self.assertRaises(RuntimeError):
                processor.lambda_handler(message, None)
        self.assertEqual(self.table.items, {})

    def test_database_failure_is_not_swallowed(self):
        self.table.error_code = "ProvisionedThroughputExceededException"
        with self.assertRaises(ClientError):
            processor.lambda_handler(event('{"order_id":"test-404"}'), None)


if __name__ == "__main__":
    unittest.main()
