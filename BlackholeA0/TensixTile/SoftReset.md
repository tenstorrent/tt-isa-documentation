# Soft Reset

> [!CAUTION]
> There is no hardware functionality for atomically setting or clearing individual bits of any of the registers described on this page, so software needs to perform read-modify-write sequences, and software needs to enforce its own mutual exclusion if it wants such sequences to be free of data races.

## `RISCV_DEBUG_REG_SOFT_RESET_0`

**Address:** `0xFFB1_21B0`

|Bit index|Purpose|
|--:|---|
|0|[Unpacker soft reset](#unpacker-soft-reset)|
|1|[Unpacker soft reset](#unpacker-soft-reset)|
|2|[Packer 0 soft reset](#packer-soft-reset)|
|3|[Packer 1 soft reset](#packer-soft-reset)|
|4|[Packer 2 soft reset](#packer-soft-reset)|
|5|[Packer 3 soft reset](#packer-soft-reset)|
|6|[Mover soft reset](#mover-soft-reset)|
|7|[Unpacker soft reset](#unpacker-soft-reset)|
|8|[TDMA-RISC soft reset](#tdma-risc-soft-reset) and [glue soft reset](#glue-soft-reset)|
|9|[THCON configuration soft reset](#thcon-configuration-soft-reset) and [Scalar Unit (ThCon) soft reset](#scalar-unit-thcon-soft-reset)|
|10|[Matrix Unit (FPU) soft reset](#matrix-unit-fpu-soft-reset) and [Vector Unit (SFPU) soft reset](#vector-unit-sfpu-soft-reset) and [SrcA data soft reset](#srca-data-soft-reset) (all columns)|
|11|[RISCV B soft reset](#riscv-soft-reset)|
|12|[RISCV T0 soft reset](#riscv-soft-reset)|
|13|[RISCV T1 soft reset](#riscv-soft-reset)|
|14|[RISCV T2 soft reset](#riscv-soft-reset)|
|15|[`SrcA` `AllowedClient` soft reset](#srca-allowedclient-soft-reset)|
|16|[`SrcB` `AllowedClient` soft reset](#srcb-allowedclient-soft-reset) and [`SrcB` data soft reset](#srcb-data-soft-reset)|
|17|[Packer `Dst` connection soft reset](#packer-dst-connection-soft-reset) and [`ZEROACC` soft reset](#zeroacc-soft-reset)|
|18|[RISCV NC soft reset](#riscv-soft-reset)|
|19|[`SrcA` data soft reset](#srca-data-soft-reset) (columns 0-3)|
|20|[`SrcA` data soft reset](#srca-data-soft-reset) (columns 4-7)|
|21|[`SrcA` data soft reset](#srca-data-soft-reset) (columns 8-11)|
|22|[`SrcA` data soft reset](#srca-data-soft-reset) (columns 12-15)|
|23|Automatic TTSync soft reset|
|≥24|No effect|

## `RISCV_DEBUG_REG_DISABLE_RESET`

**Address:** `0xFFB1_2224`

|Bit index|Purpose|
|--:|---|
|0|If `false`, RISCV T0 soft reset will reset RISCV T0's local data RAM. If `true`, it won't|
|1|If `false`, RISCV T0 soft reset will reset RISCV T0's debug `DR` registers. If `true`, it won't|
|2|If `false`, RISCV T1 soft reset will reset RISCV T1's local data RAM. If `true`, it won't|
|3|If `false`, RISCV T1 soft reset will reset RISCV T1's debug `DR` registers. If `true`, it won't|
|4|If `false`, RISCV T2 soft reset will reset RISCV T2's local data RAM. If `true`, it won't|
|5|If `false`, RISCV T2 soft reset will reset RISCV T2's debug `DR` registers. If `true`, it won't|
|6|If `false`, RISCV B soft reset will reset RISCV B's local data RAM. If `true`, it won't|
|7|If `false`, RISCV B soft reset will reset RISCV B's debug `DR` registers. If `true`, it won't|
|8|If `false`, RISCV NC soft reset will reset RISCV NC's local data RAM. If `true`, it won't|
|9|If `false`, RISCV NC soft reset will reset RISCV NC's debug `DR` registers. If `true`, it won't|
|≥10|No effect|

## `RISCV_DEBUG_REG_TRISC_RESET_PC_OVERRIDE`

**Address:** `0xFFB1_2234`

|Bit index|Purpose|
|--:|---|
|0|If `true`, RISCV T0's initial `pc` when coming out of soft reset will come from `RISCV_DEBUG_REG_TRISC0_RESET_PC`. <br/>If `false`, it'll instead be the fixed value `0x06000`|
|1|If `true`, RISCV T1's initial `pc` when coming out of soft reset will come from `RISCV_DEBUG_REG_TRISC1_RESET_PC`.<br/>If `false`, it'll instead be the fixed value `0x0A000`|
|2|If `true`, RISCV T2's initial `pc` when coming out of soft reset will come from `RISCV_DEBUG_REG_TRISC2_RESET_PC`.<br/>If `false`, it'll instead be the fixed value `0x0E000`|
|≥3|No effect|

## `RISCV_DEBUG_REG_TRISC0_RESET_PC`

**Address:** `0xFFB1_2228`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|32|Initial `pc` for RISCV T0, used when bit #0 of `RISCV_DEBUG_REG_TRISC_RESET_PC_OVERRIDE` is set|

## `RISCV_DEBUG_REG_TRISC1_RESET_PC`

**Address:** `0xFFB1_222C`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|32|Initial `pc` for RISCV T1, used when bit #1 of `RISCV_DEBUG_REG_TRISC_RESET_PC_OVERRIDE` is set|

## `RISCV_DEBUG_REG_TRISC2_RESET_PC`

**Address:** `0xFFB1_2230`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|32|Initial `pc` for RISCV T2, used when bit #2 of `RISCV_DEBUG_REG_TRISC_RESET_PC_OVERRIDE` is set|

## `RISCV_DEBUG_REG_NCRISC_RESET_PC_OVERRIDE`

**Address:** `0xFFB1_223C`

|Bit index|Purpose|
|--:|---|
|0|If `true`, RISCV NC's initial `pc` when coming out of soft reset will come from `RISCV_DEBUG_REG_NCRISC_RESET_PC`.<br/>If `false`, it'll instead be the fixed value `0x12000`|
|≥1|No effect|

## `RISCV_DEBUG_REG_NCRISC_RESET_PC`

**Address:** `0xFFB1_2238`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|32|Initial `pc` for RISCV NC, used when bit #0 of `RISCV_DEBUG_REG_NCRISC_RESET_PC_OVERRIDE` is set|

## RISCV soft reset

Each RISCV core has a single reset bit associated with it, which low-level software can make use of. The constants `RISCV_SOFT_RESET_0_BRISC`, `RISCV_SOFT_RESET_0_TRISCS`, and `RISCV_SOFT_RESET_0_NCRISC` are available as names for the appropriate bit masks.

**Upon entering soft reset:** Any in-flight RISCV instructions are likely to be aborted, though software should not rely on this (especially if soft reset is only asserted for a handful of cycles). For RISCV T<sub>i</sub>, any Tensix instructions either in the T<sub>i</sub> [MOP Expander](TensixCoprocessor/MOPExpander.md) or in the FIFO preceding the MOP Expander will be discarded. Any [mailboxes](BabyRISCV/Mailboxes.md) writable by the RISCV will have their contents discarded. If the appropriate bit of `RISCV_DEBUG_REG_DISABLE_RESET` is `false`, all [debug `DR` registers](BabyRISCV/DebugInterface.md) are set to zero.

**Whilst held in soft reset:** New RISCV instructions will not start. The RISCV frontend will not perform any instruction reads against L1 nor against [core-local instruction RAM](BabyRISCV/InstructionRAM.md). If the appropriate bit of `RISCV_DEBUG_REG_DISABLE_RESET` is `false`, writes to [debug `DR` registers](BabyRISCV/DebugInterface.md) are discarded.

**Upon leaving soft reset:** For RISCV T<sub>i</sub>, the [PCBuf](BabyRISCV/PCBufs.md) from RISCV B to RISCV T<sub>i</sub> will have its FIFO contents discarded. All branch predictor history will be forgotten. The [instruction cache](BabyRISCV/InstructionCache.md) will be invalidated. If the appropriate bit of `RISCV_DEBUG_REG_DISABLE_RESET` is `false`, the local data RAM will begin reinitializing itself to zero. All GPRs and FPRs (and, for RISCV T2, vector registers) will be set to zero, and `pc` will be set according to the below table.

<table><thead><th/><th>Initial <code>pc</code> when coming out of soft reset</th></thead>
<tr><th align="left">RISCV B</th><td align="right"><code>0x00000</code></td></tr>
<tr><th align="left">RISCV T0</th><td align="right"><code>RISCV_DEBUG_REG_TRISC_RESET_PC_OVERRIDE.Bit[0] ? RISCV_DEBUG_REG_TRISC0_RESET_PC : 0x06000</code></td></tr>
<tr><th align="left">RISCV T1</th><td align="right"><code>RISCV_DEBUG_REG_TRISC_RESET_PC_OVERRIDE.Bit[1] ? RISCV_DEBUG_REG_TRISC1_RESET_PC : 0x0A000</code></td></tr>
<tr><th align="left">RISCV T2</th><td align="right"><code>RISCV_DEBUG_REG_TRISC_RESET_PC_OVERRIDE.Bit[2] ? RISCV_DEBUG_REG_TRISC2_RESET_PC : 0x0E000</code></td></tr>
<tr><th align="left">RISCV NC</th><td align="right"><code>RISCV_DEBUG_REG_NCRISC_RESET_PC_OVERRIDE       ? RISCV_DEBUG_REG_NCRISC_RESET_PC : 0x12000</code></td></tr></table>

## `SrcA` data soft reset

All columns of `SrcA` data can be held in reset as part of bit 10, or groups of four columns can be held in reset using bits 19 through 22. Software is encouraged to use [`ZEROSRC`](TensixCoprocessor/ZEROSRC.md) rather than relying heavily on `SrcA` data soft reset.

**Upon entering soft reset:** The relevant columns of `SrcA` (all banks, all rows) will have their data set to zero.

**Whilst held in soft reset:** Instructions writing to the relevant columns of `SrcA` (any bank, any row) will have the writes to those columns discarded.

**Upon leaving soft reset:** No additional action.

## `SrcB` data soft reset

All columns of `SrcB` data can be held in reset as part of bit 16. Software is encouraged to use [`ZEROSRC`](TensixCoprocessor/ZEROSRC.md) rather than relying heavily on `SrcB` data soft reset.

**Upon entering soft reset:** The relevant columns of `SrcB` (all banks, all rows) will have their data set to zero.

**Whilst held in soft reset:** Instructions writing to the relevant columns of `SrcB` (any bank, any row) will have the writes to those columns discarded.

**Upon leaving soft reset:** No additional action.

## `SrcA` `AllowedClient` soft reset

Software is encouraged to use [`CLEARDVALID`](TensixCoprocessor/CLEARDVALID.md) rather than relying heavily on `SrcA` `AllowedClient` soft reset.

**Upon entering soft reset:**
```c
MatrixUnit.SrcABank = 0;
Unpackers[0].SrcBank = 0;
SrcA[0].AllowedClient = SrcClient::Unpackers;
SrcA[1].AllowedClient = SrcClient::Unpackers;
```

**Whilst held in soft reset:** Instructions will be unable to change `MatrixUnit.SrcABank`, `Unpackers[0].SrcBank`, `SrcA[0].AllowedClient`, or `SrcA[1].AllowedClient`.

**Upon leaving soft reset:** No additional action.

## `SrcB` `AllowedClient` soft reset

Software is encouraged to use [`CLEARDVALID`](TensixCoprocessor/CLEARDVALID.md) rather than relying heavily on `SrcB` `AllowedClient` soft reset.

**Upon entering soft reset:**
```c
MatrixUnit.SrcBBank = 0;
Unpackers[1].SrcBank = 0;
SrcB[0].AllowedClient = SrcClient::Unpackers;
SrcB[1].AllowedClient = SrcClient::Unpackers;
```

**Whilst held in soft reset:** Instructions will be unable to change `MatrixUnit.SrcBBank`, `Unpackers[1].SrcBank`, `SrcB[0].AllowedClient`, or `SrcB[1].AllowedClient`.

**Upon leaving soft reset:** No additional action.

## Mover soft reset

**Upon entering soft reset:** Any in-flight [Mover](Mover.md) command / instruction will be aborted.

**Whilst held in soft reset:** Tensix [`XMOV`](TensixCoprocessor/XMOV.md) instructions will be discarded rather than being sent to the mover, [TDMA-RISC](TDMA-RISC.md) mover commands will be discarded rather than being sent to the mover. [`STALLWAIT`](TensixCoprocessor/STALLWAIT.md) condition C12 will observe the mover as having no requests outstanding, TDMA-RISC will observe the mover as not busy.

**Upon leaving soft reset:** No additional action.

## Vector Unit (SFPU) soft reset

**Upon entering soft reset:** Any in-flight [Vector Unit (SFPU)](TensixCoprocessor/VectorUnit.md) instructions will be aborted, and any instructions scheduled for future execution via [`SFPLOADMACRO`](TensixCoprocessor/SFPLOADMACRO.md) will be forgotten.

**Whilst held in soft reset:** New Vector Unit (SFPU) instructions will not start (they might or might not be silently discarded).

**Upon leaving soft reset:** The Vector Unit's PRNG will be reset. All `LaneConfig` and `LoadMacroConfig` will be set to zero. The conditional execution stack will be emptied, and the conditional execution mode will be set to "unconditional". Every mutable [`LReg`](TensixCoprocessor/LReg.md) will be set according to the below table.

<table><thead><tr><th/><th>Value when coming out of soft reset (all lanes)</th></tr></thead>
<tr><th><code>LReg[0]</code><br/>...<br/><code>LReg[7]</code></th><td>Zero</td></tr>
<tr><th><code>LReg[11]</code></th><td><code>-1.0</code> (FP32 format)</td></tr>
<tr><th><code>LReg[12]</code></th><td><code>1.0/65536</code> (FP32 format)</td></tr>
<tr><th><code>LReg[13]</code></th><td><code>-0.67487759</code> (FP32 format)</td></tr>
<tr><th><code>LReg[14]</code></th><td><code>-0.34484843</code> (FP32 format)</td></tr>
<tr><th><code>LReg[16]</code></th><td>Zero</td></tr></table>

## Matrix Unit (FPU) soft reset

**Upon entering soft reset:** Any in-flight [Matrix Unit (FPU)](TensixCoprocessor/MatrixUnit.md) instructions will be aborted.

**Whilst held in soft reset:** New Matrix Unit (FPU) instructions will not start (they might or might not be silently discarded). Unpacker 0 will be unable to write to `Dst`.

**Upon leaving soft reset:** The PRNGs optionally used for stochastic rounding will be reset.

## Unpacker soft reset

Bits 0, 1, and 7 collectively serve as soft reset for both unpackers. If any of these bits is set, then all bits should be. The effects described here apply when all bits are set; the bits are not described individually.

**Upon entering soft reset:** Any in-flight `UNPACR` and `UNPACR_NOP` instructions will be aborted.

**Whilst held in soft reset:** New `UNPACR` and `UNPACR_NOP` instructions will not start (they might or might not be silently discarded). Any in-flight [`STOREIND`](TensixCoprocessor/STOREIND_Src.md) instructions writing to `SrcA` or `SrcB` might behave strangely.

**Upon leaving soft reset:** No additional action.

## Packer soft reset

Each packer has a single reset bit associated with it. Note that bit 17 also affects all packers.

**Upon entering soft reset:** Any in-flight [`PACR`](TensixCoprocessor/PACR.md) and [`PACR_SETREG`](TensixCoprocessor/PACR_SETREG.md) instructions on the relevant packer(s) will be aborted, and any non-empty output buffers sitting before L1 will have their contents discarded. `AccTileSize` and `LastTileSize` will be set to zero on the relevant packer(s) (these are observable via [`SETDMAREG`](TensixCoprocessor/SETDMAREG_Special.md) and via [TDMA-RISC](TDMA-RISC.md)). The metadata output FIFO of the relevant packer(s) will be emptied.

**Whilst held in soft reset:** New [`PACR`](TensixCoprocessor/PACR.md) and [`PACR_SETREG`](TensixCoprocessor/PACR_SETREG.md) instructions will not start on the relevant packer(s) (they might or might not be silently discarded).

**Upon leaving soft reset:** `l1_dest_addr_offset` will be set to zero on the relevant packer(s) (this can be set again via [TDMA-RISC](TDMA-RISC.md), and can be used as part of the [output address generator](TensixCoprocessor/Packers/OutputAddressGenerator.md)).

## Packer `Dst` connection soft reset

Part of bit 17 affects the connection between all packers and `Dst`.

**Upon entering soft reset:** Invokes [the `Reset` function](TensixCoprocessor/Packers/ExponentHistogram.md#functional-model) on the exponent histogram of all four packers (software is encouraged to use [`CLREXPHIST`](TensixCoprocessor/CLREXPHIST.md) for this, rather than relying heavily on soft reset).

**Whilst held in soft reset:** [`PACR`](TensixCoprocessor/PACR.md) instructions reading from `Dst` will behave strangely.

**Upon leaving soft reset:** The PRNGs optionally used for stochastic rounding in the [early format conversion](TensixCoprocessor/Packers/FormatConversion.md) will be reset.

## `ZEROACC` soft reset

**Upon entering soft reset:** Behaves as if a [`ZEROACC`](TensixCoprocessor/ZEROACC.md) instruction was executed with `Mode == ZEROACC_MODE_ALL_OF_DST` and `Revert == true`. In other words, if a `ZEROACC` instruction had previously been used to set any rows of `Dst` to `Undefined`, those rows revert back to whatever value they held before being set to `Undefined`.

**Whilst held in soft reset:** `ZEROACC` instructions are silently discarded.

**Upon leaving soft reset:** No additional action.

## TDMA-RISC soft reset

**Upon entering soft reset:** _Some_ value is assigned to `Unpackers.SetRegBase`, `Packers.SetRegBase`, and `Packers.SetRegHiScaler`. The command queue for instructing the mover is emptied, and the related `CmdParams` array is set to zero.

**Whilst held in soft reset:** All writes to the [TDMA-RISC](TDMA-RISC.md) memory region are silently discarded.

**Upon leaving soft reset:** No additional action.

## Glue soft reset

**Upon entering soft reset:** No particular action.

**Whilst held in soft reset:** New [Scalar Unit (ThCon)](TensixCoprocessor/ScalarUnit.md), [`PACR`](TensixCoprocessor/PACR.md), [`PACR_SETREG`](TensixCoprocessor/PACR_SETREG.md), `UNPACR`, `UNPACR_NOP`, and [`XMOV`](TensixCoprocessor/XMOV.md) instructions will not start, and any such in-flight instructions accessing L1 might behave strangely.

**Upon leaving soft reset:** No additional action.

## THCON configuration soft reset

Software is encouraged to use [`STATE_RESET_EN_ADDR32`](TensixCoprocessor/BackendConfiguration.md#special-cases) rather than relying heavily on THCON configuration soft reset.

**Upon entering soft reset:**
```c
for (unsigned j = THCON_CFGREG_BASE_ADDR32; j < GLOBAL_CFGREG_BASE_ADDR32; ++j) {
  Config[0][j] = 0;
  Config[1][j] = 0;
}
```

**Whilst held in soft reset:** All writes to `Config[i][j]` with `THCON_CFGREG_BASE_ADDR32 ≤ j < GLOBAL_CFGREG_BASE_ADDR32` are silently discarded.

**Upon leaving soft reset:** No additional action.

## Scalar Unit (ThCon) soft reset

**Upon entering soft reset:** Any in-flight [Scalar Unit (ThCon)](TensixCoprocessor/ScalarUnit.md) instruction taking more than one cycle to execute is likely to be aborted, though software should not rely on this (especially if soft reset is only asserted for a handful of cycles).

**Whilst held in soft reset:** [`DMANOP`](TensixCoprocessor/DMANOP.md) and [`SETDMAREG`](TensixCoprocessor/SETDMAREG.md) instructions can execute, but other [Scalar Unit (ThCon)](TensixCoprocessor/ScalarUnit.md) instructions will not start.

**Upon leaving soft reset:** No additional action.
