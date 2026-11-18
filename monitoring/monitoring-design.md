
# Monitoring Design

## 1. Overview

The QuickCart Order Request Processing System uses Amazon CloudWatch to monitor asynchronous order processing, detect failures, and provide operational visibility.

The monitoring solution covers:

- Amazon SQS main queue activity.
- AWS Lambda processing performance.
- Processing errors and failures.
- Dead-Letter Queue (DLQ) activity.
- CloudWatch Logs and alarms.

The main objective is to identify problems before they significantly affect order processing.

## 2. System Architecture

The implemented architecture consists of:

Customer → API Gateway → SQS Main Queue → Lambda → DynamoDB

Failed messages follow a separate path:

SQS Main Queue → Lambda → Retries → Dead-Letter Queue

Amazon CloudWatch monitors the queue and processing components.

### AWS Resources

| Component | Resource Name |
|---|---|
| API Gateway | `quickcart-order-api` |
| Main SQS Queue | `order-request-queue` |
| Lambda Processor | `order-processor` |
| DynamoDB Table | `quickcart-orders` |
| Dead-Letter Queue | `order-request-dlq` |
| CloudWatch Log Group | `/aws/lambda/order-processor` |

## 3. Monitoring Objectives

The monitoring design should answer the following questions:

1. Are new orders arriving in the system?
2. Are orders being processed successfully?
3. Are messages accumulating in the main queue?
4. Is the Lambda processor experiencing errors?
5. Are failed messages reaching the DLQ?
6. How long does order processing take?
7. Does the system require operator intervention?

These questions help evaluate the health and reliability of the asynchronous processing workflow.

## 4. Amazon SQS Monitoring

Amazon SQS publishes operational metrics to CloudWatch.

### Main Queue Metrics

**ApproximateNumberOfMessagesVisible**

Shows the approximate number of messages available for processing.

An increasing value may indicate that incoming orders are arriving faster than Lambda can process them.

**ApproximateNumberOfMessagesNotVisible**

Shows the approximate number of messages currently in flight.

These messages have been received but have not yet been deleted or become visible again.

**ApproximateAgeOfOldestMessage**

Shows the approximate age of the oldest unprocessed message.

An increasing age may indicate processing delays or a backlog.

**NumberOfMessagesSent**

Measures messages sent to the queue during a monitoring period.

**NumberOfMessagesDeleted**

Measures messages deleted from the queue.

These metrics help identify changes in message traffic and processing capacity.

### Dead-Letter Queue Metrics

The most important DLQ metric is:

`ApproximateNumberOfMessagesVisible`

This metric shows the approximate number of messages available in the DLQ.

A value greater than zero indicates that at least one message requires investigation.

## 5. AWS Lambda Monitoring

AWS Lambda publishes execution and performance metrics to CloudWatch.

### Important Metrics

| Metric | Purpose |
|---|---|
| `Invocations` | Number of Lambda executions |
| `Errors` | Number of failed Lambda executions |
| `Duration` | Execution duration |
| `Throttles` | Invocations rejected because of concurrency limits |
| `ConcurrentExecutions` | Number of simultaneous Lambda executions |

### Error Monitoring

The `Errors` metric is particularly important because the Lambda processor is responsible for processing order messages.

An increase in Lambda errors can indicate:

- Invalid order data.
- Application exceptions.
- DynamoDB write failures.
- Permission problems.
- Temporary infrastructure problems.

### Duration Monitoring

The `Duration` metric helps evaluate processing performance.

Increasing execution duration may indicate slow processing or dependency problems.

Lambda duration should also be considered when configuring the SQS visibility timeout.

## 6. CloudWatch Logs

The Lambda processor writes execution logs to Amazon CloudWatch Logs.

### Log Group

`/aws/lambda/order-processor`

### Successful Processing

The processor records successful order-processing events.

Example:

```json
{
  "event": "order_processed",
  "order_id": "test-002"
}
```

These events help confirm that Lambda successfully processed an order.

### Failed Processing

When Lambda encounters an exception, CloudWatch Logs records the error and traceback.

Example validation error:

```text
ValueError: order_id must be a nonempty string when supplied
```

Example intentional processing failure:

```text
RuntimeError: Intentional failure for Week 3 retry/DLQ demo
```

These logs were observed during the project's Week 3 testing.

### Log Retention

The CloudWatch log group is configured with a retention period of:

**7 days**

This limits long-term log storage while retaining recent execution information for troubleshooting.

## 7. CloudWatch Alarms

The project includes two CloudWatch metric alarms.

### Alarm 1: Lambda Processing Errors

**Alarm Name:**

`quickcart-order-processor-errors`

**Purpose:**

Detect failed executions of the order-processing Lambda.

**Configuration:**

