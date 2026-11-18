
# Test Results

## 1. Overview

This document describes the testing performed for the QuickCart AWS Order Request Queue & Processing System.

The main objective is to verify that the system processes valid orders successfully, retries failed messages, and moves repeatedly failing messages to the Dead-Letter Queue (DLQ).

Testing was performed using:

- AWS CLI
- cURL
- AWS Management Console
- Amazon CloudWatch Logs
- Amazon SQS
- Amazon DynamoDB

Automated Python unit tests are maintained separately in `tests/test_processor.py`.

## 2. System Under Test

The implemented architecture is:

Customer → API Gateway → SQS Main Queue → Lambda → DynamoDB

Failed messages follow this path:

SQS Main Queue → Lambda → Processing Failure → Retries → DLQ

### AWS Resources

| Resource | Name |
|---|---|
| API Gateway | `quickcart-order-api` |
| Main SQS Queue | `order-request-queue` |
| Lambda Function | `order-processor` |
| DynamoDB Table | `quickcart-orders` |
| Dead-Letter Queue | `order-request-dlq` |
| CloudWatch Log Group | `/aws/lambda/order-processor` |
| AWS Region | `eu-central-1` |

## 3. Test Environment

The infrastructure was deployed and configured using Terraform.

The following settings were used:

| Parameter | Value |
|---|---|
| SQS Queue Type | Standard |
| Main Queue Visibility Timeout | 60 seconds |
| Maximum Receive Count | 3 |
| Dead-Letter Queue | Enabled |
| Lambda Runtime | Python 3.12 |
| Lambda Test Failures | Disabled after testing |

The Lambda test failure mechanism can be temporarily enabled using the `ENABLE_TEST_FAILURES` environment variable.

## 4. Test Case 1: Single Valid Order

**Objective:** Verify that a valid order is accepted and processed.

### Test Input

```json
{
  "order_id": "test-001",
  "customer_id": "customer-001",
  "items": [
    {
      "product_id": "sku-001",
      "quantity": 1
    }
  ]
}
```

### Expected Result

1. API Gateway accepts the HTTP request.
2. SQS receives the order message.
3. Lambda processes the message.
4. DynamoDB stores the order.
5. CloudWatch Logs records successful processing.

### Observed Result

**Status: PASSED**

- API Gateway returned HTTP 202 Accepted.
- Lambda successfully processed the order.
- CloudWatch Logs contained:

```text
{"event": "order_processed", "order_id": "test-001"}
```

The successful processing flow was demonstrated.

## 5. Test Case 2: Multiple Valid Orders

**Objective:** Verify that the system can process multiple customer orders.

### Test Orders

The following order IDs were used:

- `test-002`
- `test-003`
- `test-004`
- `test-005`
- `test-006`

### Expected Result

All orders are accepted by API Gateway and processed asynchronously.

### Observed Result

**Status: PASSED**

All five requests returned HTTP 202 Accepted.

CloudWatch Logs recorded successful processing events for each order:

```text
{"event": "order_processed", "order_id": "test-002"}
{"event": "order_processed", "order_id": "test-003"}
{"event": "order_processed", "order_id": "test-004"}
{"event": "order_processed", "order_id": "test-005"}
{"event": "order_processed", "order_id": "test-006"}
```

This demonstrates that the system can process multiple messages asynchronously.

## 6. Test Case 3: Intentional Lambda Failure

**Objective:** Verify retry behavior and DLQ functionality using a controlled processing failure.

### Test Input

```json
{
  "order_id": "test-failure-001",
  "customer_id": "customer-failure",
  "simulate_failure": true,
  "items": [
    {
      "product_id": "sku-001",
      "quantity": 1
    }
  ]
}
```

### Test Configuration

The Lambda environment variable was temporarily set to:

```text
ENABLE_TEST_FAILURES=true
```

### Expected Result

1. API Gateway accepts the order.
2. SQS stores the message.
3. Lambda raises an intentional error.
4. SQS retries processing.
5. The message eventually reaches the DLQ.

### Observed Result

**Status: PASSED**

API Gateway returned HTTP 202 Accepted.

CloudWatch Logs showed repeated errors:

```text
RuntimeError: Intentional failure for Week 3 retry/DLQ demo
```

The message was subsequently found in `order-request-dlq`.

The SQS message body contained the original `test-failure-001` order.

After testing, the intentional failure mechanism was disabled:

```text
ENABLE_TEST_FAILURES=false
```

