<!-- PRODUCT artifact: durable context about the product itself, revisited rarely — not about
     any one feature. No technology and no per-feature detail; those drift into pitch/PRD
     territory below and go stale fast if duplicated here. -->
<!-- Filled by /rush-init, updated only when the product itself changes shape.
     Location: .rush/memory/product.md -->

# Product: {{PRODUCT_NAME}}

## What It Is

<!-- One paragraph: what a stranger needs to know before reading any spec in this repo. -->
{{PRODUCT_DESCRIPTION}}

## Who It Serves

<!-- Real user segments/personas actually observed, not a market slide. -->
- {{USER_SEGMENT_1}}
- {{USER_SEGMENT_2}}

## Current Stage

<!-- Pre-launch, MVP live, scaling, maintenance, sunset, etc. This changes over the product's
     life — revisit it each time it stops being true, don't leave it stale. -->
{{CURRENT_STAGE}}

## What Must Never Break

<!-- Invariants no change is allowed to violate — the thing that, if it broke, would be a
     crisis regardless of what else shipped that day. -->
- {{INVARIANT_1}}
- {{INVARIANT_2}}

## What Matters Most Right Now

<!-- The current priority, in one or two sentences. This is what an agent should optimise for
     when a trade-off elsewhere in the docs isn't spelled out. -->
{{CURRENT_PRIORITY}}
