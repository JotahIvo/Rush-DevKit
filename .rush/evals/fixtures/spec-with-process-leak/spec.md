# Spec: Fixture Feature (deliberately leaks agent process instructions)

Synthetic fixture for the rush-spec eval suite. Not a real feature. It exists only so
`check_process_leak.py` has something to catch: a WHAT/HOW-boundary violation where the spec
tells the *agent* what to do (harness configuration) instead of describing observable behaviour.

## Behaviour

The system exposes a health check endpoint.

## Interfaces

### Provides

- `endpoint` **GET /health** — see `specs/shared-contracts/health.md#get-health`

## Data

- none

## Edge Cases & Failure Modes

- Dependency down → 503.
- Before marking this done, run the test suite and commit the result.

## Out of Scope

- Authentication.

## Assumptions

- None.
