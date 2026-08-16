# Constitution: Fixture Project (excerpt)

Synthetic excerpt for the rush-analyze eval suite. Not a real project's constitution.

## Principles

### 1. No plaintext secrets in source (MUST)

The codebase MUST NOT store API keys, passwords or tokens in plaintext in any file tracked by
git. All secrets are read from environment variables or a secrets manager at runtime.

**Why**: a plaintext key committed to history stays leaked even after deletion.

## Governance

### Enforcement

A `MUST` principle violated by an artifact or by generated code **blocks feature close** until
resolved or the constitution is amended through the process above.
