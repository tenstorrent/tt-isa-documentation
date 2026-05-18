# GDB/Debug Interface

Each of RISCV (B, T0, T1, T2) has a GDB/Debug interface, which allows an external agent to:
* Bring the core to a pause, and then either single-step it or resume it.
* When paused, read `pc` and read / write the GPRs `x1` through `x31` (`x0` is also readable, but it always contains zero, and is not writable).
* When paused, issue memory loads / stores as if they were issued by the core. Notably, this allows an external agent to inspect [RISCV local data RAM](README.md#local-data-ram).
* Place up to eight hardware breakpoints / memory watchpoints.

This interface is intended for use by debuggers such as GDB or [TT-ExaLens](https://github.com/tenstorrent/tt-exalens), but it is not specific to GDB in any way.

Unfortunately, RISCV NC does not have a GDB/Debug interface (`ebreak` and `ecall` instructions executed by RISCV NC will still pause the core _as if_ it had a GDB/Debug interface, but the only way out from this is a [soft reset](../SoftReset.md#riscv-soft-reset)). The [debug daisychain](../DebugDaisychain.md#riscv-execution-state) can still be used to obtain an approximate `pc` from RISCV NC.

## Debug registers

Each RISCV has 14 32-bit debug registers:

||Purpose|Software access|Hardware access|
|---|---|---|---|
|**`DR(0)`**|[Status bitmask](#status-bitmask)|Read-only (writes discarded)|Write-only|
|**`DR(1)`**|[Command and control bitmask](#command-and-control-bitmask)|Read/write, write can cause effect|Read-only|
|**`DR(2)`**|Command argument 0 (index or address)|Read/write|Read-only|
|**`DR(3)`**|Command argument 1 (data)|Read/write|Read-only|
|**`DR(4)`**|Command result|Read-only, writes discarded|Write-only|
|**`DR(5)`**|[Breakpoint / memory watchpoint mode (8x 4-bit)](#breakpoints-and-memory-watchpoints)|Read/write|Read-only|
|**`DR(10 + i)`<br/>`0 ≤ i < 8`**|Breakpoint / memory watchpoint #`i` address|Read/write|Read-only|

See [Debug register access](#debug-register-access) for details on how software accesses these `DR` registers.

## Status bitmask

`DR(0)` contains a status bitmask:

|Bit index|Meaning|
|--:|---|
|0|True if the RISCV core is paused waiting for a debugger to inspect it or resume it|
|1|True if the current pause is due to a breakpoint being hit|
|2|True if the current pause is due to a memory watchpoint being hit|
|3|True if the current pause is due to an `ebreak` or `ecall` instruction being hit|
|4,5,6,7|Reserved, always zero|
|8 + i<br/>0 ≤ i < 8|True if the current pause is due to breakpoint / memory watchpoint #`i` being hit|
|≥ 16|Reserved, always zero|

## Command and control bitmask

The low 9 bits of `DR(1)` contains a bitmask of potential debugger actions: any write to `DR(1)` will trigger all of the actions specified in the bitmask (though not all combinations of actions are valid). Software can read back the value of `DR(1)` and observe the bitmask, but the bitmask only causes a hardware effect on the single cycle on which the write occurred. Meanwhile, the high bit of `DR(1)` behaves totally differently: it is a persistent mode bit. If software sets this bit, it remains in effect up until software subsequently clears the bit.

|Bit&nbsp;index|Meaning|Valid to set when...|
|--:|---|---|
|0|[Trigger pause](#trigger-pause)|RISCV core is executing normally|
|1|[Trigger single-step](#resuming-execution)|RISCV core is paused waiting for a debugger to inspect it or resume it, and slow execution mode has been enabled since before the pause|
|2|[Trigger resumption of normal execution](#resuming-execution)|RISCV core is paused waiting for a debugger to inspect it or resume it, and slow execution mode has been enabled since before the pause|
|3|[Trigger GPR read or `pc` read](#reading-gprs)|RISCV core is paused waiting for a debugger to inspect it or resume it|
|4|[Trigger GPR write](#writing-gprs)|RISCV core is paused waiting for a debugger to inspect it or resume it|
|5|[Trigger memory read](#reading-memory)|RISCV core is paused waiting for a debugger to inspect it or resume it|
|6|[Trigger memory write](#writing-memory)|RISCV core is paused waiting for a debugger to inspect it or resume it|
|7|[Trigger bulk GPR write](#writing-gprs)|RISCV core is paused waiting for a debugger to inspect it or resume it|
|8|[Trigger `pc` write](#writing-pc)|RISCV core is paused waiting for a debugger to inspect it or resume it|
|9-30|Reserved|N/A|
|31|[Slow execution mode](#slow-execution-mode)|Can be enabled or disabled at any time|

### Slow execution mode

Software can put a RISCV into slow execution mode by setting bit 31 of [`DR(1)`](#command-and-control-bitmask), and the RISCV will remain in this mode until software clears bit 31. Whilst in this mode:

<ul><li>The capacity of the Load/Store Unit's store queue is reduced from four entries down to one entry, and the capacity of the Load/Store Unit's retire-order queue is reduced from eight entries down to one entry (if these queues initially contain more than one entry, then the existing entries are allowed to naturally drain out). Once these queues contain at most one element, <a href="MemoryOrdering.md">memory ordering</a> is greatly simplified: a load's read-response will always be obtained before a subsequent memory operation's request is emitted, and a store's write-request will always be emitted before a subsequent memory operation's request is emitted. The tradeoff is that the core is no longer able to hide the latency of loads</li>
<li>The capacity of some queues within the Frontend is similarly reduced down to just a single entry. This will make it harder for the core to hide the latency of fetching instructions</li>
<li>The GPR operand forwarding network is disabled, so instructions can only enter the Integer Unit once the instructions which generate their register operands have retired: the Integer Unit cannot snoop the result from a generating instruction as it moves between the Integer Unit and the Load/Store Unit, nor as it moves between the Load/Store Unit and the Retire Unit. This will cause increased latency for sequentially dependent instructions</li>
<li>The branch predictor is partially disabled. Unfortunately, the core is not designed to operate with a partially disabled branch predictor, so software needs to <i>entirely</i> disable the branch predictor prior to entering slow execution mode, and keep it disabled whilst in slow execution mode. This can be done by setting some bits that live in <a href="../TensixCoprocessor/BackendConfiguration.md">Tensix backend configuration</a>:<br/><br/><table><thead><tr><th/><th align="center">Branch predictor disable bit</th></tr></thead>
<tr><th>RISCV B</th><td><code>Config[0].DISABLE_RISC_BP_Disable_main</code></td></tr>
<tr><th>RISCV T0</th><td><code>Config[0].DISABLE_RISC_BP_Disable_trisc</code> (low bit thereof)</td></tr>
<tr><th>RISCV T1</th><td><code>Config[0].DISABLE_RISC_BP_Disable_trisc</code> (middle bit thereof)</td></tr>
<tr><th>RISCV T2</th><td><code>Config[0].DISABLE_RISC_BP_Disable_trisc</code> (high bit thereof)</td></tr>
<tr><th>RISCV NC</th><td><code>Config[0].DISABLE_RISC_BP_Disable_ncrisc</code></td></tr>
<tr><th>RISCV E</th><td>Cannot be disabled</td></tr></table>Unfortunately, Tensix backend configuration is not part of the address space made available over the NoC, so there is no particularly convenient way for an external debugger to disable the branch predictor until it has <i>already</i> commandeered a core (and can therefore perform memory writes as if it were the core).</li></ul>

## Breakpoints and memory watchpoints

Up to eight hardware breakpoints / memory watchpoints can be set at once. `DR(5)` contains bits to control this:

|First bit|# Bits|Purpose|Corresponding address register|
|--:|--:|---|---|
|0|4|Breakpoint / memory watchpoint #0 mode|`DR(10)`|
|4|4|Breakpoint / memory watchpoint #1 mode|`DR(11)`|
|8|4|Breakpoint / memory watchpoint #2 mode|`DR(12)`|
|12|4|Breakpoint / memory watchpoint #3 mode|`DR(13)`|
|16|4|Breakpoint / memory watchpoint #4 mode|`DR(14)`|
|20|4|Breakpoint / memory watchpoint #5 mode|`DR(15)`|
|24|4|Breakpoint / memory watchpoint #6 mode|`DR(16)`|
|28|4|Breakpoint / memory watchpoint #7 mode|`DR(17)`|

For each of the eight, the available mode values are:
* **`<8` - Disabled.** The address in `DR(10+i)` is ignored.
* **`8` - Breakpoint.** Execution of the address in `DR(10+i)` will trigger a pause.
* **`9` - Memory watchpoint, read.** Any load instruction loading from the address in `DR(10+i)` will trigger a pause.
* **`10` - Memory watchpoint, write.** Any store instruction storing to the address in `DR(10+i)` will trigger a pause.
* **`11` - Memory watchpoint, read or write.** Any load instruction loading from the address in `DR(10+i)` will trigger a pause, as will any store instruction storing to the address in `DR(10+i)`.
* **`>11` - Disabled.** The address in `DR(10+i)` is ignored.

If a breakpoint is triggered, then the triggering instruction will be allowed to leave the Load/Store Unit, the core will wait until the _next_ instruction [meets the requirements for leaving the Load/Store Unit](MemoryOrdering.md#mechanical-description), and then instead of allowing that instruction to leave the Load/Store Unit, the core will pause waiting for a debugger to inspect it or resume it. Whilst paused, no instructions can _leave_ the Load/Store Unit, and therefore no instructions can retire, but instructions can still _enter_ the Load/Store Unit (until the queues therein become full) and can still progress through all the earlier stages of the RISCV pipeline (until they also become full).

The semantics of memory watchpoints are not quite so clean. A load instruction can hit a read memory watchpoint as it _enters_ the Load/Store Unit, and once hit, no instructions can _leave_ the Load/Store Unit, and the core will pause once _an_ instruction [meets the requirements for leaving the Load/Store Unit](MemoryOrdering.md#mechanical-description). This might be the load instruction which hit the watchpoint, or it might be some earlier instruction in program order. A store instruction can hit a write memory watchpoint as it _leaves_ the Load/Store Unit's store queue, and once hit, no instructions can _leave_ the Load/Store Unit, and the core will pause once _an_ instruction [meets the requirements for leaving the Load/Store Unit](MemoryOrdering.md#mechanical-description). This might be the store instruction which hit the watchpoint, or it might be an earlier or later instruction in program order. Whilst paused, no instructions can _leave_ the Load/Store Unit, and therefore no instructions can retire, but instructions can still _enter_ the Load/Store Unit (until the queues therein become full) and can still progress through all the earlier stages of the RISCV pipeline (until they also become full). If the core is in [slow execution mode](#slow-execution-mode), then the semantics of memory watchpoints become slightly cleaner, as the relevant queues have their capacity reduced down to just a single entry.

## `ebreak` and `ecall` instructions

RISCV `ebreak` and `ecall` instructions are executed as if they were `nop` instructions, but additionally act as if a hardware breakpoint was set on them, so their execution triggers a pause exactly as described in the previous section. The triggering instruction (i.e. `ebreak` or `ecall`) will be allowed to leave the Load/Store Unit, the core will wait until the _next_ instruction [meets the requirements for leaving the Load/Store Unit](MemoryOrdering.md#mechanical-description), and then instead of allowing that instruction to leave the Load/Store Unit, the core will pause waiting for a debugger to inspect it or resume it. Whilst paused, no instructions can _leave_ the Load/Store Unit, and therefore no instructions can retire, but instructions can still _enter_ the Load/Store Unit (until the queues therein become full) and can still progress through all the earlier stages of the RISCV pipeline (until they also become full).

## Trigger pause

If [`DR(1)`](#command-and-control-bitmask) is written to, and the value being written has bit 0 set, then a pause is triggered. The core will wait until an instruction [meets the requirements for leaving the Load/Store Unit](MemoryOrdering.md#mechanical-description), and then instead of allowing that instruction to leave the Load/Store Unit, the core will pause waiting for a debugger to inspect it or resume it. Whilst paused, no instructions can _leave_ the Load/Store Unit, and therefore no instructions can retire, but instructions can still _enter_ the Load/Store Unit (until the queues therein become full) and can still progress through all the earlier stages of the RISCV pipeline (until they also become full).

Triggering a pause has no effect if the core is _already_ paused waiting for a debugger to inspect it or resume it. Software can read from [`DR(0)`](#status-bitmask) to determine whether a core is already paused, and also to determine whether a trigger has resulted in a pause (it usually will within a handful of cycles, though it can take longer if the head of the queue is a load instruction waiting to pop from an empty FIFO).

### FIFOs

Most RISCV instructions will always complete in a finite number of cycles. However, some instructions do not have a static bound on how long they will take to complete:
* Loads from a [PCBuf](PCBufs.md) can wait for an indeterminate amount of time (unless `OverrideEn` and `OverrideBusy` are set).
* Loads from a [mailbox](Mailboxes.md) can wait for an indeterminate amount of time (unless software has already confirmed the mailbox is non-empty by polling its emptiness).
* Loads from [TDMA-RISC](../TDMA-RISC.md) can wait for an indeterminate amount of time when `MetadataFIFO.Peek()` is part of the read behavior.
* Loads from unmapped memory might wait forever.
* Stores to a [PCBuf](PCBufs.md) or to a [mailbox](Mailboxes.md) can remain in the store queue for as long as the FIFO is full, which can cause subsequent instructions to be stalled for an indeterminate amount of time.
* Stores to [push a Tensix instruction](PushTensixInstruction.md) can remain in the store queue for as long as the FIFOs in the Tensix frontend are full, and the FIFOs can remain full for an indeterminate amount of time if there's an in-flight [`STALLWAIT`](../TensixCoprocessor/STALLWAIT.md), [`SEMWAIT`](../TensixCoprocessor/SEMWAIT.md), [`ATGETM`](../TensixCoprocessor/ATGETM.md), [`ATCAS`](../TensixCoprocessor/ATCAS.md), or [`ATINCGETPTR`](../TensixCoprocessor/ATINCGETPTR.md) Tensix instruction. If so, this can cause subsequent RISCV instructions to be stalled for an indeterminate amount of time.
* Stores to unmapped memory might remain in the store queue forever, which can cause subsequent instructions to be stalled forever.

The above instructions present two problems for the GDB/Debug interface:
1. When a pause is requested, if any of the above instructions are in flight, it could take an indeterminate amount of time for the pause to be actioned, and until it is actioned, the GDB/Debug interface can't even query the `pc` (though the [debug daisychain](../DebugDaisychain.md#riscv-execution-state) _can_ be used to query `pc` whilst waiting for a pause to be actioned, and the low 31 bits of group A therein are guaranteed to be valid once a pause has been requested).
2. In order to safely resume a core after it has been paused, it usually needs to be placed in [slow execution mode](#slow-execution-mode) prior to being paused, and if the Load/Store Unit's retire-order queue initially contains more than one entry, software needs to wait for the existing entries to naturally drain out. If any of the above instructions are in flight, it could take an indeterminate amount of time for this draining to happen.

If software wishes to use the GDB/Debug interface, the following mitigations are suggested:
1. Do not use [PCBufs](PCBufs.md) at all; [mailboxes](Mailboxes.md) can be used instead.
2. To read from a [mailbox](Mailboxes.md), perform a software polling loop to query whether the mailbox is non-empty, and only perform a read to pop from the mailbox once this loop has confirmed that the mailbox is non-empty.
3. If using the `MetadataFIFO` functionality of [TDMA-RISC](../TDMA-RISC.md), perform a software polling loop of `MetadataFIFOStatus` to query whether the FIFO is non-empty, and only perform a read from `MetadataFIFO` once this loop has confirmed that the FIFO is non-empty.
4. To avoid writing to a full mailbox, use a communication channel in the opposite direction (such as another mailbox) to keep track of write credits.

## Resuming execution

If a core is paused waiting for a debugger to inspect it or resume it, and [`DR(1)`](#command-and-control-bitmask) is written to, and the value being written has bit 1 or bit 2 set, then the core will resume execution. If bit 2 is set, it'll resume execution normally, whereas if just bit 1 is set, it'll resume execution for just a single instruction.

Due to a hardware bug, it is only safe to resume execution or single-step execution if either:
* The Load/Store Unit contains no load instructions in its retire-order queue.
* The Load/Store Unit contains exactly one load instruction in its retire-order queue, and that load instruction [meets the requirements for leaving the Load/Store Unit](MemoryOrdering.md#mechanical-description).

The easiest way to meet one of the above requirements is to ensure that the core is in [slow execution mode](#slow-execution-mode), as this reduces the capacity of the retire-order queue to just a single element. For this, prior to triggering a pause, the debugger should:
1. Disable the branch predictor (as it can conflict with slow execution mode).
2. Enable slow execution mode.
3. Wait an appropriate number of cycles to allow the existing contents of retire-order queue to naturally drain out. 200 clock cycles should suffice, unless [FIFOs](#fifos) are in play.

If not using slow execution mode, _some_ other viable approaches exist:
* For pauses triggered by `ebreak` or `ecall` instructions: software needs to ensure that of the next eight (dynamic) instructions after the `ebreak` or `ecall` instruction, the first can optionally be a load instruction, but none of the other seven can be. Note that it suffices for the single instruction after `ebreak` or `ecall` to be an unconditional jump that jumps back to itself, as this'll cause the next eight dynamic instructions to all be copies of that jump (though to _meaningfully_ resume execution, software will need to change this instruction to something other than an infinite loop and then flush the instruction cache).
* For pauses triggered by hardware breakpoints: software needs to ensure that of the next eight (dynamic) instructions after the instruction configured as a hardware breakpoint, the first can optionally be a load instruction, but none of the other seven can be. Note that it suffices for the single instruction after the hardware breakpoint to be an unconditional jump that jumps back to itself, as this'll cause the next eight dynamic instructions to all be copies of that jump (though to _meaningfully_ resume execution, software will need to change this instruction to something other than an infinite loop and then flush the instruction cache).

## Reading GPRs

If a core is paused waiting for a debugger to inspect it or resume it, and [`DR(1)`](#command-and-control-bitmask) is written to, and the value being written has bit 3 set, then a GPR read or `pc` read is performed. Prior to writing to `DR(1)`, software should put the desired GPR index (`0` through `31`) into `DR(2)`, or put the value `32` in `DR(2)` if it wishes to read `pc`. The value of the GPR or of `pc` will be copied to `DR(4)`, which software can subsequently read.

The reported `pc` will be the address of the instruction that [meets the requirements for leaving the Load/Store Unit](MemoryOrdering.md#mechanical-description), and the reported GPR values will be as of the point in time that said instruction read from GPRs (unless the debugger has modified GPRs), but said instruction's GPR write (if any) will not yet have been performed.

## Writing GPRs

If a core is paused waiting for a debugger to inspect it or resume it, and [`DR(1)`](#command-and-control-bitmask) is written to, and the value being written has bit 4 set, then a GPR write is performed. Prior to writing to `DR(1)`, software should put the desired GPR index (`1` through `31`) into `DR(2)` and the desired value of that GPR into `DR(3)`. If a core is paused waiting for a debugger to inspect it or resume it, and [`DR(1)`](#command-and-control-bitmask) is written to, and the value being written has bit 7 set, then a bulk GPR write is performed: this is equivalent to individually writing `0` to all of `x1` through `x31`.

Note that instructions already in the RISCV pipeline might have already performed their GPR reads, and the instruction that [meets the requirements for leaving the Load/Store Unit](MemoryOrdering.md#mechanical-description) will _definitely_ have already performed its GPR reads. As such, debuggers should expect that several subsequent instructions will need to execute before GPR writes become visible to instructions.

## Writing `pc`

If a core is paused waiting for a debugger to inspect it or resume it, and [`DR(1)`](#command-and-control-bitmask) is written to, and the value being written has bit 8 set, then several things happen:
* All in-flight instructions in the RISCV pipeline are aborted. Any in-flight stores might or might not have already sent their write-request into the memory subsystem. Any in-flight loads might or might not have already sent their read-request into the memory subsystem.
* Branch predictor history is forgotten.
* A new value is written to `pc`. If in [slow execution mode](#slow-execution-mode), the value in `DR(4)` is written to `pc`. Otherwise, `pc` is set as per a [soft reset](../SoftReset.md#riscv-soft-reset) of the core.
* Execution resumes at the new `pc` (though if [bit 2 of `DR(1)`](#resuming-execution) is not simultaneously set, instructions will still be unable to _leave_ the Load/Store Unit, so only a limited amount of execution can happen).

To work around a hardware bug, bit 8 of `DR(1)` should always be set in combination with bit 1. If bit 8 is set, then bit 1 does not have its [usual meaning of causing single-step execution](#resuming-execution); its sole effect in this context is to work around a bug elsewhere.

The usual safety concerns around the contents of the Load/Store Unit when resuming execution are entirely mitigated due to all in-flight instructions being aborted prior to the resumption. In _most cases_, a debugger could choose to determine and then re-issue any in-flight instructions, though this is not possible for loads which atomically pop from a FIFO: in that case aborting the instruction will throw away the popped value and it is not possible to obtain the value.

## Reading memory

If a core is paused waiting for a debugger to inspect it or resume it, and [`DR(1)`](#command-and-control-bitmask) is written to, and the value being written has bit 5 set, then a memory read is performed. This cannot be simultaneously combined with bits 1 or 2 or 6. Prior to writing to `DR(1)`, software should put the desired memory address into `DR(2)`. The core will then be temporarily busy while it performs the read, and bit 0 of [`DR(0)`](#status-bitmask) will be `false` while the core is busy. Once the read completes, the result of the read will be put in `DR(4)` and bit 0 of `DR(0)` will simultaneously revert to `true`. Software is expected to poll `DR(0)` until bit 0 reverts to `true`, and then read from `DR(4)`.

The read will be performed as if it were an `lw` instruction executed by the core, and any part of the [memory map](../BabyRISCV/README.md#memory-map) can be accessed. Notably, this allows a debugger to inspect [RISCV local data RAM](README.md#local-data-ram).

## Writing memory

If a core is paused waiting for a debugger to inspect it or resume it, and [`DR(1)`](#command-and-control-bitmask) is written to, and the value being written has bit 6 set, then a memory write is performed. This cannot be simultaneously combined with bits 1 or 2 or 5. Prior to writing to `DR(1)`, software should put the desired memory address into `DR(2)` and the desired value of that memory into `DR(3)`. The core will then be temporarily busy while it performs the write, and bit 0 of [`DR(0)`](#status-bitmask) will be `false` while the core is busy. Once the write completes, bit 0 of `DR(0)` will revert to `true`. Software is expected to poll `DR(0)` until bit 0 reverts to `true`.

The write will be performed as if it were an `sw` instruction executed by the core, and any part of the [memory map](../BabyRISCV/README.md#memory-map) can be accessed. Notably, this allows a debugger to inspect [RISCV local data RAM](README.md#local-data-ram).

Note that instructions already in the RISCV pipeline might have already performed their memory reads, and the instruction that [meets the requirements for leaving the Load/Store Unit](MemoryOrdering.md#mechanical-description) will _definitely_ have already performed its memory read (if any). As such, unless in [slow execution mode](#slow-execution-mode), debuggers should expect that several subsequent instructions will need to execute before memory writes become visible to instructions.

## Debug register access

Access to all the `DR` registers of the various RISCV cores is multiplexed through just four registers in the "Tile control / debug / status registers" memory region, whose addresses are:

```c
#define RISCV_DEBUG_REGS_START_ADDR                                0xFFB12000
#define RISCV_DEBUG_REG_RISC_DBG_CNTL_0   (RISCV_DEBUG_REGS_START_ADDR | 0x80)
#define RISCV_DEBUG_REG_RISC_DBG_CNTL_1   (RISCV_DEBUG_REGS_START_ADDR | 0x84)
#define RISCV_DEBUG_REG_RISC_DBG_STATUS_0 (RISCV_DEBUG_REGS_START_ADDR | 0x88)
#define RISCV_DEBUG_REG_RISC_DBG_STATUS_1 (RISCV_DEBUG_REGS_START_ADDR | 0x8C)
```

||Purpose|Software access|Hardware access|
|---|---|---|---|
|**`RISCV_DEBUG_REG_RISC_DBG_CNTL_0`**|`DR` read/write control|Read/write, write can cause effect|Read-only|
|**`RISCV_DEBUG_REG_RISC_DBG_CNTL_1`**|`DR` write value|Read/write|Read-only|
|**`RISCV_DEBUG_REG_RISC_DBG_STATUS_0`**|Echo of `DR` read/write control|Read-only (writes discarded)|Write-only|
|**`RISCV_DEBUG_REG_RISC_DBG_STATUS_1`**|`DR` read value|Read-only (writes discarded)|Write-only|

### `RISCV_DEBUG_REG_RISC_DBG_CNTL_0`

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|11|`DR_i`|Software should set to `i` in order to access `DR(i)`|
|11|5||Ignored|
|16|1|`IsWrite`|Software should set to `true` to perform a `DR` write, or `false` to perform a `DR` read|
|17|2|`Which_RISCV`|Software should set according to which RISCV it wishes to access the `DR` register of:<br/><ul><li><code>0</code> for RISCV B (Tensix tiles) or RISCV E (Ethernet tiles)</li><li><code>1</code> for RISCV T0</li><li><code>2</code> for RISCV T1</li><li><code>3</code> for RISCV T2</li></ul>|
|19|12||Ignored|
|31|1|`Trigger`|A read or write of `DR(i)` is triggered whenever software changes the value of this field from `false` to `true`|

### `RISCV_DEBUG_REG_RISC_DBG_STATUS_0`

This register is mostly a read-only echo of `RISCV_DEBUG_REG_RISC_DBG_CNTL_0`: once software writes to `RISCV_DEBUG_REG_RISC_DBG_CNTL_0`, hardware will at some point receive that write and echo it back through `RISCV_DEBUG_REG_RISC_DBG_STATUS_0`. Once software observes the echo, it knows that hardware has received and processed the write to `RISCV_DEBUG_REG_RISC_DBG_CNTL_0`. The low 30 bits of `RISCV_DEBUG_REG_RISC_DBG_STATUS_0` are unstable following a write to `RISCV_DEBUG_REG_RISC_DBG_CNTL_0`: software should only inspect the low 30 bits of `RISCV_DEBUG_REG_RISC_DBG_STATUS_0` once it has observed the echo of `Trigger` in bit 31.

One bit of `RISCV_DEBUG_REG_RISC_DBG_STATUS_0` is _not_ an echo of `RISCV_DEBUG_REG_RISC_DBG_CNTL_0`, and instead tells software when it can safely read from `RISCV_DEBUG_REG_RISC_DBG_STATUS_1`.

|First bit|# Bits|Meaning|
|--:|--:|---|
|0|11|`RISCV_DEBUG_REG_RISC_DBG_CNTL_0.DR_i`|
|11|2|Always zero|
|13|4|`RISCV_DEBUG_REG_RISC_DBG_CNTL_0.IsWrite << RISCV_DEBUG_REG_RISC_DBG_CNTL_0.Which_RISCV`|
|17|13|Always zero|
|30|1|True if `RISCV_DEBUG_REG_RISC_DBG_STATUS_1` is valid to read|
|31|1|`RISCV_DEBUG_REG_RISC_DBG_CNTL_0.Trigger`|

### Writing to `DR(i)`

To perform a write to `DR(i)` of some RISCV core, software should:

1. Perform a write to `RISCV_DEBUG_REG_RISC_DBG_CNTL_1` with the desired contents of `DR(i)`.
2. Perform a write to `RISCV_DEBUG_REG_RISC_DBG_CNTL_0` with `Trigger == false` (the other fields can contain anything).
3. Read from `RISCV_DEBUG_REG_RISC_DBG_STATUS_0` (in a loop) until `Trigger == false` is observed. This step can usually be skipped, though it is recommended for robustness.
4. Perform a write to `RISCV_DEBUG_REG_RISC_DBG_CNTL_0` with `DR_i == i`, `IsWrite == true`, `Which_RISCV == j`, `Trigger == true`. The transition of `Trigger` from `false` to `true` will cause hardware to act upon the other fields: it'll initiate the `DR` write (using the value from `RISCV_DEBUG_REG_RISC_DBG_CNTL_1`), and also set bit 30 of `RISCV_DEBUG_REG_RISC_DBG_STATUS_0` to `false`.
5. Read from `RISCV_DEBUG_REG_RISC_DBG_STATUS_0` (in a loop) until `Trigger == true` is observed. This step can usually be skipped, though it is recommended for robustness. If skipped, software should instead ensure that `RISCV_DEBUG_REG_RISC_DBG_CNTL_0` is not written to for another three cycles.

### Reading from `DR(i)`

To perform a read of `DR(i)` of some RISCV core, software should:

1. Perform a write to `RISCV_DEBUG_REG_RISC_DBG_CNTL_0` with `Trigger == false` (the other fields can contain anything).
2. Read from `RISCV_DEBUG_REG_RISC_DBG_STATUS_0` (in a loop) until `Trigger == false` is observed. This step can usually be skipped, though it is recommended for robustness.
3. Perform a write to `RISCV_DEBUG_REG_RISC_DBG_CNTL_0` with `DR_i == i`, `IsWrite == false`, `Which_RISCV == j`, `Trigger == true`. The transition of `Trigger` from `false` to `true` will cause hardware to act upon the other fields: it'll initiate the `DR` read, and also set bit 30 of `RISCV_DEBUG_REG_RISC_DBG_STATUS_0` to `false`. Once the read completes, hardware will put the result into `RISCV_DEBUG_REG_RISC_DBG_STATUS_1` and simultaneously transition bit 30 of `RISCV_DEBUG_REG_RISC_DBG_STATUS_0` to `true`.
4. Read from `RISCV_DEBUG_REG_RISC_DBG_STATUS_0` (in a loop) until `Trigger == true` is observed and bit 30 of this register is `true`.
5. Read from `RISCV_DEBUG_REG_RISC_DBG_STATUS_1`, which will contain the contents of `DR(i)`.
