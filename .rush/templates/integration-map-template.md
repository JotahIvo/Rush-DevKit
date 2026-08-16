<!-- INTEGRATION-MAP artifact: the cement between features — who provides/consumes what, and
     the journeys that cross feature boundaries. No budget declared in script-interfaces.md;
     keep it derivable from the specs, never a place to redesign a feature. -->
<!-- Filled/updated by /rush-features and /rush-spec, validated by
     .rush/scripts/validate-integration-map.sh. Location: specs/integration-map.md -->

# Integration Map

<!-- One or two sentences of orientation for a human skimming this before the JSON below. -->
{{INTRO_NOTE}}

## Features & Journeys

<!-- `provides`/`consumes` kind is one of: endpoint | event | component | data | module.
     Each entry: {"kind","name","contract":"path#pointer","from"} — `from` only appears on a
     `consumes` entry and names the feature-id expected to provide it. `depends_on` lists
     feature ids this feature cannot be implemented before. -->

```json
{
  "features": [
    {
      "id": "{{FEATURE_ID}}",
      "title": "{{FEATURE_TITLE}}",
      "provides": [
        { "kind": "endpoint", "name": "{{PROVIDED_NAME}}", "contract": "{{CONTRACT_PATH}}#{{POINTER}}" }
      ],
      "consumes": [
        { "kind": "endpoint", "name": "{{CONSUMED_NAME}}", "contract": "{{CONTRACT_PATH}}#{{POINTER}}", "from": "{{PROVIDING_FEATURE_ID}}" }
      ],
      "depends_on": ["{{DEPENDENCY_FEATURE_ID}}"]
    }
  ],
  "journeys": [
    {
      "id": "{{JOURNEY_ID}}",
      "description": "{{JOURNEY_DESCRIPTION}}",
      "features": ["{{FEATURE_ID}}"],
      "test": "{{TEST_COMMAND_OR_PATH}}"
    }
  ]
}
```

## Rules Enforced by `validate-integration-map.sh`

<!-- Documentation of what the script already checks — do not invent new rules here, and do not
     restate them differently than the script does. This exists so a human editing the JSON by
     hand knows the constraints before running the validator. -->
- Every `consumes` entry must resolve to a `provides` entry of the same `kind`+`name` on the
  feature named in `from` (`consume_without_provider`).
- No two features may `provide` the same `kind`+`name` (`duplicate_provider`).
- `depends_on` edges must not form a cycle (`dependency_cycle`).
- Every id in a journey's `features` must exist among `features[].id`
  (`journey_missing_feature`, `unknown_feature_ref`).
- Every journey must declare a non-empty `test` (`journey_without_test`).
