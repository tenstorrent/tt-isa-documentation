# PIC

The PIC (programmable interrupt controller) can:
* Track 11 different IRQs, allowing hardware to atomically raise an IRQ, and allowing software to atomically clear an IRQ.
* Optionally stop RISCV NC's clock when there are no IRQs pending (or, in Ethernet tiles, optionally stop RISCV E's clock).

> [!NOTE]
> There is no support in Wormhole for actually interrupting any RISCV core in response to an IRQ. Instead, RISCV cores need to poll for pending IRQs. In the case of RISCV NC or RISCV E, this polling can optionally be combined with stopping of the RISCV clock when there are no IRQs pending.

## IRQs

The 11 recognized IRQs are:

|Index|Raised by|Enabled if|
|--:|---|---|
|0 - 3|NoC Overlay [stream 0 - 3, upon phase start or phase end or both](../NoC/Overlay/README.md#stream-state-machine)|`PIC_ENABLE.Bit[i]` and<br/>`PIC_STREAM_IRQ_TYPE[i] != 0`|
|4 - 7|NoC Overlay [stream 8 - 11, upon phase start or phase end or both](../NoC/Overlay/README.md#stream-state-machine)|`PIC_ENABLE.Bit[i]` and<br/>`PIC_STREAM_IRQ_TYPE[i] != 0`|
|8 - 15|Not used|`PIC_ENABLE.Bit[i]`|
|16|NoC Overlay when [`STREAM_BLOB_AUTO_CFG_DONE_REG_INDEX`](../NoC/Overlay/LoadConfigurationFromL1.md) non-zero|`PIC_ENABLE.Bit[16]`|
|17|[Debug timestamper](DebugTimestamper.md) when `bufs0_full` (not available in Ethernet tiles)|`PIC_ENABLE.Bit[17]`|
|18|[Debug timestamper](DebugTimestamper.md) when `bufs1_full` (not available in Ethernet tiles)|`PIC_ENABLE.Bit[18]`|
|19 - 31|Not used|Never|

All IRQs are edge triggered: when the relevant condition transitions from `false` to `true`, the IRQ will be added to the pending set if it is enabled. Once software subsequently clears it from the pending set, it'll only be added again when it next transitions from `false` to `true`. Software accesses the pending set via `PIC_STATUS`.

## Clock gating

The local RISCV NC or RISCV E will have its clock running if any of the following happened in the previous `PIC_CLKGT.HYST` cycles:
* `PIC_CLKGT.GATING_ENABLED` was `false` (which is its default value).
* `PIC_CLKGT.FORCE_ACTIVE` was `true`.
* Any IRQ was pending (i.e. reading from `PIC_STATUS` would have returned a non-zero value).
* Any agent performed a read or write against any of the PIC's memory-mapped registers.
* Assorted other miscellaneous events (i.e. this is not an exhaustive list).

If software wishes to stop the clock other than when servicing IRQs, it should:
1. Set `PIC_CLKGT.HYST` to a suitable value (the default value is 3 cycles, which is slightly aggressive, but may be suitable).
2. Set `PIC_CLKGT.GATING_ENABLED` to `true` and `PIC_CLKGT.FORCE_ACTIVE` to `false`.
3. Before clearing bits in `PIC_STATUS`, set `PIC_CLKGT.FORCE_ACTIVE` to `true`.
4. After servicing the cleared bits of `PIC_STATUS`, set `PIC_CLKGT.FORCE_ACTIVE` back to `false`.

Note that software is free to use the IRQ raising and clearing features of the PIC without having to use the clock gating features.

## Memory Map

|Name|Address|Software access|Purpose|
|---|---|---|---|
|`PIC_STATUS`|`0xFFB1_3000`|Read to query,<br/>write to clear|Bitmask of pending IRQs|
|`PIC_NEXT_IRQ`|`0xFFB1_3004`|Read only<br/>(but with side effects)|Repeated reads iterate through the indices of pending IRQs|
|`PIC_ENABLE`|`0xFFB1_3008`|Read / write|Bitmask of enabled IRQs|
|`PIC_CLKGT_EN`|`0xFFB1_300C`|Some bits read only, others read / write|[Clock gating](#clock-gating)|
|`PIC_CLKGT_HYST`|`0xFFB1_3010`|Read / write|[Clock gating](#clock-gating)|
|`PIC_STREAM_IRQ_TYPE[i]`|<code>0xFFB1_3014&nbsp;+&nbsp;i*4</code><br/>(for `0 ≤ i < 8`)|Read / write|Controls whether phase start or phase end (or both) should raise an IRQ|

### `PIC_STATUS`

Reading from `PIC_STATUS` returns the bitmask of pending IRQs, and does not modify any state in any way.

Writing to `PIC_STATUS` will atomically clear the specified bits from the bitmask of pending IRQs. If an IRQ is not pending, then clearing it has no effect.

It is expected that software will read from `PIC_STATUS`, and if the returned value is non-zero, write the value back to `PIC_STATUS` and then service all of the set bits.

### `PIC_NEXT_IRQ`

If `PIC_STATUS` is non-zero, then reading from `PIC_NEXT_IRQ` will return the _index_ of one of the set bits. Reading from `PIC_NEXT_IRQ` does not affect `PIC_STATUS` in any way, but reading from `PIC_NEXT_IRQ` _does_ affect some internal state relating to `PIC_NEXT_IRQ`: if multiple bits of `PIC_STATUS` are set, then repeated reads of `PIC_NEXT_IRQ` will iterate through the set bits.

If `PIC_STATUS` is zero, then reading from `PIC_NEXT_IRQ` will return zero. When IRQ #0 is enabled, this causes a read result of zero to be ambiguous: it can mean that `PIC_STATUS` is zero, or it can mean that the least significant bit of `PIC_STATUS` is set.

### `PIC_ENABLE`

`PIC_ENABLE` is a bitmask of enabled IRQs. It is initially zero, and then software can set bits corresponding to the IRQs it cares about.

### `PIC_CLKGT_EN`

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|1|`PIC_CLKGT.GATING_ENABLED`|Set to `true` to enable clock gating (when `false`, gating is disabled, i.e. the clock is always running).|
|1|7|Reserved|Writes ignored, reads as zero.|
|8|1|`PIC_CLKGT.FORCE_ACTIVE`|When clock gating is enabled, set to `true` to force the clock to be running. No effect when `PIC_CLKGT.GATING_ENABLED` is `false`.|
|9|7|Reserved|Writes ignored, reads as zero.|
|16|1|`PIC_CLKGT.ACTIVE`|Read-only. Reads as `true` if the local RISCV NC / E clock is running, `false` otherwise. The local RISCV NC / E will always observe `true`; it is only other agents who are able to observe `false`.|
|17|15|Reserved|Writes ignored, reads as zero.|

### `PIC_CLKGT_HYST`

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|7|`PIC_CLKGT.HYST`|The number of cycles for which the clock should remain running after an interesting event|
|7|25|Reserved|Writes ignored, reads as zero|

### `PIC_STREAM_IRQ_TYPE`

There are eight copies of this register; `PIC_STREAM_IRQ_TYPE[0]` through `PIC_STREAM_IRQ_TYPE[3]` correspond to NoC Overlay streams 0 through 3, whereas `PIC_STREAM_IRQ_TYPE[4]` through `PIC_STREAM_IRQ_TYPE[7]` correspond to streams 8 through 11. Other stream numbers are not able to raise IRQs.

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|1|Phase start|If `true`, when the corresponding stream starts a phase, an IRQ is raised|
|1|1|Phase end|If `true`, when the corresponding stream ends a phase, an IRQ is raised|
|2|30|Reserved|Writes ignored, reads as zero|

Note that `PIC_ENABLE.Bit[i]` needs to be set in addition to `PIC_STREAM_IRQ_TYPE[i]`.
