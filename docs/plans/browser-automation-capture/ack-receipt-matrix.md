# Synthetic mutation receipt matrix

`tests/capture/ack-receipt-cases.json` is decoded as JSON and supplied to the
actual native receipt validator with its `expectedToken`. It specifies the
synthetic-coordinate callback used by WebKit adapters; native CDP input has
its own acknowledgement and provenance contract.

A successful receipt needs a nonempty matching token, `ok: true`,
`mayHaveCompleted: true`, the exact input guarantee, both privacy fields as
JSON booleans, and no error field. A refusal needs `ok: false`, a nonempty
error and explicit Boolean completion and privacy fields. Contradictory,
missing or mistyped fields are malformed. A malformed callback after a
mutation is uncertain and must never be retried automatically.

`known-positive` means a true sensitivity observation is retained even when
other metadata is unknown. `known-negative` requires false sensitivity and
true sensitivityKnown. All other observations are unknown; malformed
metadata must protect the full attempted literal and discard capture.
Privacy is consumed in the callback before any later authority or document
guard can replace its result.

After a valid final mutation acknowledgement, unknown privacy permits
uncaptured completion only with full-literal redaction; capture is discarded
and refused. Before another scalar, unknown stops input. An absent, failed or
malformed mutation callback remains uncertain even on the final scalar.
Known-negative ordinary text remains available in named outputs.

Platform tests must exercise these cases through their actual JSON decoder and
receipt validator, and separately cover callback ordering, loss of authority,
navigation, cancellation and partial input with native execution.
