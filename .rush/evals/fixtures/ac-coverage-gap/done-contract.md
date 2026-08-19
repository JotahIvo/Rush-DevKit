# Done Contract: Fixture Feature (deliberately missing AC 3's coverage row)

## Acceptance Criteria

1. A GET to /report returns 200 with a report body when data exists.
2. A GET to /report returns 204 when no data exists.
3. A GET to /report from an unauthenticated caller returns 401.

## Definition of Done

```json
{
  "checks": [
    { "name": "acceptance tests", "run": "true", "expect": "exit 0" },
    { "name": "contracts valid", "run": "true", "expect": "exit 0" }
  ],
  "human_gates": []
}
```

## Acceptance Criteria Coverage

| Acceptance Criterion | Enforced By |
|---|---|
| 1 | acceptance tests |
| 2 | acceptance tests |
