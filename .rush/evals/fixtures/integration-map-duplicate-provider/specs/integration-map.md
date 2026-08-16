# Integration Map (fixture: duplicate provider)

Synthetic map where two features both `provide` the same interface instead of one owning it via
`shared_contracts`. Used to prove `validate-integration-map.sh` catches `duplicate_provider`.
Not a real project.

```json
{
  "features": [
    {
      "id": "005-users-a",
      "title": "Users A",
      "provides": [
        { "kind": "endpoint", "name": "POST /users", "contract": "specs/005-users-a/contracts/users.md#create" }
      ],
      "consumes": [],
      "depends_on": []
    },
    {
      "id": "005-users-b",
      "title": "Users B",
      "provides": [
        { "kind": "endpoint", "name": "POST /users", "contract": "specs/005-users-b/contracts/users.md#create" }
      ],
      "consumes": [],
      "depends_on": []
    }
  ],
  "shared_contracts": [],
  "journeys": []
}
```
