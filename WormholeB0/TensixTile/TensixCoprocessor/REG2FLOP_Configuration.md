# `REG2FLOP` (Move from GPRs to THCON configuration)

**Summary:** Use the Scalar Unit (ThCon) to write to thread-agnostic backend configuration, but only for fields whose name starts with `THCON_`. In most cases, the [`WRCFG`](WRCFG.md) instruction should be used instead, unless explicitly trying to avoid contention around the [Configuration Unit](ConfigurationUnit.md).

**Backend execution unit:** [Scalar Unit (ThCon)](ScalarUnit.md)

## Syntax

```c
TT_REG2FLOP(/* u2 */ SizeSel, 0, 0, 0, /* u7 */ ThConCfgIndex, /* u6 */ InputReg)
```

## Encoding

![](../../../Diagrams/Out/Bits32_REG2FLOP_Configuration.svg)

## Functional model

```c
if (TTArchitecture == Blackhole) {
  UnsupportedFunctionality(); // No known usage, confidence in specification below is weak
}
if (ThConCfgIndex >= (GLOBAL_CFGREG_BASE_ADDR32 - THCON_CFGREG_BASE_ADDR32)) {
  // Can only write to backend configuration whose field name starts with THCON_.
  // See WRCFG for a similar instruction without this limitation.
  UndefinedBehavior();
}

uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
uint32_t* ThConCfgBase = &Config[StateID][THCON_CFGREG_BASE_ADDR32];

if (SizeSel == 0) {
  UnsupportedFunctionality(); // No known usage, confidence in specification below is weak
  // 128 bit configuration write
  memcpy(&ThConCfgBase[ThConCfgIndex & ~3], &GPRs[CurrentThread][InputReg & ~3], 16);
} else {
  // 32 bit configuration write
  ThConCfgBase[ThConCfgIndex] = GPRs[CurrentThread][InputReg];
}
```

## Performance

This instruction usually takes two cycles, though it will take longer if [Configuration Unit](ConfigurationUnit.md) instructions (from any Tensix thread or any baby RISCV) are contending for write bandwidth to THCON configuration. The instruction occupies the [Scalar Unit (ThCon)](ScalarUnit.md) for the entire duration, and the issuing thread will be blocked from issuing subsequent instructions for the entire duration.

## Instruction scheduling

Software must ensure that the instruction immediately after `REG2FLOP` is not trying to consume the configuration written by the `REG2FLOP` instruction. A NOP instruction can be inserted to ensure this (any kind of Tensix NOP suffices, though plain `NOP` is conventional).

[`PACR`](PACR.md) is an exception: a `PACR` immediately after `REG2FLOP`, with or without `Flush`, sees the new value of any packer configuration the `REG2FLOP` wrote (e.g. `L1_Dest_addr`), as the `REG2FLOP` holds its thread until its write is done, and the packers read no configuration for a `PACR` before they accept it. In the other direction, a `PACR` before a `REG2FLOP` sees the old value even when the packers are still busy with earlier work, as the `REG2FLOP` can't start until the packers have accepted that `PACR`. So the usual way of moving the packers to their next tile, a `REG2FLOP` of `L1_Dest_addr` followed at once by a `PACR` with `Flush` and then the tile's `PACR`s, needs no NOP.
