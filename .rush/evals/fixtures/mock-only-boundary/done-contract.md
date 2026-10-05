# Done Contract: Order Totals (every check mocks the other side of the boundary)

## Acceptance Criteria

1. GET /orders/{id}/total returns 200 with `total_cents` including tax for a known order.
2. GET /orders/{id}/total returns 404 for an unknown order.
3. GET /orders/{id}/total returns 503 when the tax service is unavailable.

## Definition of Done

```json
{
  "checks": [
    { "name": "unit tests", "run": "npm test -- tests/unit/order-total.test.ts --mock-tax-client", "expect": "exit 0" },
    { "name": "contracts valid", "run": ".rush/scripts/validate-contracts.sh 001-order-totals", "expect": "exit 0" }
  ],
  "human_gates": ["assisted review completed (/rush-review)"]
}
```

## Acceptance Criteria Coverage

| Acceptance Criterion | Enforced By |
|---|---|
| 1 | unit tests |
| 2 | unit tests |
| 3 | unit tests |
