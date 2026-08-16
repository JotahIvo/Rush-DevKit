# Spec: Fixture Feature (deliberately over budget)

<!-- This fixture exists only to exercise validate-artifacts.sh's budget rule for the
     rush-spec eval suite. It is not a real feature. Synthetic, obviously so. -->

## Behaviour

The system does something observable for the purpose of this fixture.

## Interfaces

### Provides

- `endpoint` **GET /fixture** — see `specs/shared-contracts/fixture.md#get-fixture`

### Consumes

- `endpoint` **POST /auth/login** from `001-auth` — see `specs/shared-contracts/auth.md#login`

## Data

- FixtureEntity: owned by this feature, created on request, never deleted.

## Edge Cases & Failure Modes

- Invalid input → 400 with a field-level error.
- Dependency down → 503, retried once.

## Acceptance Criteria

1. A GET to /fixture returns 200 with a FixtureEntity payload.
2. An invalid request returns 400.

## Out of Scope

- Anything not GET /fixture.

## Assumptions

- The caller is already authenticated.

## Padding

<!-- The lines below exist only to push this fixture past the 150-line spec budget on
     purpose, so the eval can assert that validate-artifacts.sh catches it. -->
- padding line 1: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 2: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 3: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 4: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 5: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 6: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 7: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 8: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 9: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 10: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 11: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 12: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 13: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 14: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 15: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 16: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 17: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 18: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 19: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 20: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 21: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 22: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 23: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 24: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 25: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 26: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 27: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 28: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 29: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 30: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 31: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 32: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 33: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 34: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 35: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 36: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 37: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 38: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 39: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 40: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 41: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 42: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 43: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 44: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 45: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 46: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 47: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 48: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 49: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 50: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 51: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 52: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 53: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 54: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 55: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 56: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 57: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 58: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 59: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 60: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 61: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 62: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 63: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 64: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 65: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 66: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 67: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 68: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 69: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 70: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 71: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 72: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 73: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 74: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 75: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 76: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 77: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 78: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 79: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 80: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 81: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 82: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 83: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 84: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 85: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 86: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 87: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 88: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 89: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 90: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 91: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 92: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 93: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 94: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 95: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 96: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 97: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 98: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 99: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 100: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 101: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 102: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 103: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 104: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 105: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 106: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 107: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 108: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 109: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 110: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 111: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 112: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 113: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 114: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 115: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 116: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 117: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 118: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 119: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 120: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 121: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 122: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 123: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 124: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 125: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 126: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 127: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 128: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 129: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 130: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 131: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 132: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 133: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 134: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 135: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 136: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 137: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 138: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 139: this fixture spec is intentionally verbose to exceed the 150-line budget.
- padding line 140: this fixture spec is intentionally verbose to exceed the 150-line budget.
