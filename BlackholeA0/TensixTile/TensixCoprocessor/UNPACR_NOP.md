# `UNPACR_NOP` (Set `SrcA` or `SrcB` to a constant, sequenced with UNPACR)

**Summary:** Similar to a [`ZEROSRC`](ZEROSRC.md) instruction, but sequenced after previous instructions to the same unpacker, and optionally setting data valid afterwards. Blackhole's encoding of this instruction differs from Wormhole's throughout.

**Backend execution unit:** [Unpackers](../../../WormholeB0/TensixTile/TensixCoprocessor/Unpackers/README.md)

## Syntax

```c
TT_UNPACR_NOP(/* u1 */ WhichUnpacker,
              /* u6 */ StreamId,
              /* u11 */ MsgClrCnt,
              /* bool */ SetDvalid,
              /* u2 */ ClrTo1FmtCtrl,
              /* bool */ WaitLikeUnpacr,
              /* bool */ BothBanks,
              /* u2 */ ClearValue,
              /* u2 */ Mode)
```

## Functional model

```c
if (Mode != 1) {
  UnsupportedFunctionality(); // 0 and 3 free buffer space in the NoC overlay, 2 is a delay between unpacks; no known usage
}
if (StreamId != 0 || MsgClrCnt != 0 || ClrTo1FmtCtrl != 0) {
  UnsupportedFunctionality(); // Only meaningful with other modes, or with clearing to one; no known usage
}
if (ClearValue >= 2) {
  UnsupportedFunctionality(); // 2 clears to one, 3 to a value held in a register; no known usage
}
if (WhichUnpacker == 1 && ClearValue == 1) {
  UnsupportedFunctionality(); // Clearing SrcB to negative infinity; no known usage
}
if (BothBanks) {
  UnsupportedFunctionality(); // The wait below covers just one bank, so clearing the other races against the Matrix Unit
}

uint1_t UnpackBank = Unpackers[WhichUnpacker].SrcBank;
auto& Src = WhichUnpacker == 0 ? SrcA : SrcB;
uint1_t MatrixBank = WhichUnpacker == 0 ? MatrixUnit.SrcABank : MatrixUnit.SrcBBank;

// Wait for bank access.
while (Src[WaitLikeUnpacr ? UnpackBank : MatrixBank].AllowedClient != SrcClient::Unpackers) {
  wait;
}

// Do the clearing.
uint19_t ClearVal = ClearValue == 1 ? ~0u : 0u; // Negative infinity, or zero
for (unsigned i = 0; i < 64; ++i) {
  for (unsigned j = 0; j < 16; ++j) {
    Src[UnpackBank][i][j] = ClearVal;
  }
}

if (SetDvalid) {
  if (Src[UnpackBank].AllowedClient != SrcClient::Unpackers) {
    NonContractualBehavior(); // Only possible with WaitLikeUnpacr false, which waited for the Matrix Unit's bank instead
  }
  if (WhichUnpacker == 0 && ThreadConfig[CurrentThread].SRCA_SET_Base != 0) {
    UnsupportedFunctionality(); // No known usage
  }
  // As UNPACR with FlipSrc set: the bank goes to the Matrix Unit, with the unpacker's output format as its implied format.
  // Unlike FlipSrc, it leaves Unpackers[WhichUnpacker].SrcRow[CurrentThread] as it is.
  Src[UnpackBank].AllowedClient = SrcClient::MatrixUnit;
  (WhichUnpacker ? ImpliedSrcBFmt : ImpliedSrcAFmt)[UnpackBank] = ConfigState.THCON_SEC[WhichUnpacker].REG2_Out_data_format;
  Unpackers[WhichUnpacker].SrcBank ^= 1;
}
```

The clear covers the whole bank, whatever the unpacker's X counter range (`SETADCXX`): it doesn't narrow to the span the next `UNPACR` reads.

(The datum layout is that of [`SrcA`](../../../WormholeB0/TensixTile/TensixCoprocessor/SrcASrcB.md): sign in bit 18, mantissa in bits 17 through 8, exponent in bits 7 through 0.)
