
# Assumptions & Constraints

## Assumptions

1. Orders do not need to be processed immediately.

2. An accepted order may wait for a short period before being processed.

3. The order-processing component may sometimes be temporarily unavailable.

4. Order traffic may increase suddenly during busy periods.

5. The solution will use AWS managed services for the main architecture.

6. The exact AWS service combination will be selected and justified based on the project requirements.

## Constraints

1. The architecture must demonstrate decoupling between order submission and order processing.

2. The project should remain intentionally small and simple.

3. The solution should be cost-conscious and designed with AWS Free Tier considerations in mind.

4. Only AWS services that are relevant to the project requirements should be used.

5. Terraform should be used for the implemented infrastructure where practical.

6. The Terraform configuration does not need to include every possible AWS configuration.

7. The project must be completed within the four-week project period.
