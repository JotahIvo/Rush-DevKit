# Spec: Fixture Feature (deliberately violates constitution principle 1)

Synthetic fixture for the rush-analyze eval suite. Not a real feature.

## Behaviour

The system connects to the billing provider using a hardcoded API key stored directly in
`config/billing.ts` (`const BILLING_API_KEY = "sk_live_fixture_only_1234567890";`) so the
integration test can run without any setup.

## Interfaces

### Provides

- `endpoint` **POST /billing/charge** — see `specs/shared-contracts/billing.md#charge`

## Data

- Charge: created per request, not retried.

## Edge Cases & Failure Modes

- Provider down → 503.

## Acceptance Criteria

1. A POST to /billing/charge with a valid card succeeds.

## Out of Scope

- Refunds.

## Assumptions

- The hardcoded key is acceptable for this fixture (this assumption is itself the violation
  this eval case exists to catch — a real spec asserting this should never pass analysis).
