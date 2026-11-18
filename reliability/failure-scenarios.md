
# Failure Scenarios and Recovery

## 1. Overview

The QuickCart Order Request Processing System is designed to handle failures without losing accepted customer orders.

The architecture uses Amazon API Gateway, Amazon SQS, AWS Lambda, Amazon DynamoDB, and Amazon CloudWatch.

This document describes potential failure scenarios, expected system behavior, recovery mechanisms, and testing results.

The main goal is to demonstrate reliable asynchronous order processing, retry behavior, and failure isolation.

## 2. Architecture

### Successful Processing

Customer → API Gateway → SQS Main Queue → Lambda → DynamoDB

### Failed Processing

Customer → API Gateway → SQS Main Queue → Lambda → Processing Failure → Retries → DLQ

The main SQS queue separates order submission from order processing.

If Lambda is temporarily unavailable, accepted messages can remain in SQS until processing becomes possible.

## 3. Failure Scenario 1: Invalid Order Data

### Description

An incoming order contains an invalid `order_id`.

The Lambda processor expects `order_id` to be a nonempty string when the field is supplied.

### Test Message

```json
{
  "order_id": 98765,
  "customer_id": "customer-invalid",
  "items": [
    {
      "product_id": "sku-001",
      "quantity": 1
    }
  ]
}
```

### Expected Behavior

1. API Gateway accepts the HTTP request.
2. The order message is stored in the main SQS queue.
3. Lambda receives the message.
4. Lambda validates the order data.
5. Validation fails because `order_id` is a number instead of a string.
6. Lambda raises a `ValueError`.
7. SQS makes the message available for another processing attempt.
8. After repeated failures, the message is moved to the DLQ.

### Observed Result

**Status: PASSED**

The API Gateway returned `HTTP 202 Accepted`.

CloudWatch Logs showed the following error:

```text
ValueError: order_id must be a nonempty string when supplied
```

After repeated processing attempts, the message appeared in `order-request-dlq`.

The invalid order was not stored as a successfully processed order in DynamoDB.

## 4. Failure Scenario 2: Intentional Lambda Failure

### Description

A controlled failure mechanism was implemented to test retry and DLQ behavior.

The Lambda processor checks the environment variable:

`ENABLE_TEST_FAILURES`

When this variable is set to `true`, an order containing `"simulate_failure": true` triggers an intentional exception.

### Test Message

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

### Expected Behavior

1. API Gateway accepts the order request.
2. SQS stores the message.
3. Lambda receives the message.
4. The processor detects the simulation flag.
5. Lambda raises a `RuntimeError`.
6. The message becomes available for retry.
7. Repeated processing attempts fail.
8. SQS transfers the message to the DLQ.

### Observed Result

**Status: PASSED**

CloudWatch Logs recorded:

```text
RuntimeError: Intentional failure for Week 3 retry/DLQ demo
```

The message was retried and subsequently appeared in the DLQ.

The failure simulation feature was disabled after testing by configuring:

`ENABLE_TEST_FAILURES = false`

This allows normal processing to continue without intentionally generated errors.

## 5. Failure Scenario 3: Temporary Processor Unavailability

### Description

The AWS Lambda processor may become temporarily unavailable.

The purpose of the SQS queue is to ensure that incoming orders do not depend on the immediate availability of the processing component.

### Expected Behavior

1. API Gateway accepts an order request.
2. The order message is stored in SQS.
3. Lambda is temporarily unavailable or unable to consume messages.
4. The message remains in the queue.
5. When the processor becomes available, Lambda consumes the message.
6. Successfully processed orders are stored in DynamoDB.

### Recovery Mechanism

Amazon SQS acts as a buffer between the producer and consumer.

The submission component does not need to wait for Lambda to finish processing.

### Test Status

**Not verified in the documented Week 3 tests.**

This scenario can be demonstrated by temporarily disabling the Lambda event source mapping, submitting an order, and verifying that the message remains in SQS until processing is re-enabled.

## 6. Failure Scenario 4: Temporary DynamoDB Failure

### Description

A temporary DynamoDB error may prevent an otherwise valid order from being stored.

Possible causes include a temporary service problem or insufficient IAM permissions.

### Expected Behavior

1. Lambda receives a valid message.
2. Lambda attempts to write the order to DynamoDB.
3. The database operation fails.
4. Lambda reports the exception.
5. The SQS message is not acknowledged successfully.
6. The visibility timeout expires.
7. The message becomes available for another attempt.

If DynamoDB becomes available before the retry limit is exceeded, the order can be processed successfully.

If processing repeatedly fails, the message can be moved to the DLQ.

### Test Status

**Not directly tested.**

