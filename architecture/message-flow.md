# Message Flow

## Overview

The system uses asynchronous order processing.  
The customer request is accepted first, and the order is then placed into a message queue before processing.

## Order Message Flow

1. The customer sends an HTTP order request to Amazon API Gateway.

2. Amazon API Gateway receives the request and forwards it to the Order Submission Lambda function.

3. The Order Submission Lambda validates the incoming order request.

4. If the request is valid, the Lambda function sends the order message to Amazon SQS.

5. Amazon SQS stores the order message in the queue until it can be processed.

6. The Order Processor Lambda receives messages from the SQS queue.

7. The Order Processor Lambda processes the order.

8. If processing succeeds, the message is removed from the SQS queue.

9. If processing fails, the message becomes available for another processing attempt.

10. Messages that repeatedly fail processing can later be moved to a dead-letter queue.

## Flow Summary

**Customer → API Gateway → Order Submission Lambda → Amazon SQS → Order Processor Lambda**

Amazon SQS decouples order submission from order processing. This allows accepted orders to remain available even if the processing component is temporarily unavailable.