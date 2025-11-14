# Tensix Backend Configuration

Instruction descriptions assume the presence of the following pair of global variables, which are also mapped (one immediately after the other) into the address space of RISCV B / T0 / T1 / T2 starting at address `TENSIX_CFG_BASE`:

```c
uint32_t Config[2][CFG_STATE_SIZE * 4];
struct {uint16_t Value, Padding[7];} ThreadConfig[3][THD_STATE_SIZE];
```

The `ThreadConfig` variable contains assorted thread-specific configuration fields, with one bank per Tensix thread. In instruction descriptions, `ThreadConfig[i].Field` is shorthand for `(ThreadConfig[i][Field_ADDR32].Value & Field_MASK) >> Field_SHAMT`. The `[3]` is always indexed as `[CurrentThread]`, so that Tensix thread T0 accesses `ThreadConfig[0]`, Tensix thread T1 accesses `ThreadConfig[1]`, and Tensix thread T2 accesses `ThreadConfig[2]`.

The `Config` variable contains assorted thread-agnostic configuration fields, with two banks (any Tensix thread can access any bank). In instruction descriptions, `Config[i].Field` is shorthand for `(Config[i][Field_ADDR32] & Field_MASK) >> Field_SHAMT`.

Additionally:
- `Config[i].Packers[0].Field` is `Config[i].THCON_SEC0_REG1_Field`
- `Config[i].Packers[1].Field` is `Config[i].THCON_SEC0_REG8_Field`
- `Config[i].Packers[2].Field` is `Config[i].THCON_SEC1_REG1_Field`
- `Config[i].Packers[3].Field` is `Config[i].THCON_SEC1_REG8_Field`

