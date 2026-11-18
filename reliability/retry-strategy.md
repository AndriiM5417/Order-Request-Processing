
# Dead-Letter Queue (DLQ) Design

## 1. Overview

The QuickCart Order Request Processing System uses an Amazon SQS Dead-Letter Queue (DLQ) to isolate order messages that cannot be processed successfully.

The DLQ prevents permanently failing messages from being retried indefinitely and allows failed orders to be investigated without interrupting normal order processing.

## 2. Architecture

The system uses the following AWS components:

- **Amazon API Gateway:** Accepts incoming HTTP order requests.
- **Amazon SQS Main Queue:** Temporarily stores incoming orders.
- **AWS Lambda:** Processes orders asynchronously.
- **Amazon DynamoDB:** Stores successfully processed orders.
- **Amazon SQS Dead-Letter Queue:** Stores messages that repeatedly fail.
- **Amazon CloudWatch:** Provides logging and monitoring.

### Successful Processing

Customer → API Gateway → Main SQS Queue → Lambda → DynamoDB

### Failed Processing

Customer → API Gateway → Main SQS Queue → Lambda → Processing Failure → Retries → DLQ

The DLQ is connected to the main SQS queue through a redrive policy.

## 3. DLQ Configuration

The following configuration is implemented using Terraform.

| Parameter | Value |
|---|---|
| Main Queue | `order-request-queue` |
| Dead-Letter Queue | `order-request-dlq` |
| Queue Type | SQS Standard |
| Maximum Receive Count | `3` |
| Main Queue Visibility Timeout | `60 seconds` |
| DLQ Visibility Timeout | `30 seconds` |
| DLQ Message Retention | `14 days` |
| Encryption | SQS-managed server-side encryption |

The main queue uses a redrive policy with `maxReceiveCount = 3`.

When a message repeatedly fails processing and exceeds the configured receive threshold, Amazon SQS moves it to the DLQ.

The DLQ retains messages for investigation.

## 4. Failure Handling

When AWS Lambda receives a message from the main queue, it attempts to process the order.

If processing succeeds, the order is stored in DynamoDB and the message is removed from the main queue.

If processing fails, Lambda reports an error. The message is not successfully acknowledged and becomes available for another attempt after the visibility timeout expires.

After repeated failures, Amazon SQS moves the message to the DLQ.

This mechanism prevents problematic messages from continuously interfering with normal order processing.

## 5. Failure Scenarios

### Scenario 1: Invalid Order ID

The Lambda processor requires `order_id` to be a nonempty string when provided.

Valid example:

```json
{
  "order_id": "test-success-001",
  "customer_id": "customer-001",
  "items": [
    {
      "product_id": "sku-001",
      "quantity": 1
    }
  ]
}
```

Invalid example:

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

The invalid example contains a numeric `order_id` instead of a string.

The Lambda processor raises a `ValueError`:

`order_id must be a nonempty string when supplied`

The message is retried and eventually transferred to the DLQ.

### Scenario 2: Simulated Processing Failure

The project also includes a controlled failure mechanism for testing.

When the Lambda environment variable `ENABLE_TEST_FAILURES` is set to `true`, an order containing:

```json
{
  "simulate_failure": true
}
```

causes an intentional processing failure.

The Lambda processor raises:

`RuntimeError: Intentional failure for Week 3 retry/DLQ demo`

This allows the retry and DLQ mechanisms to be tested without introducing an actual infrastructure failure.

The feature is disabled during normal operation by setting `ENABLE_TEST_FAILURES` to `false`.

### Scenario 3: Temporary Service Failure

A temporary dependency failure, such as an unsuccessful DynamoDB operation, may prevent an otherwise valid order from being processed.

In this situation, SQS allows the message to become available again after the visibility timeout.

If a later processing attempt succeeds, the message can be removed from the queue.

If the failures continue beyond the configured threshold, the message is moved to the DLQ.

## 6. Monitoring

Amazon CloudWatch is used to monitor processing failures and DLQ activity.

The project includes the following CloudWatch alarms:

- `quickcart-dlq-has-messages` — monitors whether messages are available in the DLQ.
- `quickcart-order-processor-errors` — monitors errors reported by the order-processing Lambda.

Relevant metrics include:

- `ApproximateNumberOfMessagesVisible`
- `ApproximateNumberOfMessagesNotVisible`
- Lambda `Errors`
- Lambda `Duration`

CloudWatch Logs are available through:

`/aws/lambda/order-processor`

These logs help identify the reason for failed processing attempts.

## 7. Viewing Messages in the DLQ

Failed messages can be inspected through the AWS Management Console.

1. Open **Amazon SQS**.
2. Select `order-request-dlq`.
3. Open **Send and receive messages**.
4. Click **Poll for messages**.
5. Select a message to view its body and attributes.

The message body contains the original order information.

The `ApproximateReceiveCount` attribute represents the number of times the message has been received. Viewing messages through SQS polling can also increase this counter.

Therefore, the receive count displayed in the DLQ should not be interpreted as the exact number of Lambda processing failures.

## 8. DLQ Recovery Strategy

Messages in the DLQ require investigation before they can be processed again.

The recommended recovery procedure is:

1. Inspect the message body.
2. Identify the reason for processing failure.
3. Review the corresponding CloudWatch Logs.
4. Correct the underlying application or infrastructure problem.
5. Correct invalid message data if necessary.
6. Redrive suitable messages to the main queue.
7. Verify successful processing.

Amazon SQS supports DLQ redrive operations, but automatic recovery is not implemented as part of this project.

Messages should not be repeatedly redriven without resolving the underlying problem.

## 9. Security Considerations

Access to the main queue and DLQ should be controlled through AWS IAM.

The implementation follows the principle of least privilege.

Important security measures include:

- Restricting access to SQS queues.
- Using IAM roles for AWS service integrations.
- Enabling server-side encryption.
- Avoiding unnecessary permissions.
- Protecting potentially sensitive customer order information.

## 10. Testing and Verification

The DLQ functionality was tested using two scenarios:

**Test 1 — Intentional Processing Failure**

An order containing `"simulate_failure": true` was submitted while test failures were enabled.

The Lambda processor reported a `RuntimeError`, and the message eventually appeared in the DLQ.

**Test 2 — Invalid Order Data**

An order containing a numeric `order_id` was submitted.

The API Gateway returned `HTTP 202 Accepted`, confirming that the message was accepted for asynchronous processing.

Lambda rejected the order because the `order_id` was not a string.

After repeated processing failures, the message appeared in the DLQ.

These tests demonstrate that the system isolates repeatedly failing messages while allowing normal orders to continue processing.

Detailed evidence should be recorded in `tests/test-results.md`.

## 11. Limitations and Future Improvements

The current DLQ mechanism provides basic failure isolation, but several improvements are possible:

- Automated notifications when messages enter the DLQ.
- More detailed failure classification.
- Improved validation of incoming order data.
- Automated investigation workflows.
- Controlled message correction and redrive procedures.
- Additional operational dashboards and metrics.

The DLQ does not automatically repair failed messages. It preserves them for later investigation and recovery.

## 12. Conclusion

The Amazon SQS Dead-Letter Queue improves the reliability of the QuickCart Order Request Processing System by isolating messages that repeatedly fail processing.

Combined with SQS retry behavior, AWS Lambda, DynamoDB, and CloudWatch, the DLQ helps ensure that problematic orders remain available for investigation rather than being silently lost.

This implementation fulfills the project's Week 3 requirement for dead-letter queue configuration and failure isolation.
