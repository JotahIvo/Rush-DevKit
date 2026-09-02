<!-- DONE-CONTRACT artifact: the executable Definition of Done, together with the acceptance
     criteria it enforces — one document instead of two, so a criterion and the thing that proves
     it can never drift apart. Density over completeness: a done-contract with checks nobody
     trusts gets bypassed instead of fixed. -->
<!-- Negotiated with the user before any code is written. Filled by /rush-spec, executed by
     .rush/scripts/done-check.sh. Location: specs/{{FEATURE_ID}}/done-contract.md -->

# Done Contract: {{FEATURE_TITLE}}

## Acceptance Criteria

<!-- Numbered, each testable, written as the test you would run. Every criterion below must have
     a row in the Coverage table mapping it to a check name or a human gate — a criterion mapped
     to neither will not be enforced by anything. -->
1. {{ACCEPTANCE_CRITERION_1}}
2. {{ACCEPTANCE_CRITERION_2}}

## Definition of Done

<!-- `run` must be a real, already-working command — done-check.sh executes it verbatim, it
     never reimplements what it does. `expect` supports: "exit 0", "exit N",
     "contains: <text>", "not_contains: <text>". Keep `human_gates` to things a script
     genuinely cannot verify (e.g. a design review), not a dumping ground for lazy checks. -->

```json
{
  "checks": [
    { "name": "{{CHECK_NAME_1}}", "run": "{{CHECK_COMMAND_1}}", "expect": "exit 0" },
    { "name": "contracts valid", "run": ".rush/scripts/validate-contracts.sh {{FEATURE_ID}}", "expect": "exit 0" },
    { "name": "fitness functions", "run": ".rush/scripts/fitness.sh {{FEATURE_ID}}", "expect": "exit 0" },
    { "name": "no spec drift", "run": ".rush/scripts/check-as-built.sh {{FEATURE_ID}}", "expect": "exit 0" }
  ],
  "human_gates": [
    "{{HUMAN_GATE_DESCRIPTION_1}}"
  ]
}
```

## Acceptance Criteria Coverage

<!-- Traceability table: every acceptance-criterion number above maps to one check name or one
     human gate. No blank rows. -->

| Acceptance Criterion | Enforced By |
|---|---|
| {{AC_NUMBER_1}} | {{CHECK_NAME_OR_HUMAN_GATE_1}} |
| {{AC_NUMBER_2}} | {{CHECK_NAME_OR_HUMAN_GATE_2}} |
