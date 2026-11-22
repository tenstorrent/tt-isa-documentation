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
  // As UNPACR with FlipSrc set: the bank goes to the Matrix Unit, with the unpacker's output format as its implied format.
  // Unlike FlipSrc, it leaves Unpackers[WhichUnpacker].SrcRow[CurrentThread] as it is.
  Src[UnpackBank].AllowedClient = SrcClient::MatrixUnit;
  (WhichUnpacker ? ImpliedSrcBFmt : ImpliedSrcAFmt)[UnpackBank] = ConfigState.THCON_SEC[WhichUnpacker].REG2_Out_data_format;
  Unpackers[WhichUnpacker].SrcBank ^= 1;
}
```

The clear covers the whole bank, whatever the unpacker's X counter range (`SETADCXX`): it doesn't narrow to the span the next `UNPACR` reads.

## Clearing both banks

`BothBanks` is `UnsupportedFunctionality`, but the hardware's behavior is as follows. After the same wait as above, every datum of both banks of the selected register is set to `ClearVal`; bank ownership, the unpacker's bank, and implied formats are unchanged. Nothing waits for the bank that the wait didn't cover, so if the Matrix Unit has that bank, it can be cleared while being read.

The two unpackers share the hardware signal that selects both banks, so a `BothBanks` clear on one unpacker can disturb what the other unpacker is doing at the same time:
* Any `UNPACR_NOP` clear by the other unpacker that overlaps it can clear both banks of its register too, and if that clear has `SetDvalid`, the bank change can be lost.
* While unpacker 1 clears both banks of `SrcB`, an `UNPACR` on unpacker 0 at the same time can lose some of its writes to `SrcA` (or `Dst`). This depends on `ClearValue` from unpacker 0's most recent clear, which nothing resets: it happens if that was 2 or 3, or if unpacker 0 hasn't done a clear since reset.
* An `UNPACR` on unpacker 1 is unaffected by a `BothBanks` clear on unpacker 0.

Software that uses `BothBanks` anyway should order it against the other unpacker with [`STALLWAIT`](STALLWAIT.md): wait for both unpackers to be idle before the clear, and for the clearing unpacker to be idle before the other unpacker's next instruction.

(The datum layout is that of [`SrcA`](../../../WormholeB0/TensixTile/TensixCoprocessor/SrcASrcB.md): sign in bit 18, mantissa in bits 17 through 8, exponent in bits 7 through 0.)
