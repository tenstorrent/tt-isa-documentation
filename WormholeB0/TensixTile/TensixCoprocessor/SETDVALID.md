# `SETDVALID` (Give `SrcA` / `SrcB` banks to Matrix Unit)

**Summary:** The `SrcA` and/or `SrcB` banks currently being used by the Unpackers are given to the [Matrix Unit (FPU)](MatrixUnit.md), and then the relevant Unpacker(s) are prepared for writing to the other `SrcA` and/or `SrcB` bank.

On Blackhole, this instruction is `UnsupportedFunctionality` and its use is strongly discouraged, as its interaction with implied data formats is ill-specified. In practice, it records a stale/held copy of a previous unpack's output format, but this behavior should not be relied on by software.

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
  SrcA[Unpackers[0].SrcBank].AllowedClient = SrcClient::MatrixUnit;
  if (TTArchitecture == Blackhole) {
    ImpliedSrcAFmt[Unpackers[0].SrcBank] = UnpredictableValue();
  }
  Unpackers[0].SrcBank ^= 1;
  Unpackers[0].SrcRow[CurrentThread] = ThreadConfig[CurrentThread].SRCA_SET_Base << 4;
}
if (FlipSrcB) {
  SrcB[Unpackers[1].SrcBank].AllowedClient = SrcClient::MatrixUnit;
  if (TTArchitecture == Blackhole) {
    ImpliedSrcBFmt[Unpackers[1].SrcBank] = UnpredictableValue();
  }
  Unpackers[1].SrcBank ^= 1;
  Unpackers[1].SrcRow[CurrentThread] = ThreadConfig[CurrentThread].SRCB_SET_Base << 4;
}
```
