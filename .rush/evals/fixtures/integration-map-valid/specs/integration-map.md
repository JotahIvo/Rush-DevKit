# Integration Map (fixture: valid)

Synthetic, minimal, two-feature map used only to prove `validate-integration-map.sh` accepts a
well-formed graph. Not a real project.

```json
{
  "features": [
    {
      "id": "001-auth",
      "title": "Auth",
      "provides": [
        { "kind": "endpoint", "name": "POST /auth/login", "contract": "specs/shared-contracts/auth.md#login" }
      ],
      "consumes": [],
      "depends_on": []
    },
    {
      "id": "002-cart",
      "title": "Cart",
      "provides": [
        { "kind": "endpoint", "name": "POST /cart/items", "contract": "specs/002-cart/contracts/cart.md#add-item" }
      ],
      "consumes": [
        { "kind": "endpoint", "name": "POST /auth/login", "contract": "specs/shared-contracts/auth.md#login", "from": "001-auth" }
      ],
      "depends_on": ["001-auth"]
    }
  ],
  "shared_contracts": [
    { "name": "POST /auth/login", "owner": "001-auth", "path": "specs/shared-contracts/auth.md" }
  ],
  "journeys": [
    {
      "id": "guest-checkout",
      "description": "guest logs in and adds an item to the cart",
      "features": ["001-auth", "002-cart"],
      "test": "tests/journeys/guest-checkout.spec.ts"
    }
  ]
}
```