See [`cfg_defines.h`](https://github.com/tenstorrent/tt-metal/blob/bc8bf6c8d8533501480d9154777749abe1ed846a/tt_metal/hw/inc/wormhole/wormhole_b0_defines/cfg_defines.h) for all of the `Field_ADDR32`, `Field_MASK`, and `Field_SHAMT` values. Note that `cfg_defines.h` is divided up into multiple sections; the `// Registers for THREAD` section is for indexing into `ThreadConfig`, whereas all of the other sections are for indexing into `Config`.

Different instructions are used to access these two variables:

||Thread-agnostic configuration (`Config`)|Thread-specific configuration (`ThreadConfig`)|
|---|---|---|
|**Tensix implicit read**|Various instructions|Various instructions|
|**Tensix explicit read**|`RDCFG`|No explicit reads|
|**Tensix write**|[`WRCFG`](WRCFG.md), [`RMWCIB`](RMWCIB.md), [`REG2FLOP`](REG2FLOP_Configuration.md) (‡)|[`SETC16`](SETC16.md)|
|**RISCV read**|`lw`, `lh`, `lhu`, `lb`, `lbu`|`lw`, `lh`, `lhu`, `lb`, `lbu`|
|**RISCV write**|`sw` only|No RISCV writes|

(‡) `REG2FLOP` can only be used to write to a subset of the thread-agnostic configuration.

## RISCV writes to `Config`

Although RISCV cores can use `sw` instructions to write to `Config`, the programmer needs to be aware that RISCV execution and Tensix execution proceed asynchronously from each other: once a Tensix instruction has been pushed, it will _eventually_ execute, but a variable number of RISCV instructions might execute before the Tensix instruction executes. The programmer also needs to be aware that the RISCV cores can reorder memory writes if the writes are against different memory regions. Race conditions can arise if the programmer does not consider the dangers in the below paragraphs.

**Danger one:** `sw` to write to `Config`, followed by `sw` to push a Tensix instruction intending to consume this configuration. By default, these two writes can be reordered, causing the Tensix instruction to execute without the new configuration. To guarantee race-free operation, one of the following approaches is recommended:
* Push a Tensix [`WRCFG`](WRCFG.md) or [`RMWCIB`](RMWCIB.md) or [`REG2FLOP`](REG2FLOP_Configuration.md) instruction to perform the configuration write, instead of using a RISCV `sw` instruction.
* Push a [`STALLWAIT`](STALLWAIT.md) instruction after writing to `Config` and before pushing the instruction of interest, where the `STALLWAIT` specifies condition C13 and specifies a block mask which will cause the instruction of interest to wait for that condition.
* Use RISCV [memory ordering](../BabyRISCV/MemoryOrdering.md) techniques to ensure that the write to `Config` has _finished_ before the write to push a Tensix instruction _starts_. One possible sequence of instructions for this is:
```
sw t0, 0(t1)   # Write to Tensix Backend Configuration
lw t2, 0(t1)   # Read back from same address; guaranteed to finish after the store finishes
addi x0, t2, 0 # Consume result of load; guarantees subsequent instructions cannot begin until load finishes
sw t3, 0(t4)   # Push Tensix instruction
```

**Danger two:** `sw` to push a Tensix instruction, followed by `sw` to write to `Config`, where that configuration is intended to be consumed only by future instructions. By default, the instruction pushed _before_ the configuration write might execute _after_ the configuration write, and thus consume the new configuration when it wasn't meant to. To guard against this, RISCV code needs to ensure that the pushed Tensix instruction has started (or ideally finished) execution before performing the `sw` to write to `Config`.

## Special cases

RISCV cores cannot directly write to `ThreadConfig` using store instructions. Instead they need to push a [`SETC16`](SETC16.md) instruction.

The [`REG2FLOP`](REG2FLOP_Configuration.md) instruction can only write to `Config[i][j]` when `THCON_CFGREG_BASE_ADDR32 ≤ j < GLOBAL_CFGREG_BASE_ADDR32`.

Writes to `Config[i][j]` with `j >= GLOBAL_CFGREG_BASE_ADDR32` will write to _both_ `Config[0][j]` and `Config[1][j]`. Instruction descriptions therefore often use the shorthand `Config.Field` when `Field_ADDR32 >= GLOBAL_CFGREG_BASE_ADDR32`, as there is only ever one value of the field.

In most cases, writes to `Config` or `ThreadConfig` will be picked up by a subsequent Tensix instruction which (either implicitly or explicitly) reads from `Config` or `ThreadConfig`. However, in a few cases writes cause an immediate effect:
  * Writing _anything_ to `Config[i][STATE_RESET_EN_ADDR32]` (except via `RMWCIB`) is equivalent to an instantaneous `for (unsigned j = 0; j < GLOBAL_CFGREG_BASE_ADDR32; ++j) Config[i][j] = 0;`.
  * Writing a value to `Config.PRNG_SEED_Seed_Val_ADDR32` will use that value to (re-)seed all the PRNGs.
  * Writing a mask to `Config.RISCV_IC_INVALIDATE_InvalidateAll` will invalidate the instruction caches of the baby RISCV cores identified by the mask (bit 0 for RISCV B, bit 1 for RISCV T0, bit 2 for RISCV T1, bit 3 for RISCV T2, bit 4 for RISCV NC).
  * Writing to any of `ThreadConfig[i][CG_CTRL_EN_Regblocks_ADDR32]` or `ThreadConfig[i][CG_CTRL_EN_Hyst_ADDR32]` or `ThreadConfig[i][CG_CTRL_KICK_Regblocks_ADDR32]` (using `SETC16`) will have an immediate effect on the clock gaters.
  * Writing to `ThreadConfig[i][UNPACK_MISC_CFG_CfgContextCntReset_0_ADDR32]` or `ThreadConfig[i][UNPACK_MISC_CFG_CfgContextCntReset_1_ADDR32]` (using `SETC16`) will reset the unpacker configuration context counters associated with thread `i`.

A few configuration fields affect RISCV cores rather than affecting backend execution:
  * `Config[0].DISABLE_RISC_BP_Disable_main`, `Config[0].DISABLE_RISC_BP_Disable_trisc`, and `Config[0].DISABLE_RISC_BP_Disable_ncrisc` are used to entirely disable the RISCV branch predictors.
  * `Config[0].DISABLE_RISC_BP_Disable_bmp_clear_main`, `Config[0].DISABLE_RISC_BP_Disable_bmp_clear_trisc`, and `Config[0].DISABLE_RISC_BP_Disable_bmp_clear_ncrisc` are used to partially disable one feature of the RISCV branch predictors. The RISCV cores are not designed to operate with a partially disabled branch predictor, so software should leave these fields set to false.
  * `Config.TRISC_RESET_PC_OVERRIDE_Reset_PC_Override_en`, `Config.TRISC_RESET_PC_SEC0_PC`, `Config.TRISC_RESET_PC_SEC1_PC`, and `Config.TRISC_RESET_PC_SEC2_PC` affect the initial value of `pc` when RISCV T0 / T1 / T2 come out of reset.
  * `Config.NCRISC_RESET_PC_OVERRIDE_Reset_PC_Override_en` and `Config.NCRISC_RESET_PC_PC` affect the initial value of `pc` when RISCV NC comes out of reset.
  * `Config.BRISC_END_PC_PC`, `Config.TRISC_END_PC_SEC0_PC`, `Config.TRISC_END_PC_SEC1_PC`, `Config.TRISC_END_PC_SEC2_PC`, and `Config.NOC_RISC_END_PC_PC` configure an address upper bound for the RISCV instruction cache prefetchers.
  * `Config.RISC_PREFETCH_CTRL_Enable_Brisc`, `Config.RISC_PREFETCH_CTRL_Enable_Trisc`, and `Config.RISC_PREFETCH_CTRL_Enable_NocRisc` are used to enable/disable the RISCV instruction cache prefetchers.
  * `RISC_PREFETCH_CTRL_Max_Req_Count` is used to limit the number of in-flight requests each RISCV instruction cache prefetcher can have.

## Other configuration spaces

Though most configuration lives in either `Config` or `ThreadConfig`, some configuration lives elsewhere:
* The [Replay Expanders](REPLAY.md) are configured in-band using (a mode of) the [`REPLAY`](REPLAY.md) instruction.
* The [MOP Expanders](MOPExpander.md) have separate write-only configuration mapped into the RISCV address space.
* The majority of the configuration for the Vector Unit (SFPU) lives in its `LaneConfig` and `LoadMacroConfig`, which is set in-band using [`SFPCONFIG`](SFPCONFIG.md).
* A few pieces of packer and unpacker configuration are set exclusively via [TDMA-RISC](../TDMA-RISC.md).
* Packers and unpackers make use of [ADCs](ADCs.md), which are technically auto-incrementable addressing counters rather than configuration, but similarly act as implicit state used by an instruction.
* Matrix Unit (FPU) and Vector Unit (SFPU) instructions make use of [RWCs](RWCs.md), which are technically auto-incrementable addressing counters rather than configuration, but similarly act as implicit state used by an instruction.

## Debug registers

`Config` and `ThreadConfig` are not mapped into the address space of RISCV NC, nor into the address space visible to the NoC, but debug functionality exists to allow these clients to read backend configuration: if the value `x` is written to `RISCV_DEBUG_REG_CFGREG_RD_CNTL`, then a few cycles later, hardware will perform the equivalent of `RISCV_DEBUG_REG_CFGREG_RDDATA = ((uint32_t*)TENSIX_CFG_BASE)[x & 0x7ff]`. This pair of debug registers exists in the "Tile control / debug / status registers" memory region, which is accessible to all RISCV cores and to external clients via the NoC.
