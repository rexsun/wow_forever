# ComponentManager.lua

Component registry (`private.ComponentManager`).

API: `RegisterComponent()`, `UnregisterComponent()`, `EnableComponent`/`DisableComponent`, `GetComponent`, `GetAllComponents`, `RefreshAllComponents`. Fires `OnComponentEnable`/`OnComponentDisable`.

**`RefreshAllComponents` does not catch.** It raises `private.fontsDirty`, walks the register order
calling each `Refresh()`, then lowers the flag. A throwing component aborts the pass: every
component registered after it is skipped, and `fontsDirty` stays pinned at `true` — the flag that
gates every component's expensive per-child styling pass on the combat refresh path
(`.context/patterns.md` "fontsDirty"). That is deliberate. The addon does not wrap its own code in
`pcall`; an error here is a real defect and must be loud rather than absorbed into a degraded
session that looks merely slow.

