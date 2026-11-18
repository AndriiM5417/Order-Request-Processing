
# Dead-Letter Queue (DLQ) Design

## 1. Overview

The QuickCart Order Request Processing System uses an Amazon SQS Dead-Letter Queue (DLQ) to isolate order messages that repeatedly fail processing.

The DLQ improves system reliability by preventing problematic messages from being retried indefinitely and preserving them for investigation.

The main objectives are:

- Prevent permanently failing messages from interfering with normal order processing.
- Preserve failed messages for investigation.
- Limit repeated processing attempts.
- Improve fault isolation.
- Provide operational visibility through Amazon CloudWatch.

## 2. Architecture

The system uses the following AWS components:

- **Amazon API Gateway:** Receives customer order requests.
- **Amazon SQS Main Queue:** Stores incoming order messages.
- **AWS Lambda:** Processes orders asynchronously.
- **Amazon DynamoDB:** Stores successfully processed orders.
- **Amazon SQS Dead-Letter Queue:** Stores messages that repeatedly fail.
- **Amazon CloudWatch:** Provides logs, metrics, and alarms.

### Successful Processing Flow

Customer → API Gateway → Main SQS Queue → Lambda → DynamoDB

### Failed Processing Flow

Main SQS Queue → Lambda → Processing Failure → Retry → Repeated Failure → DLQ

The DLQ is connected to the main SQS queue through an SQS redrive policy.

## 3. DLQ Configuration

The configuration documented for the project is:

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

**Configuration verification:** These values are based on the project configuration described previously and must be checked against the deployed Terraform configuration.

The main queue uses a redrive policy to determine when repeatedly failing messages are moved to the DLQ.

The `maxReceiveCount` parameter defines the receive threshold for moving messages to the DLQ.

The visibility timeout determines how long a received message remains temporarily invisible to other consumers.

## 4. Failure Handling

When AWS Lambda receives an order message from SQS, it attempts to process the order.

### Successful Processing

1. Lambda receives the message from SQS.
2. Lambda validates the order data.
3. Lambda stores the order in DynamoDB.
4. Processing completes successfully.
5. The message is removed from the main queue.

### Failed Processing

1. Lambda receives the message.
2. Processing fails.
3. Lambda reports the failure.
4. The failed message is not successfully acknowledged.
5. The visibility timeout expires.
6. The message becomes available for another processing attempt.
7. After repeated failures and the configured receive threshold, SQS moves the message to the DLQ.

This mechanism isolates problematic messages while allowing other orders to continue processing.

## 5. Failure Scenarios

### Scenario 1: Invalid Order Data

An order contains an invalid `order_id`.

Example:

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

The Lambda processor expects `order_id` to be a nonempty string when supplied.

The invalid message causes a validation error:

`ValueError: order_id must be a nonempty string when supplied`

The message is retried and can eventually be moved to the DLQ.

### Scenario 2: Simulated Processing Failure

The project includes a controlled failure mechanism for testing retry and DLQ behavior.

When the Lambda environment variable `ENABLE_TEST_FAILURES` is set to `true`, an order containing:

```json
{
  "simulate_failure": true
}
```

triggers an intentional processing failure.

The processor raises:

`RuntimeError: Intentional failure for Week 3 retry/DLQ demo`

This allows retry and DLQ behavior to be tested without introducing an actual AWS infrastructure failure.

During normal operation, the test mechanism should be disabled.

### Scenario 3: Temporary AWS Service Failure

A temporary DynamoDB error may prevent an otherwise valid order from being stored.

Expected behavior:

1. Lambda attempts to process the message.
2. The DynamoDB operation fails.
3. Lambda reports the processing failure.
4. The message becomes available again after the visibility timeout.
5. Another processing attempt is performed.
6. If processing succeeds, the message is removed.
7. If failures continue, the message eventually reaches the DLQ.

## 6. Monitoring and Logging

