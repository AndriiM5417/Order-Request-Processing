# Architecture Decisions

## Overview

The goal of the architecture is to build a reliable asynchronous order-processing system for QuickCart GmbH.

The main architectural requirement is that an accepted order should not be lost if the order-processing component is temporarily unavailable or overloaded.

---

## Synchronous vs Asynchronous Processing

### Synchronous Processing

In a synchronous architecture, the customer-facing application sends an order directly to the order-processing component and waits for the processing result.

**Advantages:**

- Simple request flow.
- Immediate processing result.

**Disadvantages:**

- The customer-facing application depends directly on the availability of the order processor.
- Slow processing can make the application slower.
- If the processor is unavailable, the order request may fail.
- Sudden traffic increases can overload the processor.
- The producer and consumer are tightly coupled.

### Asynchronous Processing

In an asynchronous architecture, the order request is first placed into a message queue. The order processor consumes the message later when processing capacity is available.

**Advantages:**

- The producer and consumer are decoupled.
- Orders can remain in the queue while the processor is temporarily unavailable.
- Traffic spikes can be buffered by the queue.
- Failed processing attempts can be retried.
- The processing component can scale independently.

**Disadvantages:**

- Processing is not immediate.
- The architecture contains additional components.
- Retry behavior and failed messages must be managed.

### Decision

The asynchronous approach is selected because the project requires asynchronous order processing and reliable storage of accepted orders until they can be processed.

---

## Architecture Option 1 — API Gateway + Lambda + SQS + Lambda

### Flow

Customer  
→ API Gateway  
→ Order Submission Lambda  
→ Amazon SQS  
→ Order Processor Lambda  
→ Processing Result

### Services

- **Amazon API Gateway** provides an HTTP endpoint for order submission.
- **AWS Lambda** handles the incoming order request.
- **Amazon SQS** stores order messages until they can be processed.
- **AWS Lambda** processes messages from the queue.
- **Amazon CloudWatch** provides logs and monitoring.
- **AWS IAM** controls permissions between services.

### Advantages

- Fully managed AWS architecture.
- Clear separation between order submission and processing.
- Easy to scale.
- No servers need to be managed.
- SQS provides buffering between the producer and consumer.

### Limitations

- More AWS components must be configured.
- API Gateway introduces an additional service.
- Processing is asynchronous, so the final result is not returned immediately.

---

## Architecture Option 2 — Application Backend + SQS + Lambda

### Flow

Customer  
→ Application Backend  
→ Amazon SQS  
→ Order Processor Lambda  
→ Processing Result

### Services

- The existing application backend accepts the order request.
- **Amazon SQS** stores the order message.
- **AWS Lambda** processes messages from the queue.
- **Amazon CloudWatch** provides logging and monitoring.
- **AWS IAM** controls access between AWS services.

### Advantages

- Simpler architecture.
- Fewer AWS services are required.
- The queue still provides decoupling and buffering.
- Lower architectural complexity.

### Limitations

- The application backend must already provide the order-submission interface.
- The backend remains responsible for receiving customer requests.
- The architecture is less serverless than Option 1 if the backend runs on a managed server or container.

---

## Selected Architecture

The initial selected architecture is **Option 1: API Gateway + Lambda + SQS + Lambda**.

The main reason is that it provides a clear, fully managed AWS architecture and demonstrates the complete asynchronous message flow.

The proposed flow is:

**Customer → API Gateway → Order Submission Lambda → SQS → Order Processor Lambda**

Amazon SQS acts as the buffer between the order-submission component and the order-processing component.

If the processor is temporarily unavailable, the order message can remain in the queue until processing is available again.

---

## AWS Service Decisions

### Amazon SQS

Amazon SQS is selected as the message queue.

It provides:

- Message buffering.
- Decoupling between producer and consumer.
- Reliable temporary message storage.
- Retry support.
- Integration with AWS Lambda.

A dead-letter queue will later be used for messages that repeatedly fail processing.

### AWS Lambda

AWS Lambda is selected for order submission and order processing because it is a managed, event-driven compute service.

It allows the system to:

- Process events without managing servers.
- Scale automatically.
- Integrate with Amazon SQS.
- Keep the architecture small and simple.

### Amazon CloudWatch

Amazon CloudWatch is selected for:

- Application logs.
- Processing logs.
- Queue and Lambda monitoring.
- Troubleshooting.

### AWS IAM

AWS IAM is required to control access between AWS services.

Permissions should follow the principle of least privilege.

### Amazon API Gateway

Amazon API Gateway is included in the initial architecture to provide an HTTP endpoint for customer order requests.

It is not required for the queue itself, but it provides a clear entry point into the serverless architecture.

---

## Cost Considerations

The architecture is designed to remain small and cost-conscious.

Managed and serverless AWS services are preferred so that resources are mainly used when requests are received and processed.

The project will avoid unnecessary AWS services and keep the implementation focused on the required architecture.