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
if (StreamId != 0 || MsgClrCnt != 0) {
  UnsupportedFunctionality(); // Only meaningful with other modes; no known usage
}
if (ClearValue >= 2 || ClrTo1FmtCtrl != 0) {
  UnsupportedFunctionality(); // 2 clears to one, 3 to a value held in a register; see below
}
if (WhichUnpacker == 1 && ClearValue == 1) {
  UnsupportedFunctionality(); // Clearing SrcB to negative infinity; no known usage
}
if (BothBanks) {
  UnsupportedFunctionality(); // Races against the other unpacker, and the wait below covers just one bank; see below
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
  // As UNPACR with FlipSrc set: the bank goes to the Matrix Unit, with the unpacker's output format as its implied format,
  // except that a BFP4 or BFP2 input format (BFP4, BFP4a, BFP2, BFP2a) is recorded instead.
  // Unlike FlipSrc, it leaves Unpackers[WhichUnpacker].SrcRow[CurrentThread] as it is.
  Src[UnpackBank].AllowedClient = SrcClient::MatrixUnit;
  uint4_t InFmt = ConfigState.THCON_SEC[WhichUnpacker].REG0_TileDescriptor.InDataFormat;
  (WhichUnpacker ? ImpliedSrcBFmt : ImpliedSrcAFmt)[UnpackBank] = (InFmt & 3) == 3 ? InFmt : ConfigState.THCON_SEC[WhichUnpacker].REG2_Out_data_format;
  Unpackers[WhichUnpacker].SrcBank ^= 1;
}
```

The clear covers the whole bank, whatever the unpacker's X counter range (`SETADCXX`): it doesn't narrow to the span the next `UNPACR` reads.

## Clearing to one or to a register value

`ClearValue` values of 2 and 3, and a nonzero `ClrTo1FmtCtrl`, are `UnsupportedFunctionality`, but the hardware's behavior is as follows. The value is written in one of four formats, picked by `ClearFmt`:

```c
uint4_t InFmt = ConfigState.THCON_SEC[WhichUnpacker].REG0_TileDescriptor.InDataFormat;
uint4_t ClearFmt = (InFmt & 3) == 3 ? InFmt : ConfigState.THCON_SEC[WhichUnpacker].REG2_Out_data_format; // As the implied format above
bool Unsigned = WhichUnpacker == 0 ? ConfigState.ALU_FORMAT_SPEC_REG0_SrcAUnsigned : ConfigState.ALU_FORMAT_SPEC_REG0_SrcBUnsigned;
uint32_t Reg = WhichUnpacker == 0 ? ConfigState.UNP0_NOP_REG_CLR_VAL : ConfigState.UNP1_NOP_REG_CLR_VAL;

uint19_t ClearVal;
if (ClearFmt == INT8) {
  ClearVal = ClearValue == 2 ? WriteSrcInt8(1, Unsigned) : WriteSrcInt8(Reg & 0xff, Unsigned);
} else if (ClearFmt == FP16 || ClearFmt == BFP8a || ClearFmt == BFP4a || ClearFmt == BFP2a || ClearFmt == FP8) {
  ClearVal = WriteSrcFP16(ClearValue == 2 ? 0x3c00 : Reg & 0xffff);
} else if (ClearFmt == TF32 && ClearValue == 3) {
  ClearVal = WriteSrcTF32(Reg & 0x7ffff);
} else {
  ClearVal = WriteSrcBF16(ClearValue == 2 ? 0x3f80 : Reg & 0xffff);
}
```

`WriteSrcTF32`, `WriteSrcFP16` and `WriteSrcBF16` are as in [`UNPACR`](../../../WormholeB0/TensixTile/TensixCoprocessor/UNPACR_Regular.md); `WriteSrcInt8` stores sign and magnitude (or, when `Unsigned`, an 8-bit magnitude) in the low mantissa bits, with exponent 16 when the magnitude is nonzero and 0 otherwise. `Reg` and `Unsigned` are read when the clear happens, after its wait; the formats when the unpacker accepts the instruction.

`ClrTo1FmtCtrl` has no effect on the value; the value 3 together with `ClearValue` 2 turns the instruction into something other than a clear, not described here. `ClearValue` 2 and 3 on unpacker 0 also leave the hazard described under "Clearing both banks" armed.

## Clearing both banks

`BothBanks` is `UnsupportedFunctionality`, but the hardware's behavior is as follows. After the same wait as above, every datum of both banks of the selected register is set to `ClearVal`; bank ownership, the unpacker's bank, and implied formats are unchanged. Nothing waits for the bank that the wait didn't cover, so if the Matrix Unit has that bank, it can be cleared while being read.

The two unpackers share the hardware signal that selects both banks, so a `BothBanks` clear on one unpacker can disturb what the other unpacker is doing at the same time:
* Any `UNPACR_NOP` clear by the other unpacker that overlaps it can clear both banks of its register too, and if that clear has `SetDvalid`, the bank change can be lost.
* While unpacker 1 clears both banks of `SrcB`, an `UNPACR` on unpacker 0 at the same time can lose some of its writes to `SrcA` (or `Dst`). This depends on `ClearValue` from unpacker 0's most recent clear, which nothing resets: it happens if that was 2 or 3, or if unpacker 0 hasn't done a clear since reset.
* An `UNPACR` on unpacker 1 is unaffected by a `BothBanks` clear on unpacker 0.

Software that uses `BothBanks` anyway should order it against the other unpacker with [`STALLWAIT`](STALLWAIT.md): wait for both unpackers to be idle before the clear, and for the clearing unpacker to be idle before the other unpacker's next instruction.

(The datum layout is that of [`SrcA`](../../../WormholeB0/TensixTile/TensixCoprocessor/SrcASrcB.md): sign in bit 18, mantissa in bits 17 through 8, exponent in bits 7 through 0.)
