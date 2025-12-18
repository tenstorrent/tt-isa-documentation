# Instruction Cache

Each baby RISCV has a little instruction cache between it and L1. Instructions are automatically pulled into this cache as required, and a hardware prefetcher also tries to pull things in ahead of them being required. If the [Instruction RAM](InstructionRAM.md) is in use, then that RAM capacity is entirely additive to the cache capacity: instructions fetched from it do not consume any cache space, nor is a cache invalidation required when changing its contents. The capacities are:

||RISCV E|
|---|---|
|**Instruction cache ‡**|512 bytes|
|**Instruction RAM**|16 KiB|

‡ Calculated as (4 bytes) times (maximum number of instructions that can be held in the cache). Additional memory is required for tracking _which_ addresses are present in the cache, but that additional memory is not counted here.

## Prefetcher

Some configuration fields are available to constrain the instruction cache prefetcher. The prefetcher can be outright disabled, or the maximum number of in-flight prefetches can be set, or a limit address can be set: if the limit address is set to a non-zero value, then the prefetcher will only fetch instructions at addresses less than or equal to the limit address.
<table><thead><tr><th/><th>RISCV E</th></tr></thead>
<tr><th>Enable register</th><td><code>ETH_RISC_PREFECTH_CTRL</code>, low bit</td></tr>
<tr><th>Maximum in-flight prefetches</th><td><code>ETH_RISC_PREFECTH_CTRL</code>, bits 8 through 15</td></tr>
<tr><th>Limit address</th><td><code>ETH_RISC_PREFECTH_PC</code></td></tr>
</table>

## Cache invalidation

The baby RISCV cores do *not* implement the `Zifencei` extension, and thus the `fence.i` instruction is *not* available and cannot be used to flush the instruction cache. If executed, it'll be treated as if it were a `nop` instruction; this is a NonContractualBehavior and should not be relied upon.

The instruction cache is only cleared during [reset](../SoftReset.md#riscv-soft-reset), though it is also possible to trash the entire contents of the cache by executing 128 instructions from consecutive addresses in L1.
