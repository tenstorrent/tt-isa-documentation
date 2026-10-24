# PIC

The PIC (programmable interrupt controller) can:
* Track 32 different software IRQs, which software can atomically raise and/or clear.
* Track 4 different hardware IRQs, which hardware can atomically raise, and software can atomically clear.
* Interrupt RISCV B and/or RISCV NC in response to an IRQ, with the `pc` of the interrupt handler configurable per IRQ.

> [!TIP]
> Blackhole features three different styles of PIC: this page describes the PIC found in Tensix tiles, then Ethernet tiles have a different style of PIC, and L2CPU tiles have yet another style of PIC. All three are substantially different to the PIC found in Wormhole.

## Software IRQs

Each of the 32 software IRQs has a 32-bit MMIO register associated with it:
* Writing a non-zero value to the register raises the IRQ.
* Writing a zero value to the register clears the IRQ.
* If the IRQ is raised, reading from the register returns the value from the most recent write (which will be non-zero), and atomically writes zero at the same time, thereby clearing the IRQ.
* If the IRQ is cleared, reading from the register will return `0`.

Software can assign any purpose to the 32 software IRQs, and assign any meaning to the non-zero values. Alternatively, it can ignore the concept of interrupts entirely and instead use these MMIO addresses as atomic single-slot queues.

## Hardware IRQs

The four hardware IRQs are:

|Index|Raised by|
|--:|---|
|0|NoC Overlay when [`STREAM_BLOB_AUTO_CFG_DONE_REG_INDEX`](../NoC/Overlay/LoadConfigurationFromL1.md) non-zero|
|1|NoC #0 NIU when any `NIU_MST_REQS_OUTSTANDING_ID(i)` counter changes from positive to zero ([subject to appropriate NIU configuration](../NoC/Interrupts.md))|
|2|NoC #1 NIU when any `NIU_MST_REQS_OUTSTANDING_ID(i)` counter changes from positive to zero ([subject to appropriate NIU configuration](../NoC/Interrupts.md))|
|3|The watchdog timer, when it hits zero, or the ECC scrubber, when it detects a bit flip (in both cases subject to appropriate configuration)|

Each of these hardware IRQs has a 32-bit MMIO register associated with it:
* Writing to the register has no effect.
* If the IRQ is raised, reading from the register will return `1`.
* If the IRQ is cleared, reading from the register will return `0`.

Each hardware IRQ has a different way of clearing it, which will involve software addressing the underlying reason for the hardware IRQ having been raised.

## Memory Map

|Name|Address|Software access|Purpose|
|---|---|---|---|
|`BRISC_SW_INT_EN`|`0xFFB1_3000`|Read / write|Bitmask of enabled software IRQs for RISCV B (i.e. which IRQs cause interrupts)|
|`BRISC_HW_INT_EN`|`0xFFB1_3004`|Read / write|Bitmask of enabled hardware IRQs for RISCV B (i.e. which IRQs cause interrupts)|
|`BRISC_INT_NO`|`0xFFB1_3008`|Read only|If RISCV B has been interrupted, the index of the software IRQ responsible for that, or 32 plus the index of the hardware IRQ responsible for that|
|`NCRISC_SW_INT_EN`|`0xFFB1_300C`|Read / write|Bitmask of enabled software IRQs for RISCV NC (i.e. which IRQs cause interrupts)|
|`NCRISC_HW_INT_EN`|`0xFFB1_3010`|Read / write|Bitmask of enabled hardware IRQs for RISCV NC (i.e. which IRQs cause interrupts)|
|`NCRISC_INT_NO`|`0xFFB1_3014`|Read only|If RISCV NC has been interrupted, the index of the software IRQ responsible for that, or 32 plus the index of the hardware IRQ responsible for that|
|`SW_INT[i]`|<code>0xFFB1_3018&nbsp;+&nbsp;i*4</code><br/>(for `0 ≤ i < 32`)|Read / write|One 32-bit register per software IRQ, used to raise or query/clear the IRQ|
|`HW_INT[i]`|<code>0xFFB1_3098&nbsp;+&nbsp;i*4</code><br/>(for `0 ≤ i < 4`)|Read only|One 32-bit register per hardware IRQ, used to query the IRQ|
|`SW_INT_PC[i]`|<code>0xFFB1_30A8&nbsp;+&nbsp;i*4</code><br/>(for `0 ≤ i < 32`)|Read / write|One 32-bit register per software IRQ, containing the `pc` of the interrupt handler|
|`HW_INT_PC[i]`|<code>0xFFB1_3128&nbsp;+&nbsp;i*4</code><br/>(for `0 ≤ i < 4`)|Read / write|One 32-bit register per hardware IRQ, containing the `pc` of the interrupt handler|

## Interrupt handlers

If an IRQ is raised, and the relevant bit of `BRISC_SW_INT_EN` or `BRISC_HW_INT_EN` is set, then RISCV B will be interrupted (unless it is already running an interrupt handler). The current `pc` will be saved to an internal register within RISCV B, and then `pc` will be set to the relevant entry of `SW_INT_PC` or `HW_INT_PC`. The interrupt handler is expected to:
1. Save any other RISCV execution state which it intends to modify (for example by decrementing `sp` and then storing to the newly allocated stack space).
2. If the same handler is configured to handle multiple different IRQs, read from `BRISC_INT_NO` to determine which IRQ the handler was invoked for. Note that hardware will hold the value of `BRISC_INT_NO` constant for the duration of the interrupt handler.
3. Read from the appropriate `SW_INT[i]` or `HW_INT[i]`, and if the result is non-zero, handle the IRQ. Note that the result can be zero if the IRQ was cleared _after_ the interrupt handler was invoked but _before_ the handler had time to read from `SW_INT[i]` or `HW_INT[i]`. The handler is free to read from other `SW_INT[j]` or `HW_INT[j]` if it has reason to believe that they might be raised, and if so, it should handle IRQs when such a read returns a non-zero value.
4. Restore any modified RISCV execution state.
5. Execute an `mret` instruction.

The same applies to RISCV NC, just using `NCRISC_SW_INT_EN` and `NCRISC_HW_INT_EN` and `NCRISC_INT_NO`.

If a particular IRQ is enabled for both RISCV B and RISCV NC, then raising that IRQ can potentially invoke the same interrupt handler on both RISCV B and RISCV NC. Whichever one reads from `SW_INT[i]` or `HW_INT[i]` first will observe a non-zero value and get the chance to handle the IRQ.

Interrupt handlers do not nest: once one has been invoked, another will not be invoked until the previous one executes `mret`. When there are multiple enabled raised IRQs, fair round-robin arbitration is used to choose which handler to invoke.

> [!CAUTION]
> Due to a hardware bug, interrupt handlers cannot write to CSRs: `csrrw` / `csrrs` / `csrrc` / `csrrwi` / `csrrsi` / `csrrci` instructions can be used by a handler to _read_ from CSRs, but cannot write to CSRs.

> [!CAUTION]
> Due to a hardware bug, an `mret` can be skipped: if the branch predictor holds an entry that matches the address of the `mret` and predicts it taken, the `mret` is treated as a mispredicted non-branch instruction and execution continues at the following instruction, still inside the interrupt handler. Following the `mret` with a jump back to it (for example `1: mret; j 1b`) avoids this: the first attempt removes the predictor entry, so the second `mret` returns.
