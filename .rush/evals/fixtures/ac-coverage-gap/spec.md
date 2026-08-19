# Spec: Fixture Feature (deliberately has an uncovered acceptance criterion)

Synthetic fixture shared by the rush-spec and rush-analyze eval suites. Not a real feature.

## Behaviour

The system exports a report on request.

## Interfaces

### Provides

- `endpoint` **GET /report** — see `specs/shared-contracts/report.md#get-report`

## Data

- Report: generated on demand, not persisted.

## Edge Cases & Failure Modes

- No data available → 204.

## Out of Scope

- Scheduled report generation.

## Assumptions

- The caller is already authenticated for criteria 1 and 2.
