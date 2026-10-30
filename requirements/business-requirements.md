# Business Requirements

## Overview

QuickCart GmbH needs a reliable and scalable order-processing system. The new solution should use asynchronous processing so that customer orders are not lost when the processing system is temporarily unavailable or overloaded.

## Business Requirements

1. The system must accept customer order requests.

2. Accepted orders must be stored reliably until they can be processed.

3. The customer-facing application should not depend directly on the availability of the order-processing component.

4. The system must be able to handle sudden increases in order traffic.

5. Orders should be processed asynchronously.

6. Failed order-processing attempts should be retried.

7. Permanently failing messages should not interfere with normal order processing.

8. The system should provide visibility into the number of orders waiting to be processed.

9. The system should provide logging and monitoring of order-processing activity.

10. The solution should follow AWS security best practices.

11. The architecture should remain simple and cost-conscious.

12. The solution should be small enough to implement as a working AWS project.

13. The infrastructure should be structured so that it can later be managed using Terraform.