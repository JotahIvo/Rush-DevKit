# Integration Map (fixture: journey without test)

Synthetic map where a journey declares no `test` field. Used to prove
`validate-integration-map.sh` catches `journey_without_test` instead of shipping a journey nobody
verifies. Not a real project.

```json
{
  "features": [
    {
      "id": "004-notify",
      "title": "Notifications",
      "provides": [
        { "kind": "event", "name": "notification.sent", "contract": "specs/shared-contracts/notify.md#sent" }
      ],
      "consumes": [],
      "depends_on": []
    }
  ],
  "shared_contracts": [],
  "journeys": [
    {
      "id": "order-confirmation",
      "description": "an order confirmation notification is sent",
      "features": ["004-notify"]
    }
  ]
}
```
