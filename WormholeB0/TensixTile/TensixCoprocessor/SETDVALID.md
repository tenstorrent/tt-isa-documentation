# `SETDVALID` (Give `SrcA` / `SrcB` banks to Matrix Unit)

**Summary:** The `SrcA` and/or `SrcB` banks currently being used by the Unpackers are given to the [Matrix Unit (FPU)](MatrixUnit.md), and then the relevant Unpacker(s) are prepared for writing to the other `SrcA` and/or `SrcB` bank.

On Blackhole, this instruction is `UnsupportedFunctionality` and its use is strongly discouraged, as its interaction with implied data formats is ill-specified. In practice, the implied data format it gives each bank is not tied to the bank's data: it is the output data format of the most recent `UNPACR` the bank's unpacker executed, which may have written the other bank or `Dst`, or of the `UNPACR` before that if one is still running (see [implied data format](SrcASrcB.md#implied-data-format-blackhole-only)). Software should not rely on this; [`UNPACR_NOP`](UNPACR_NOP.md) is the alternative.

See also [`CLEARDVALID`](CLEARDVALID.md).

**Backend execution unit:** [Miscellaneous Unit](MiscellaneousUnit.md)

## Syntax

```c
TT_SETDVALID(((/* bool */ FlipSrcB) << 1) +
               /* bool */ FlipSrcA)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SETDVALID.svg)

## Functional model

```c
if (TTArchitecture == Blackhole) {
  UnsupportedFunctionality(); // No known usage and interaction with ImpliedSrc*Fmt is ill-specified; UNPACR_NOP is recommended as an alternative
}
if (FlipSrcA) {
  if (Unpackers[0].WroteDst) {
    UndefinedBehavior(); // Hardware bug; see Unpackers[0].WroteDst in SrcASrcB.md
  }
  SrcA[Unpackers[0].SrcBank].AllowedClient = SrcClient::MatrixUnit;
  if (TTArchitecture == Blackhole) {
    ImpliedSrcAFmt[Unpackers[0].SrcBank] = UnpredictableValue(); // In practice Unpackers[0].LastOutDataFormat, or an older one if an UNPACR on unpacker 0 is still running
  }
  Unpackers[0].SrcBank ^= 1;
  uint2_t T = TTArchitecture == Wormhole ? Unpackers[0].WriteThread : CurrentThread; // See SrcASrcB.md
  Unpackers[0].SrcRow[T] = ThreadConfig[T].SRCA_SET_Base << 4;
}
if (FlipSrcB) {
  SrcB[Unpackers[1].SrcBank].AllowedClient = SrcClient::MatrixUnit;
  if (TTArchitecture == Blackhole) {
    ImpliedSrcBFmt[Unpackers[1].SrcBank] = UnpredictableValue(); // In practice Unpackers[1].LastOutDataFormat, or an older one if an UNPACR on unpacker 1 is still running
  }
  Unpackers[1].SrcBank ^= 1;
  uint2_t T = TTArchitecture == Wormhole ? Unpackers[1].WriteThread : CurrentThread; // See SrcASrcB.md
  Unpackers[1].SrcRow[T] = ThreadConfig[T].SRCB_SET_Base << 4;
}
```

## Instruction scheduling

`SETDVALID` doesn't wait for anything: not at the Wait Gate for `AllowedClient == SrcClient::Unpackers`, and not for earlier [`UNPACR`](UNPACR_Regular.md) instructions to finish writing, not even the issuing thread's own. If an `UNPACR` to the bank is still writing when `SETDVALID` executes, the bank is given to the Matrix Unit with only the datums written so far. Software should put a [`STALLWAIT`](STALLWAIT.md) with block bit B0 and condition C1 (for `SrcA`) or C2 (for `SrcB`) between its last `UNPACR` and `SETDVALID`; C1 and C2 only see the current thread's instructions, so when another thread does the unpacking, synchronize with that thread instead.
