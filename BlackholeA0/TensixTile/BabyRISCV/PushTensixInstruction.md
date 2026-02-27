# Push Tensix Instruction

The baby RISCV cores can push Tensix instructions to the [Tensix coprocessor](../TensixCoprocessor/README.md) (and indeed this is the _only_ way of getting instructions to the coprocessor; the coprocessor does not fetch instructions by itself). The coprocessor contains three separate threads of execution, with one instruction stream per thread. RISCV T0 can push instructions to Tensix thread T0, RISCV T1 can push instructions to Tensix thread T1, RISCV T2 can push instructions to Tensix thread T2, RISCV B can push instructions to any Tensix thread, and RISCV NC cannot push instructions.

Tensix instructions are 32 bits wide, and instructions are pushed by performing a RISCV `sw` instruction, where the 32-bit value being "stored" is the instruction to push. The combination of store address and executing RISCV determines where the instruction is pushed to:
<table><thead><tr><th>Store Address</th><th>RISCV B</th><th>RISCV T0</th><th>RISCV T1</th><th>RISCV T2</th></tr></thead>
<tr><td><code>INSTRN_BUF_BASE</code><br/><code>0xFFE4_0000</code></td><td>Push to Tensix T0</td><td>Push to Tensix T0</td><td>Push to Tensix T1</td><td>Push to Tensix T2</td></tr>
<tr><td><code>INSTRN1_BUF_BASE</code><br/><code>0xFFE5_0000</code></td><td>Push to Tensix T1</td><td colspan="3">Do not use; attempting to store here will hang the RISCV</td></tr>
<tr><td><code>INSTRN2_BUF_BASE</code><br/><code>0xFFE6_0000</code></td><td>Push to Tensix T2</td><td colspan="3">Do not use; attempting to store here will hang the RISCV</td></tr></table>

Instructions are pushed into FIFOs (fixed-capacity queues) within the Tensix coprocessor's frontend, from which the coprocessor will pop as instructions progress through the coprocessor. Attempting to push into a full FIFO will cause hardware to automatically stall the RISCV until FIFO space becomes available. The various RISCVs push to different FIFOs within the Tensix coprocessor's frontend, as shown in the frontend-focused diagram:

![](../../../Diagrams/Out/TensixFrontend_BH.svg)

The very first FIFO has a capacity of 32 instructions, but this capacity can only be hit by starting with 28 instructions and pushing four instructions in a single cycle via `.ttinsn` fusion. Once the FIFO contains more than 28 instructions, it needs to drop back down to 28 instructions before it'll accept any more. Furthermore, due to restrictions imposed by Auto TTSync's tracking machinery, the capacity of the downstream FIFOs is only additive to the first FIFO when MOP expansion or replay expansion happens. These restrictions are in effect even when Auto TTSync is turned off.

## `.ttinsn` instruction set extension

As pushing Tensix instructions is extremely common, the Tenstorrent RISCV assembler permits the syntax `.ttinsn IMM32` as a shorthand for storing the compile-time constant 32-bit value `IMM32` to address `INSTRN_BUF_BASE`. This syntax is only permitted when `IMM32` is less than `0xC0000000u`, but this is always true for valid Tensix instructions. The baby RISCV cores then implement a custom RISCV extension allowing `.ttinsn IMM32` to be encoded as a single 32-bit RISCV instruction, with the semantics of `.ttinsn IMM32` being _exactly_ identical to an `sw` instruction storing the value `IMM32` to address `INSTRN_BUF_BASE`. Furthermore, sequences of up to four adjacent `.ttinsn` instructions can be fused together by the RISCV T0 / T1 / T2 instruction caches and executed in a single cycle (this allows four Tensix instructions to be queued up per thread per cycle, but the maximum dequeue rate is only one instruction per thread per cycle).

The encoding of `.ttinsn IMM32` is very simple: it is just `IMM32` rotated left by two bits. Due to the `0xC0000000u` constraint, after rotation, the low two bits will be `0b00` or `0b01` or `0b10` (never `0b11`). This lands in encoding space that many _other_ RISCV designs use for the RISCV "C"(ompressed) instruction set extension, but the baby RISCV cores do not implement the "C"(ompressed) instruction set extension; they instead treat this space as containing 32-bit `.ttinsn` instructions: the 32 bits of the instruction will be rotated right by two bits and then treated as a _value_ to be stored to `INSTRN_BUF_BASE` (`0xFFE40000`).