Amazon CloudWatch provides visibility into message processing and failure handling.

Important metrics include:

- `ApproximateNumberOfMessagesVisible`
- `ApproximateNumberOfMessagesNotVisible`
- `ApproximateAgeOfOldestMessage`
- Lambda `Errors`
- Lambda `Duration`

The project includes CloudWatch alarms for:

- Messages appearing in the DLQ.
- Errors reported by the order-processing Lambda.

Alarm names:

- `quickcart-dlq-has-messages`
- `quickcart-order-processor-errors`

Lambda execution logs are available in the log group:

`/aws/lambda/order-processor`

These logs help identify processing errors and investigate failed messages.

## 7. Inspecting Messages in the DLQ

Failed messages can be inspected through the AWS Management Console.

Steps:

1. Open Amazon SQS.
2. Select the `order-request-dlq` queue.
3. Open **Send and receive messages**.
4. Select **Poll for messages**.
5. Open a message to inspect its body and attributes.

The message body contains the original order data.

The `ApproximateReceiveCount` attribute provides information about message receives, but it should not be interpreted as an exact count of Lambda processing failures.

## 8. DLQ Recovery Strategy

Messages stored in the DLQ require investigation before reprocessing.

The recommended recovery procedure is:

1. Inspect the failed message.
2. Identify the cause of failure.
3. Review the corresponding CloudWatch Logs.
4. Correct the application or infrastructure problem.
5. Correct invalid message data if necessary.
6. Redrive suitable messages to the main queue.
7. Verify successful processing.

Amazon SQS supports redriving messages from a DLQ to a source queue.

Automatic recovery is not implemented as part of the current project.

Messages should not be repeatedly redriven without resolving the underlying problem.

## 9. Security Considerations

The DLQ should be protected using AWS IAM permissions.

Important security considerations include:

- Applying the principle of least privilege.
- Restricting access to SQS queues.
- Using IAM roles for AWS service integrations.
- Enabling server-side encryption.
- Protecting potentially sensitive customer order information.
- Avoiding unnecessary permissions.

Only authorized users and services should be able to inspect or modify DLQ messages.

## 10. Testing and Verification

The DLQ mechanism should be verified using controlled failure scenarios.

| Test Scenario | Expected Result |
|---|---|
| Valid order | Successfully stored in DynamoDB |
| Invalid order ID | Validation error and retry |
| Intentional Lambda failure | Processing error and retry |
| Repeated processing failures | Message transferred to DLQ |
| Temporary service failure | Message retried after visibility timeout |
| DLQ inspection | Failed message available for investigation |

Testing evidence should include:

- CloudWatch Logs showing processing failures.
- SQS metrics demonstrating message activity.
- Evidence of failed messages reaching the DLQ.
- Successful processing results for valid orders.

Actual test results and evidence should be documented separately in:

`tests/test-results.md`

## 11. Limitations and Future Improvements

The current DLQ design provides basic failure isolation and recovery capabilities.

Important limitations include:

- Failed messages require investigation.
- The DLQ does not automatically correct invalid data.
- Repeated retries increase processing time and may increase costs.
- Standard SQS queues may deliver messages more than once.
- Consumers should implement idempotency to prevent unintended duplicate processing.

Potential improvements include:

- Automated notifications when DLQ messages appear.
- More detailed failure classification.
- Improved input validation.
- Automated recovery workflows.
- Controlled DLQ redrive procedures.
- Additional CloudWatch dashboards and alarms.

## 12. Conclusion

The Amazon SQS Dead-Letter Queue improves the reliability of the QuickCart Order Request Processing System.

It prevents repeatedly failing messages from interfering with normal order processing and preserves them for later investigation.

Together with AWS Lambda, Amazon SQS retry behavior, DynamoDB, and CloudWatch, the DLQ supports reliable asynchronous order processing.

This design addresses the Week 3 requirements for failure isolation, retry handling, and dead-letter queue configuration.
