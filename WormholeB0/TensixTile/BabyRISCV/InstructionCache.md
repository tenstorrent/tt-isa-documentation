# Instruction Cache

Each RISCV has a little instruction cache between it and L1. Instructions are automatically pulled into this cache as required, and a hardware prefetcher also tries to pull things in ahead of them being required. If the RISCV NC [Instruction RAM](InstructionRAM.md) is in use, then that RAM capacity is entirely additive to the cache capacity: instructions fetched from it do not consume any cache space, nor is a cache invalidation required when changing its contents. The capacities are:

||RISCV B|RISCV T0|RISCV T1|RISCV T2|RISCV NC|
|---|---|---|---|---|---|
|**Instruction cache ‡**|2 KiB|2 KiB|512 bytes|2 KiB|512 bytes|
|**Instruction RAM**|None|None|None|None|16 KiB|

‡ Calculated as (4 bytes) times (maximum number of instructions that can be held in the cache). Additional memory is required for tracking _which_ addresses are present in the cache, but that additional memory is not counted here.

## Prefetcher

Some configuration fields are available to constrain the instruction cache prefetcher, all of which live within [Tensix backend configuration](../TensixCoprocessor/BackendConfiguration.md). The prefetcher can be outright disabled, or the maximum number of in-flight prefetches can be set, or a limit address can be set: if the limit address is set to a non-zero value, then the prefetcher will only fetch instructions at addresses less than or equal to the limit address.
<table><thead><tr><th/><th>RISCV B</th><th>RISCV T0</th><th>RISCV T1</th><th>RISCV T2</th><th>RISCV NC</th></tr></thead>
<tr><th>Enable register</th><td><code>RISC_PREFETCH_CTRL_Enable_Brisc</code></td><td colspan="3"><code>RISC_PREFETCH_CTRL_Enable_Trisc</code> (three bits; one per core)</td><td><code>RISC_PREFETCH_CTRL_Enable_NocRisc</code></td></tr>
<tr><th>Maximum in-flight prefetches</th><td colspan="5"><code>RISC_PREFETCH_CTRL_Max_Req_Count</code> (single value shared by all five cores)</td></tr>
<tr><th>Limit address</th><td><code>BRISC_END_PC_PC</code></td><td><code>RISC_END_PC_SEC0_PC</code></td><td><code>RISC_END_PC_SEC1_PC</code></td><td><code>RISC_END_PC_SEC2_PC</code></td><td><code>NOC_RISC_END_PC_PC</code></td></tr>
</table>

## Cache invalidation

The baby RISCV cores do *not* implement the `Zifencei` extension, and thus the `fence.i` instruction is *not* available and cannot be used to flush the instruction cache. If executed, it'll be treated as if it were a `nop` instruction; this is a NonContractualBehavior and should not be relied upon.

Instead, the instruction cache is cleared during [reset](../SoftReset.md#riscv-soft-reset), and can also be cleared by writing to the `RISCV_IC_INVALIDATE_InvalidateAll` field within [Tensix backend configuration](../TensixCoprocessor/BackendConfiguration.md). Note that this is _not_ accessible over the NoC, nor is it accessible to RISCV NC, so RISCV NC cannot clear its own instruction cache (nor anyone else's) by itself.

If writing new instructions to L1 and then writing to `RISCV_IC_INVALIDATE_InvalidateAll` to flush the instruction cache, [memory ordering](MemoryOrdering.md) rules should be consulted to ensure that the write-requests to L1 are processed _before_ the write-request to `RISCV_IC_INVALIDATE_InvalidateAll` is processed, otherwise the flush could happen before the new instructions are written, and speculative instruction fetches due to the hardware prefetcher and/or branch predictor could repopulate the cache with old instructions. One robust instruction sequence is:

```
sw t0, 0(t1)   # Write new instruction to L1
lw t2, 0(t1)   # Read back from same address
addi x0, t2, 0 # Consume result of load
sw t3, 0(t4)   # Write to RISCV_IC_INVALIDATE_InvalidateAll
```

Writing to `RISCV_IC_INVALIDATE_InvalidateAll` does _not_ flush the RISCV instruction pipeline, so although the cache will have been cleared, any in-flight instructions will already have read from the cache. As such, following a write to `RISCV_IC_INVALIDATE_InvalidateAll`, the RISCVs which had their caches invalidated might need to execute up to 20 additional instructions to ensure that the pipeline does not contain any stale cache contents.