| Parameter | Value |
|---|---|
| Namespace | `AWS/Lambda` |
| Metric | `Errors` |
| Dimension | `FunctionName = order-processor` |
| Statistic | `Sum` |
| Period | 60 seconds |
| Evaluation Periods | 1 |
| Threshold | 0 |
| Comparison | `GreaterThanThreshold` |
| Missing Data | `notBreaching` |

The alarm enters the ALARM state when the number of Lambda errors exceeds zero during the evaluation period.

### Alarm 2: DLQ Messages

**Alarm Name:**

`quickcart-dlq-has-messages`

**Purpose:**

Detect messages that have reached the Dead-Letter Queue.

**Configuration:**

| Parameter | Value |
|---|---|
| Namespace | `AWS/SQS` |
| Metric | `ApproximateNumberOfMessagesVisible` |
| Dimension | `QueueName = order-request-dlq` |
| Statistic | `Maximum` |
| Period | 60 seconds |
| Evaluation Periods | 1 |
| Threshold | 0 |
| Comparison | `GreaterThanThreshold` |
| Missing Data | `notBreaching` |

The alarm enters the ALARM state when at least one message is visible in the DLQ during the evaluation period.

### Alarm Notifications

The current Terraform configuration defines metric alarms but does not configure an SNS notification topic or email notification action.

Therefore, the alarms can be inspected through the CloudWatch console, but automatic email notifications are not implemented.

Email or SNS notifications are recommended as a future improvement.

## 8. Monitoring Through AWS Console

### View Lambda Logs

1. Open the AWS Management Console.
2. Navigate to CloudWatch.
3. Select **Logs → Log groups**.
4. Open `/aws/lambda/order-processor`.
5. Select a log stream to inspect processing events.

### View Lambda Metrics

1. Open AWS Lambda.
2. Select `order-processor`.
3. Open the **Monitor** tab.
4. Review invocations, errors, and duration.

### View SQS Metrics

1. Open Amazon SQS.
2. Select `order-request-queue` or `order-request-dlq`.
3. Open the **Monitoring** tab.
4. Review queue metrics.

### View CloudWatch Alarms

1. Open Amazon CloudWatch.
2. Navigate to **Alarms → All alarms**.
3. Select the appropriate alarm.
4. Review its state and metric history.

## 9. Monitoring During Failure Testing

Two failure scenarios were demonstrated during Week 3 testing.

### Test 1: Intentional Lambda Failure

An order containing `"simulate_failure": true` was submitted while the test failure mechanism was enabled.

**Observed results:**

- API Gateway accepted the request.
- Lambda raised a `RuntimeError`.
- CloudWatch Logs recorded the exception.
- SQS retried processing.
- The message eventually appeared in the DLQ.

### Test 2: Invalid Order Data

An order containing a numeric `order_id` was submitted.

**Observed results:**

- API Gateway returned HTTP 202 Accepted.
- Lambda rejected the message.
- CloudWatch Logs recorded a `ValueError`.
- The message was retried.
- The message eventually appeared in the DLQ.

These tests confirmed the logging and failure-isolation mechanisms.

The actual state transitions of the CloudWatch alarms were not separately documented in the available test evidence.

## 10. Operational Response

When a monitoring alarm indicates a problem, an operator should:

1. Identify the affected AWS resource.
2. Review CloudWatch metrics.
3. Inspect relevant CloudWatch Logs.
4. Determine whether the problem is temporary or permanent.
5. Examine messages in the DLQ when necessary.
6. Correct the underlying issue.
7. Reprocess suitable failed messages if appropriate.
8. Confirm that the system has returned to normal operation.

The DLQ should not be cleared without investigating failed messages.

## 11. Limitations

The current monitoring implementation has several limitations:

- No automated email or SNS notifications.
- No dedicated CloudWatch dashboard.
- No end-to-end order-processing latency measurement.
- No automatic DLQ message recovery.
- Basic logging rather than detailed business-level metrics.
- CloudWatch Logs are retained for only seven days.

These limitations are acceptable for the current educational implementation but should be considered for production use.

## 12. Future Improvements

Potential improvements include:

- SNS notifications for CloudWatch alarms.
- A CloudWatch dashboard for operational metrics.
- Custom metrics for successfully processed orders.
- Monitoring of end-to-end processing latency.
- Additional alarms for growing SQS backlogs.
- Monitoring the age of the oldest unprocessed message.
- Improved structured logging and correlation IDs.
- Automated operational incident notifications.

## 13. Conclusion

Amazon CloudWatch provides monitoring and logging for the QuickCart Order Request Processing System.

SQS metrics provide visibility into queue activity and message backlogs.

Lambda metrics and logs help identify processing failures and performance problems.

CloudWatch alarms detect Lambda errors and messages reaching the DLQ.

Together, these components provide basic operational visibility and support the Week 3 monitoring requirements of the project.
