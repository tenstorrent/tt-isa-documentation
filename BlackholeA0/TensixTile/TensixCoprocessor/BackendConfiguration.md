# Tensix Backend Configuration

Instruction descriptions assume the presence of the global variables `Config` and `ThreadConfig`, which along with `ConfigDualWrite` are mapped (one immediately after the other) into the address space of RISCV B / T0 / T1 / T2 starting at address `TENSIX_CFG_BASE`:

```c
uint32_t Config[2][CFG_STATE_SIZE * 4];
uint32_t ConfigDualWrite[CFG_STATE_SIZE * 4];
struct {uint16_t Value, Padding;} ThreadConfig[3][THD_STATE_SIZE];
```

The `ThreadConfig` variable contains assorted thread-specific configuration fields, with one bank per Tensix thread. In instruction descriptions, `ThreadConfig[i].Field` is shorthand for `(ThreadConfig[i][Field_ADDR32].Value & Field_MASK) >> Field_SHAMT`. The `[3]` is always indexed as `[CurrentThread]`, so that Tensix thread T0 accesses `ThreadConfig[0]`, Tensix thread T1 accesses `ThreadConfig[1]`, and Tensix thread T2 accesses `ThreadConfig[2]`.

The `Config` variable contains assorted thread-agnostic configuration fields, with two banks (any Tensix thread can access any bank). In instruction descriptions, `Config[i].Field` is shorthand for `(Config[i][Field_ADDR32] & Field_MASK) >> Field_SHAMT`.

Writes to `ConfigDualWrite[j]` are equivalent to simultaneously writing to both `Config[0][j]` and `Config[1][j]`. Reads from `ConfigDualWrite` are `UnsupportedFunctionality`; in practice, a read from `ConfigDualWrite[j]` is equivalent to reading from `Config[0][j]`.

