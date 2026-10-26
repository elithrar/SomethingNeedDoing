# Focused verification

`run.lua` uses `wow.lua` only at the native boundary. Each test supplies a short justification printed with its result. These are behavioral contracts, not coverage targets.

| Test | Why it exists |
| --- | --- |
| State transactions | A failed update, retained draft or reentrant write must not corrupt committed state. |
| Watch lifecycle | Hidden views must detach; one failed/canceling subscriber must not corrupt dispatch. |
| Settings restoration | Restoration timing and unknown future schemas are user-data safety boundaries. |
| Adapter atomicity | Invalid output must not partially replace multiple SavedVariables or mutate the live adapter state. |
| Scope scheduling and hooks | Repeated ownership changes must not retain callbacks, stack hooks or leave an idle driver. |
| Options editor ownership | Native hide-before-accept and stale picker callbacks can otherwise write the wrong settings. |
| Options construction and menu lifetime | Constructor retries must reuse frames, and native menus must keep input ownership during refresh. |
| Font and geometry boundaries | Native void/fractional font results and effective scales differ from naive Lua assumptions. |
| Diagnostics and instance isolation | Bounded logs, slash collisions and independently embedded instances need explicit ownership. |

The separate `exercises/run.lua` loads actual consumer domain modules and uses the real runtime with consumer-specific profile adapters and mock views. It justifies the generalization boundary; it is not a duplicate state implementation. See the root exercise report for evidence and remaining native checks.
