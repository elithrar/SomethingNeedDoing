# Changelog

## 0.3.0

- Deliver scoped logout callbacks before disposal, once, while committed settings are readable. Callback and panel-close errors cannot prevent runtime cancellation.
- Activate font tracking on first use; keep measurements passive. Guard media callbacks, recover partial registration and release replaced receivers.
- Register layout listeners only for active handles and unwind partial attachment failures.
- Keep the public API unchanged. Consolidate executable consumer checks under tests and remove historical audit reports and duplicate test documentation.


## 0.2.0

Breaking changes from the Lua correctness and developer-experience review:

- Fallible resource APIs (`Slash`, scoped events/hooks/timers, and layout helpers) now return `true, handle` or `false, error`. Previously they returned a handle or nil. Commands retain their boolean first result; successful commands have no payload.
- Both settings adapter methods return `true, { state = ..., saved = ... }` or `false, error`. Restore previously returned state and saved data separately; Prepare returned the candidate directly. Read-only restoration may omit saved data.
- Ordered declarations must be dense arrays. Scope names, revisions, timer keys, schema bounds and profile descriptors now reject malformed arguments explicitly. Validators require literal true for acceptance.
- Bound settings must be declared before Options; incompatible control/field types and missing slider bounds fail before panel registration.
- Declaration and adapter tables are copied at registration. Mutate settings through their commands; do not alter an options spec or adapter method table after registration. Callback upvalues remain consumer-owned.

Validated fixes:

- A selector returning extra Lua values could pass them into the snapshot copier's private arguments. Only the first result is now consumed.
- Sparse lists were silently truncated by ipairs. Invalid declarations now fail before registration and permit a corrected retry.
- Options/adapter tables were retained by reference. Later caller edits could corrupt an already registered panel or restoration path.
- Arbitrary error objects could invoke a throwing __tostring outside the recovery boundary. Errors are now normalized into fresh string-only records without metamethod invocation.
- Profile descriptors and non-finite/index arguments could fail deep inside unrelated code. They are checked at their boundaries.
- The example persistence adapter treated a saved false as missing data. It now preserves that invalid record and exposes read-only defaults.
- Immediate native event registration failures now return a failed Result, rather than a canceled handle that looked successful.
- Cleanup errors are reported without interrupting remaining owned cleanup.

Thirteen focused contract tests and the three real-runtime consumer mocks pass under Lua 5.1. Each focused test records its failure-risk justification in tests/run.lua. Native WoW acceptance remains outstanding.

## 0.1.0

Initial implementation of reactive state, settings/profile adapters, owned callbacks,
options panels, fonts, geometry and memory-only diagnostics.