The expected behavior follows the SQS and Lambda retry mechanism configured for the project.

## 7. Failure Scenario 5: Duplicate Message Processing

### Description

Amazon SQS Standard Queues use an at-least-once delivery model.

This means that the same message may be delivered more than once.

Duplicate processing could otherwise create unintended duplicate database operations.

### Implemented Protection

The Lambda processor uses the order identifier as the DynamoDB primary key.

The write operation includes:

```python
ConditionExpression="attribute_not_exists(order_id)"
```

This condition prevents an existing order item from being overwritten by a duplicate write.

The processor should handle DynamoDB conditional-write failures as an already-existing order instead of treating them as an unexpected infrastructure failure.

### Expected Behavior

1. Lambda receives an order message.
2. The order is written to DynamoDB.
3. The same message is delivered again.
4. The conditional write prevents overwriting the existing order.
5. The duplicate is handled without creating an additional order record.

### Limitation

If two different HTTP requests use the same `order_id`, they refer to the same DynamoDB primary key.

The current database design does not create separate records for orders with identical `order_id` values.

### Test Status

The conditional write exists in the Lambda implementation.

A dedicated duplicate-delivery test should be documented separately if performed.

## 8. Retry and DLQ Configuration

The system uses the following configuration:

| Setting | Value |
|---|---|
| Main SQS Queue | `order-request-queue` |
| Dead-Letter Queue | `order-request-dlq` |
| Queue Type | Standard |
| Main Queue Visibility Timeout | 60 seconds |
| Maximum Receive Count | 3 |
| DLQ Message Retention | 14 days |
| Lambda Consumer | `order-processor` |

The SQS redrive policy transfers repeatedly failing messages from the main queue to the DLQ.

Messages stored in the DLQ remain available for investigation.

## 9. Monitoring and Error Investigation

Amazon CloudWatch provides operational visibility into order processing.

### Lambda Logs

Log group:

`/aws/lambda/order-processor`

Relevant log events include:

- Successful order processing.
- Validation errors.
- Intentional test failures.
- Processing exceptions.
- Lambda execution duration.

### CloudWatch Alarms

The infrastructure includes:

- `quickcart-order-processor-errors`
- `quickcart-dlq-has-messages`

The first alarm monitors Lambda errors.

The second alarm monitors the presence of messages in the DLQ.

### Useful Metrics

- SQS `ApproximateNumberOfMessagesVisible`
- SQS `ApproximateNumberOfMessagesNotVisible`
- SQS `ApproximateAgeOfOldestMessage`
- Lambda `Errors`
- Lambda `Duration`

These metrics help identify processing failures, message backlogs, and orders requiring investigation.

## 10. Failure Recovery Procedure

When a failed order appears in the DLQ, the following procedure is recommended:

1. Open the DLQ in the AWS Management Console.
2. Inspect the failed message body.
3. Identify the order and its validation or processing problem.
4. Examine CloudWatch Logs.
5. Determine whether the failure was temporary or permanent.
6. Correct the underlying application, configuration, or data issue.
7. Redrive eligible messages to the main queue when appropriate.
8. Verify successful order processing in DynamoDB.

Invalid messages may require correction before reprocessing.

Automatic message correction and automatic DLQ recovery are not implemented in this project.

## 11. Summary of Failure Tests

| Scenario | Test Status | Result |
|---|---|---|
| Invalid `order_id` | Passed | Validation error, retries, DLQ |
| Intentional Lambda failure | Passed | Runtime error, retries, DLQ |
| Temporary processor unavailability | Not verified here | Expected buffering in SQS |
| Temporary DynamoDB failure | Not tested | Expected retry behavior |
| Duplicate message processing | Implementation present | Dedicated test evidence not documented |

## 12. Limitations and Future Improvements

The current implementation demonstrates basic failure handling and reliability.

Potential improvements include:

- More comprehensive incoming order validation.
- Automated alerts to an operations team.
- More detailed failure classifications.
- Automated recovery procedures.
- Additional duplicate-processing tests.
- Better separation between permanent and temporary errors.
- Additional monitoring dashboards.

## 13. Conclusion

The QuickCart Order Request Processing System demonstrates reliable failure handling through asynchronous messaging.

Amazon SQS provides message buffering and retry behavior.

AWS Lambda processes incoming orders and reports failures.

Repeatedly failing messages are moved to the DLQ for investigation.

Amazon CloudWatch provides logs and operational monitoring.

The successful tests demonstrate that invalid order data and intentional processing failures can be isolated without preventing normal orders from being processed.

This supports the main project objective: accepted customer orders should not be lost simply because the processing system experiences temporary problems.
