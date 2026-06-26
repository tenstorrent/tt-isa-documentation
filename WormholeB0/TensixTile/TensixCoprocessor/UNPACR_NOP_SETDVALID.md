# `UNPACR_NOP` (Give `SrcA` or `SrcB` banks to Matrix Unit, sequenced with UNPACR)

**Summary:** Similar to a [`SETDVALID`](SETDVALID.md) instruction, but sequenced after previous instructions to the same unpacker.

**Backend execution unit:** [Unpackers](Unpackers/README.md)

## Syntax

```c
TT_UNPACR_NOP(/* u1 */ WhichUnpacker, 0x7)
```

## Encoding

![](../../../Diagrams/Out/Bits32_UNPACR_NOP_SETDVALID.svg)

## Functional model

```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];
if (WhichUnpacker == 0) {
  SrcA[Unpackers[0].SrcBank].AllowedClient = SrcClient::MatrixUnit;
  if (TTArchitecture == Blackhole) {
    ImpliedSrcAFmt[Unpackers[0].SrcBank] = ConfigState.THCON_SEC[0].REG2_Out_data_format;
  }
  Unpackers[0].SrcBank ^= 1;
  Unpackers[0].SrcRow[CurrentThread] = ThreadConfig[CurrentThread].SRCA_SET_Base << 4;
} else {
  SrcB[Unpackers[1].SrcBank].AllowedClient = SrcClient::MatrixUnit;
  if (TTArchitecture == Blackhole) {
    ImpliedSrcBFmt[Unpackers[1].SrcBank] = ConfigState.THCON_SEC[1].REG2_Out_data_format;
  }
  Unpackers[1].SrcBank ^= 1;
  Unpackers[1].SrcRow[CurrentThread] = ThreadConfig[CurrentThread].SRCB_SET_Base << 4;
}
```

## Instruction scheduling

This instruction does not automatically wait at the Wait Gate to ensure that `AllowedClient == SrcClient::Unpackers`, so unless sequenced after an [`UNPACR` (Move datums from L1 to `SrcA` or `SrcB` or `Dst`)](UNPACR_Regular.md) or [`UNPACR_NOP` (Set `SrcA` or `SrcB` to zero, sequenced with UNPACR)](UNPACR_NOP_ZEROSRC.md) instruction which performs the desired wait, software may wish to use [`STALLWAIT`](STALLWAIT.md) (with block bit B3 and condition code C10 or C11) prior to `UNPACR_NOP`.
