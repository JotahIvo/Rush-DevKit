# Spec: Order Totals (deliberately verified only against mocks)

Synthetic fixture for the rush-analyze eval suite. Not a real feature.

## Behaviour

The system returns an order's total, in cents, including tax.

## Interfaces

### Provides

- `endpoint` **GET /orders/{id}/total** — consumed by `002-checkout` on the checkout journey.

### Consumes

- `endpoint` **GET /tax-rates/{region}** — provided by `003-tax`.

## Data

- Total: integer cents, computed on request, not persisted.

## Edge Cases & Failure Modes

- Unknown order → 404.
- Tax service unavailable → 503.

## Out of Scope

- Currency conversion.
