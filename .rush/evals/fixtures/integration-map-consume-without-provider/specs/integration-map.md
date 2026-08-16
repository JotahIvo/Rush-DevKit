# Integration Map (fixture: consume without provider)

Synthetic map where one feature consumes an interface with no declared `from` provider. Used to
prove `validate-integration-map.sh` catches `consume_without_provider` instead of silently
letting the gap through. Not a real project.

```json
{
  "features": [
    {
      "id": "003-checkout",
      "title": "Checkout",
      "provides": [
        { "kind": "endpoint", "name": "POST /checkout", "contract": "specs/003-checkout/contracts/checkout.md#pay" }
      ],
      "consumes": [
        { "kind": "endpoint", "name": "POST /payments/charge" }
      ],
      "depends_on": []
    }
  ],
  "shared_contracts": [],
  "journeys": [
    {
      "id": "pay-for-order",
      "description": "checkout charges the order",
      "features": ["003-checkout"],
      "test": "tests/journeys/pay-for-order.spec.ts"
    }
  ]
}
```