See [`cfg_defines.h`](https://github.com/tenstorrent/tt-metal/blob/81989dcdb8f9b340c932ae7a71a346f4f08703eb/tt_metal/hw/inc/blackhole/cfg_defines.h) for all of the `Field_ADDR32`, `Field_MASK`, and `Field_SHAMT` values. Note that `cfg_defines.h` is divided up into multiple sections; the `// Registers for THREAD` section is for indexing into `ThreadConfig`, whereas all of the other sections are for indexing into `Config`.

Different instructions are used to access these variables:

||Thread-agnostic configuration (`Config`)|Thread-specific configuration (`ThreadConfig`)|
|---|---|---|
|**Tensix&nbsp;implicit&nbsp;read**|Various instructions|Various instructions|
|**Tensix&nbsp;explicit&nbsp;read**|`RDCFG`, [`CFGSHIFTMASK`](CFGSHIFTMASK.md)|No explicit reads|
|**Tensix write**|[`WRCFG`](WRCFG.md), [`STREAMWRCFG`](STREAMWRCFG.md),<br/>[`RMWCIB`](RMWCIB.md), [`CFGSHIFTMASK`](CFGSHIFTMASK.md)|[`SETC16`](SETC16.md)|
|**RISCV read**|`lw`, `lh`, `lhu`, `lb`, `lbu`|`lw`, `lh`, `lhu`, `lb`, `lbu`|
|**RISCV write**|`sw` only|No RISCV writes|

## RISCV writes to `Config`

On Wormhole, the programmer had to take care to avoid race conditions when mixing writes to `Config` with writes to push Tensix instructions. On Blackhole, Auto TTSync should cause any such mixing to be fine: the hardware will automatically stall any problematic writes whilst it waits for earlier conflicting writes to complete.

## Special cases

RISCV cores cannot directly write to `ThreadConfig` using store instructions. Instead they need to push a [`SETC16`](SETC16.md) instruction.

Writes to `Config[i][j]` with `j >= GLOBAL_CFGREG_BASE_ADDR32` will write to _both_ `Config[0][j]` and `Config[1][j]`. Instruction descriptions therefore often use the shorthand `Config.Field` when `Field_ADDR32 >= GLOBAL_CFGREG_BASE_ADDR32`, as there is only ever one value of the field.

In most cases, writes to `Config` or `ThreadConfig` will be picked up by a subsequent Tensix instruction which (either implicitly or explicitly) reads from `Config` or `ThreadConfig`. However, in a few cases writes cause an immediate effect:
  * Writing _anything_ to `Config[i][STATE_RESET_EN_ADDR32]` (except via `RMWCIB`) is equivalent to an instantaneous `for (unsigned j = 0; j < GLOBAL_CFGREG_BASE_ADDR32; ++j) Config[i][j] = 0;`.
  * Writing a value to `Config.PRNG_SEED_Seed_Val_ADDR32` will use that value to (re-)seed all the PRNGs.
  * Writing a mask to `Config.RISCV_IC_INVALIDATE_InvalidateAll` will invalidate the instruction caches of the baby RISCV cores identified by the mask (bit 0 for RISCV B, bit 1 for RISCV T0, bit 2 for RISCV T1, bit 3 for RISCV T2, bit 4 for RISCV NC).
  * Writing to `ThreadConfig[i][UNPACK_MISC_CFG_CfgContextCntReset_0_ADDR32]` or `ThreadConfig[i][UNPACK_MISC_CFG_CfgContextCntReset_1_ADDR32]` (using `SETC16`) will reset the unpacker configuration context counters associated with thread `i`.

A few configuration fields affect RISCV cores rather than affecting backend execution:
  * `Config[0].DISABLE_RISC_BP_Disable_main`, `Config[0].DISABLE_RISC_BP_Disable_trisc`, and `Config[0].DISABLE_RISC_BP_Disable_ncrisc` are used to entirely disable the RISCV branch predictors.
  * `Config[0].DISABLE_RISC_BP_Disable_bmp_clear_main`, `Config[0].DISABLE_RISC_BP_Disable_bmp_clear_trisc`, and `Config[0].DISABLE_RISC_BP_Disable_bmp_clear_ncrisc` are used to partially disable one feature of the RISCV branch predictors. The RISCV cores are not designed to operate with a partially disabled branch predictor, so software should leave these fields set to false.
  * `Config.BRISC_END_PC_PC`, `Config.TRISC_END_PC_SEC0_PC`, `Config.TRISC_END_PC_SEC1_PC`, `Config.TRISC_END_PC_SEC2_PC`, and `Config.NOC_RISC_END_PC_PC` configure an address upper bound for the RISCV instruction cache prefetchers.
  * `Config.RISC_PREFETCH_CTRL_Enable_Brisc`, `Config.RISC_PREFETCH_CTRL_Enable_Trisc`, and `Config.RISC_PREFETCH_CTRL_Enable_NocRisc` are used to enable/disable the RISCV instruction cache prefetchers.
  * `Config.RISC_PREFETCH_CTRL_Max_Req_Count` is used to limit the number of in-flight requests each RISCV instruction cache prefetcher can have.
  * `Config[i].RISC_DEST_ACCESS_CTRL_SEC[j].no_swizzle`, `Config[i].RISC_DEST_ACCESS_CTRL_SEC[j].unsigned_int`, and `Config[i].RISC_DEST_ACCESS_CTRL_SEC[j].fmt` are used to configure [how `Dst` is exposed to RISCV T0 / T1 / T2](Dst.md#riscv-access-to-dst).
  * `ThreadConfig[i].TENSIX_TRISC_SYNC_TrackGlobalCfg`, `ThreadConfig[i].TENSIX_TRISC_SYNC_EnSubdividedCfgForUnpacr`, `ThreadConfig[i].TENSIX_TRISC_SYNC_TrackGPR`, `ThreadConfig[i].TENSIX_TRISC_SYNC_TrackTDMARegs`, and `ThreadConfig[i].TENSIX_TRISC_SYNC_TrackTensixInstructions` are used to configure Auto TTSync (along with the `RESOURCEDECL` instruction).

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
