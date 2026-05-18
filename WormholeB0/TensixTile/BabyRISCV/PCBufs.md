# PCBufs

There are three PCBufs within each Tensix tile: all PCBufs start from RISCV B, and then one PCBuf goes to each of RISCV T0 / T1 / T2. PCBufs cannot be accessed by RISCV NC nor by the NoC nor by the Tensix coprocessor. Each PCBuf is a FIFO queue of 32-bit values, along with 10 bits of configuration. Each FIFO queue can hold up to 16 32-bit values; attempting to push more values than this will cause the writes to sit in shared buffers within the RISCV B memory subsystem. If those shared buffers become full, RISCV B will be stalled until space becomes available.

See also [Mailboxes](Mailboxes.md) for separate FIFO queues between RISCV cores.

## Memory map

The PCBufs are variously mapped into address space of RISCV B / T0 / T1 / T2:

<table><thead><tr><th/><th><code>PCBuf[0]</code></th><th><code>PCBuf[1]</code></th><th><code>PCBuf[2]</code></th></tr></thead>
<tr><th>RISCV B</th><td><code>PC_BUF_BASE</code> (RISCV B only)<br/><code>0xFFE8_0000</code> to <code>0xFFE8_FFFF</code></td><td><code>PC1_BUF_BASE</code> (RISCV B only)<br/><code>0xFFE9_0000</code> to <code>0xFFE9_FFFF</code></td><td><code>PC2_BUF_BASE</code> (RISCV B only)<br/><code>0xFFEA_0000</code> to <code>0xFFEA_FFFF</code></td>
<tr><th>RISCV T<sub>i</sub></th><td><code>PC_BUF_BASE</code> (RISCV T0 only)<br/><code>0xFFE8_0000</code> to <code>0xFFE8_0003</code></td><td><code>PC_BUF_BASE</code> (RISCV T1 only)<br/><code>0xFFE8_0000</code> to <code>0xFFE8_0003</code></td><td><code>PC_BUF_BASE</code> (RISCV T2 only)<br/><code>0xFFE8_0000</code> to <code>0xFFE8_0003</code></td></tr></table>

The behavior of a memory access against a PCBuf depends on the issuing RISCV and whether the access is a read or a write:

<table><thead><tr><th/><th>Write Behavior</th><th>Read Behavior</th></tr></thead>
<tr><th>RISCV B</th><td><pre><code>while PCBuf[i].FIFO.full:
  wait
PCBuf[i].FIFO.push(write_value)</code></pre></td><td><pre><code>while True:
  if PCBuf[i].OverrideEn:
    if PCBuf[i].OverrideBusy:
      return 0
  if PCBuf[i].FIFO.empty:
    if RISCV T<sub>i</sub> is waiting to read from PC_BUF_BASE:
      if Tensix T<sub>i</sub> is idle:
        return 0
  wait</code></pre></td></tr>
<tr><th>RISCV T<sub>i</sub></th><td>Write is discarded</td><td><pre><code>while PCBuf[i].FIFO.empty:
  if PCBuf[i].OverrideEn:
    return PCBuf[i].OverrideValue
  wait
return PCBuf[i].FIFO.pop()</code></pre></td></tr>
</table>

Note that the `wait`s in the above happen within the memory subsystem; they prevent the memory region in question from processing the next request, but they do not _necessarily_ prevent the issuing RISCV from executing some more RISCV instructions.

The RISCV B read behavior is particularly interesting, as it waits for all three of:
1. `PCBuf[i].FIFO.empty`, i.e. for RISCV T<sub>i</sub> to have popped all the values pushed by RISCV B.
2. RISCV T<sub>i</sub> to be performing a read against <code>PC_BUF_BASE</code> and be blocked waiting due to `PCBuf[i].FIFO` being empty.
3. Tensix T<sub>i</sub> to be idle, i.e. for the Tensix coprocessor to not have any in-flight instructions from Tensix thread T<sub>i</sub>. This is the same thing that RISCV T<sub>i</sub> can wait for via the [`CoprocessorDoneCheck` of TTSync](TTSync.md#coprocessordonecheck).

## Memory ordering

When writing to a PCBuf, it is usually the case that the programmer wants the PCBuf write-request to be processed _after_ all earlier write-requests have been processed. When reading from a PCBuf, it is usually the case that the programmer wants the PCBuf read-response to be obtained _before_ any later memory requests are emitted. Neither of these things happen by default; see [memory ordering](MemoryOrdering.md) for details on how to avoid race conditions and ensure that they do happen.

## Configuration bits

The configuration bits for all three PCBufs sit in the `RISCV_DEBUG_REG_TRISC_PC_BUF_OVERRIDE` register, within the "Tile control / debug / status registers" memory region, with the bits of that register mapped as:

|Starting bit index|Type|Name|
|--:|---|---|
|0|`bool`|`PCBuf[0].OverrideEn`|
|1|`bool`|`PCBuf[0].OverrideBusy`|
|2|`uint8`|`PCBuf[0].OverrideValue`|
|10|`bool`|`PCBuf[1].OverrideEn`|
|11|`bool`|`PCBuf[1].OverrideBusy`|
|12|`uint8`|`PCBuf[1].OverrideValue`|
|20|`bool`|`PCBuf[2].OverrideEn`|
|21|`bool`|`PCBuf[2].OverrideBusy`|
|22|`uint8`|`PCBuf[2].OverrideValue`|
|30|`bool`|Reserved|
|31|`bool`|Reserved|

Note that the `OverrideEn` and `OverrideBusy` configuration can also affect [TTSync](TTSync.md).