For the purposes of [RISCV memory ordering](MemoryOrdering.md), a `.ttinsn` instruction is _exactly_ identical to an `sw` instruction. If fusion is performed, a fused sequence of up to four `.ttinsn` instructions still behaves like a single store instruction for ordering purposes, albeit storing up to 128 bits rather than just 32 bits (similar to the vector stores performable by RISCV T2, and also similar to coalesced stores to L1).

## Memory ordering

`sw` (or `.ttinsn`) instructions to push Tensix instructions follow the usual [RISCV memory ordering](MemoryOrdering.md) rules for stores, with the added twist that the instruction's write-request counts as processed once the instruction has been pushed onto a FIFO in the coprocessor's frontend. If a RISCV core wants to wait for an instruction to have finished executing, rather than just wait for it to have been pushed, then additional mechanisms are required, for example [Auto TTSync](AutoTTSync.md) or [Manual TTSync](ManualTTSync.md).

## Debug registers

Three debug registers relating to pushing Tensix instructions exist in the "Tile control / debug / status registers" memory region.

### `RISCV_DEBUG_REG_INSTRN_BUF_STATUS`

This read-only register provides some visibility into the status of the FIFO before the Replay Expander:

|Bit index|Meaning|
|--:|---|
|0|`false` if the FIFO before the T0 Replay Expander is full, `true` otherwise.|
|1|`false` if the FIFO before the T1 Replay Expander is full, `true` otherwise.|
|2|`false` if the FIFO before the T2 Replay Expander is full, `true` otherwise.|
|3|Reserved, always zero.|
|4|`true` if the FIFO before the T0 Replay Expander is empty, `false` otherwise.|
|5|`true` if the FIFO before the T1 Replay Expander is empty, `false` otherwise.|
|6|`true` if the FIFO before the T2 Replay Expander is empty, `false` otherwise.|
|≥ 7|Reserved, always zero.|

### `RISCV_DEBUG_REG_INSTRN_BUF_CTRL0` (and `RISCV_DEBUG_REG_INSTRN_BUF_CTRL1`)

`RISCV_DEBUG_REG_INSTRN_BUF_CTRL0` can be used to push Tensix instructions via the debug bus, though this comes at the cost of preventing RISCV from pushing instructions via normal means. This provides a mechanism for low-level external agents to push Tensix instructions prior to bringing the RISCV cores online, for example to issue [`RMWCIB`](../TensixCoprocessor/RMWCIB.md) instructions that set [Tensix backend configuration](../TensixCoprocessor/BackendConfiguration.md#special-cases) fields relating to RISCV execution.

|Bit&nbsp;index|Purpose|
|--:|---|
|0|If set to `true`, the debug bus has control of the FIFO before the T0 Replay Expander. While the debug bus has control, normal writes from RISCV B are very likely to be silently discarded, as are normal writes from RISCV T0.|
|1|If set to `true`, the debug bus has control of the FIFO before the T1 Replay Expander. While the debug bus has control, normal writes from RISCV B are very likely to be silently discarded, as are normal writes from RISCV T1.|
|2|If set to `true`, the debug bus has control of the FIFO before the T2 Replay Expander. While the debug bus has control, normal writes from RISCV B are very likely to be silently discarded, as are normal writes from RISCV T2.|
|3|Reserved.|
|4|When the debug bus has control of the FIFO before the T0 Replay Expander, the value in `RISCV_DEBUG_REG_INSTRN_BUF_CTRL1` is pushed onto said FIFO whenever software changes the value of this bit from `false` to `true`. Software should not push when said FIFO is full.|
|5|When the debug bus has control of the FIFO before the T1 Replay Expander, the value in `RISCV_DEBUG_REG_INSTRN_BUF_CTRL1` is pushed onto said FIFO whenever software changes the value of this bit from `false` to `true`. Software should not push when said FIFO is full.|
|6|When the debug bus has control of the FIFO before the T2 Replay Expander, the value in `RISCV_DEBUG_REG_INSTRN_BUF_CTRL1` is pushed onto said FIFO whenever software changes the value of this bit from `false` to `true`. Software should not push when said FIFO is full.|
|7|Reserved.|
|≥ 8|Reserved, always zero.|