## 7. Test Case 4: Invalid Order ID

**Objective:** Verify that invalid order data causes a processing failure and is isolated in the DLQ.

### Test Input

```json
{
  "order_id": 12345,
  "customer_id": "customer-invalid",
  "items": [
    {
      "product_id": "sku-001",
      "quantity": 1
    }
  ]
}
```

### Expected Result

The Lambda processor rejects the message because `order_id` is a number instead of a string.

Repeated failures should eventually move the message to the DLQ.

### Observed Result

**Status: PASSED**

API Gateway returned:

```text
HTTP/2 202
{"message":"Order accepted for processing"}
```

CloudWatch Logs showed:

```text
ValueError: order_id must be a nonempty string when supplied
```

The failed message subsequently appeared in the DLQ.

This confirmed that invalid messages are isolated from normal order processing.

## 8. Test Case 5: Retry Configuration

**Objective:** Verify that SQS is configured to retry failed messages before sending them to the DLQ.

### Configuration

The main SQS queue uses the following redrive policy:

```json
{
  "deadLetterTargetArn": "arn:aws:sqs:eu-central-1:182312754480:order-request-dlq",
  "maxReceiveCount": 3
}
```

### Observed Result

**Status: PASSED**

The redrive policy was confirmed using AWS CLI.

CloudWatch Logs demonstrated repeated Lambda processing failures.

The failing message eventually disappeared from the main queue and appeared in the DLQ.

The DLQ inspection showed an `ApproximateReceiveCount` value of 4 for the inspected message.

This counter includes message receives and should not be interpreted as the exact number of failed Lambda executions.

## 9. Test Case 6: CloudWatch Logging

**Objective:** Verify that CloudWatch Logs records successful and failed Lambda processing.

### Observed Result

**Status: PASSED**

The following log events were confirmed:

- Successful order-processing events.
- Intentional `RuntimeError` exceptions.
- Validation `ValueError` exceptions.
- Lambda execution start and end events.
- Lambda execution duration reports.

Log group:

```text
/aws/lambda/order-processor
```

CloudWatch Logs provided the information required to investigate processing failures.

## 10. Test Case 7: DynamoDB Storage

**Objective:** Verify that successfully processed orders are stored in DynamoDB.

### Expected Result

Valid order messages should create records in the `quickcart-orders` table.

### Observed Result

**Status: PASSED**

Successfully processed orders were visible in the DynamoDB table through the AWS Management Console.

The stored records included:

- `order_id`
- `payload_json`
- `status`
- `sqs_message_id`
- `processed_at`

The `status` value for successfully processed orders was:

```text
PROCESSED
```

## 11. Automated Unit Tests

The project includes a Python unit test file:

```text
tests/test_processor.py
```

The file contains automated tests for the Lambda processor, including tests involving the `ENABLE_TEST_FAILURES` environment variable.

The automated unit test execution result has not been included in the available evidence.

Before final submission, the tests should be executed and their actual results recorded.

Suggested command from the project root:

```bash
python3 -m pytest tests/test_processor.py -v
```

The resulting test summary should be added to this document after execution.

## 12. Test Summary

| Test | Status | Result |
|---|---|---|
| Single valid order | PASSED | Lambda processing confirmed |
| Multiple valid orders | PASSED | Five orders processed |
| Intentional Lambda failure | PASSED | Retries and DLQ confirmed |
| Invalid order ID | PASSED | Validation failure and DLQ confirmed |
| Retry configuration | PASSED | `maxReceiveCount=3` verified |
| CloudWatch logging | PASSED | Success and error logs confirmed |
| DynamoDB storage | PASSED | Processed orders visible |
| Automated Python unit tests | NOT VERIFIED | Execution result not recorded |
| Temporary processor unavailability | NOT VERIFIED | Separate test evidence required |
| Temporary DynamoDB failure | NOT TESTED | Expected behavior documented |

## 13. Conclusions

The completed integration tests demonstrate that the QuickCart system successfully processes valid orders asynchronously.

Amazon API Gateway accepts incoming requests, Amazon SQS buffers messages, and AWS Lambda processes orders and stores successful results in DynamoDB.

The failure-handling tests confirmed that repeatedly failing messages are retried and eventually transferred to the Dead-Letter Queue.

Amazon CloudWatch Logs recorded successful processing activity and detailed error information.

These results demonstrate the core reliability and failure-handling mechanisms required for Week 3.

Additional automated unit test execution evidence and optional failure scenarios can be included before the final project presentation.
