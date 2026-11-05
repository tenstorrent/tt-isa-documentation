# `MOVD2A` (Move one row or four rows from `Dst` to `SrcA`)

**Summary:** Move one row of datums from `Dst` to `SrcA`, or move an aligned block of four rows of datums from `Dst` to `SrcA`. To bridge the gap between [`Dst` data types](Dst.md#data-types) and [`SrcA` data types](SrcASrcB.md#data-types), either of FP32 / BF16 in `Dst` can be converted to either of TF32 / BF16 in `SrcA`, and either of FP16 / Integer "8" in `Dst` can be passed through unchanged to `SrcA`. If used with care, software can also take 32-bit data in `Dst` and move either the low or high bits of each datum to `SrcA`.

**Backend execution unit:** [Matrix Unit (FPU)](MatrixUnit.md)

## Syntax

```c
TT_MOVD2A(/* bool */ UseDst32bLo,
          /* u6 */ SrcRow,
          /* u2 */ AddrMod,
         (/* bool */ Move4Rows) << 1,
          /* u10 */ DstRow)
```

## Encoding

![](../../../Diagrams/Out/Bits32_MOVD2A.svg)

On Blackhole, `AddrMod` is a `u3` rather than a `u2`, giving this encoding:

![](../../../Diagrams/Out/Bits32_MOVD2A_BH.svg)

## Functional model

```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];

// Determine the data formats.
bool UseDst32b;
uint4_t SrcAStyle;
if (ThreadConfig[CurrentThread].FP16A_FORCE_Enable) {
  UnsupportedFunctionality(); // No known usage, confidence in specification below is weak
  UseDst32b = false;
  SrcAStyle = FP16;
} else {
  uint4_t SrcAFmt = ConfigState.ALU_FORMAT_SPEC_REG_SrcA_override ? ConfigState.ALU_FORMAT_SPEC_REG_SrcA_val : ConfigState.ALU_FORMAT_SPEC_REG0_SrcA;
  if ((TTArchitecture == Blackhole) && !ThreadConfig[CurrentThread].DISABLE_IMPLIED_SRCA_FMT_Base) {
    SrcAFmt = ImpliedSrcAFmt[MatrixUnit.SrcABank];
  }
  UseDst32b = ConfigState.ALU_ACC_CTRL_Fp32_enabled || ConfigState.ALU_ACC_CTRL_INT8_math_enabled;
  if (SrcAFmt in {FP32, BF16, BFP8, BFP4, BFP2, INT32, INT16}) {
    SrcAStyle = BF16;
  } else if (SrcAFmt in {FP16, FP8, BFP8a, BFP4a, BFP2a, INT8}) {
    SrcAStyle = FP16;
  } else /* SrcAFmt == TF32 */ {
    SrcAStyle = TF32;
  }
}

// Determine the row range.
unsigned NumRows;
DstRow += ThreadConfig[CurrentThread].DEST_TARGET_REG_CFG_MATH_Offset;
DstRow += RWCs[CurrentThread].Dst + ConfigState.DEST_REGW_BASE_Base;
SrcRow += RWCs[CurrentThread].SrcA;
if (Move4Rows) {
  if ((TTArchitecture == Blackhole) && (SrcRow & 3)) {
    // On Blackhole, in practice the SrcA rows are not aligned down: the move writes SrcA rows
    // starting at SrcRow, stopping at the end of the aligned group of 16 rows that contains SrcRow (the Dst rows are still aligned down).
    UndefinedBehavior();
  }
  NumRows = 4;
  DstRow &= 0x3fc;
  SrcRow &= 0x3c;
} else {
  NumRows = 1;
  DstRow &= 0x3ff;
  SrcRow &= 0x3f;
}

// Actually copy the row(s).
for (; NumRows; --NumRows, ++DstRow, ++SrcRow) {
  for (unsigned Column = 0; Column < 16; ++Column) {
    if (LaneConfig[Column / 2].BLOCK_DEST_MOV.Bit[Column & 1]) continue;
    uint19_t SrcAVal;
    if (UseDst32b) {
      // Read from Dst in 32-bit mode.
      uint32_t DstVal = Dst32b[DstRow][Column];
      if (UseDst32bLo) {
        // This is unlikely to be useful, unless software has deliberately
        // packed two bf16 or fp16 values into 32 bits and written them to Dst32b.
        DstVal = (DstVal << 16) | (DstVal & 0xffff);
      }
      if (SrcAStyle == BF16) {
        // Treat DstVal as fp32 or tf32, truncate to bf16.
        SrcAVal = ShuffleBF16(DstVal >> 16);
      } else if (SrcAStyle == FP16) {
        // This is unlikely to be useful, unless software has deliberately
        // packed two fp16 values into 32 bits and written them to Dst32b.
        SrcAVal = ShuffleFP16(DstVal >> 16);
      } else if (!UseDst32bLo) {
        // Treat DstVal as fp32 or tf32, truncate to tf32.
        SrcAVal = ShuffleTF32(DstVal >> 13);
      } else {
        // This gives the 13 bits which are discarded by the fp32 -> tf32 conversion
        // in the above branch, but they're unlikely to be useful for anything other
        // than a subsequent MOVA2D with UseDst32bLo=true.
        SrcAVal = DstVal & 0x1fff;
      }
    } else {
      // Read from Dst in 16-bit mode.
      uint16_t DstVal = Dst16b[DstRow][Column];
      if (UseDst32bLo) {
        // DstVal isn't wide enough to contain 32-bit data.
        UndefinedBehavior();
      }
      if (SrcAStyle == BF16) {
        // Treat DstVal as bf16.
        SrcAVal = ShuffleBF16(DstVal);
      } else if (SrcAStyle == FP16) {
        // Treat DstVal as fp16.
        // This branch also applies to "integer 8" data, as it is overlaid onto fp16.
        SrcAVal = ShuffleFP16(DstVal);
      } else {
        // DstVal isn't wide enough to contain fp32 or tf32 data.
        UndefinedBehavior();
      }
    }
    SrcA[MatrixUnit.SrcABank][SrcRow][Column] = SrcAVal;
  }
}

// Advance the RWCs.
ApplyAddrMod(AddrMod);
```

Supporting definitions:
```c
uint19_t ShuffleBF16(uint16_t x) {
  // Dst holds BF16 as Sign,Man(7b),Exp(8b)
  // Src holds BF16 as Sign,Man(10b),Exp(8b)
  return ((x & 0xFF00) << 3) | (x & 0xFF);
}

uint19_t ShuffleFP16(uint16_t x) {
  // Dst holds FP16 as Sign,Man(10b),Exp(5b)
  // Src holds FP16 as Sign,Man(10b),Zero(3b),Exp(5b)
  return ((x & 0xFFE0) << 3) | (x & 0x1F);
}

uint19_t ShuffleTF32(uint19_t x) {
  // Dst holds TF32 as Sign,HiMan(7b),Exp(8b),LoMan(3b)
  // Src holds TF32 as Sign,Man(10b),Exp(8b)
  uint19_t SignHiMan = x & 0x7f800;
  uint19_t Exp       = x & 0x007f8;
  uint19_t LoMan     = x & 0x00007;
  return SignHiMan | (LoMan << 8) | (Exp >> 3);
}
```

## Instruction scheduling

`MOVD2A` does not wait at the Wait Gate for `SrcA[MatrixUnit.SrcABank].AllowedClient == SrcClient::MatrixUnit`: it writes the bank that `MatrixUnit.SrcABank` selects even while the Unpackers own it, which is the bank unpacker 0 writes next. If unpacker 0 writes that bank (an [`UNPACR`](UNPACR_Regular.md), or an [`UNPACR_NOP`](UNPACR_NOP_ZEROSRC.md) that clears it) before giving it to the Matrix Unit, and `MOVD2A` runs before the Matrix Unit has the bank, then which of the two writes survives depends on timing, and the result is `UndefinedBehavior`. This includes an unpacker instruction issued before `MOVD2A`, even from the same thread, as the Unpackers can finish it after `MOVD2A` writes. Software should first make sure the Matrix Unit has the bank: with [`STALLWAIT`](STALLWAIT.md) (block bit B6 and condition code C10, or C7 on Blackhole), with an earlier instruction from the same thread that waits for it (e.g. `MOVA2D` or `ELWADD`), or by having the thread that issued the unpacker's instructions wait for that unpacker to finish (`STALLWAIT` condition C1) before it signals this thread. If the Unpackers give the bank without writing it ([`SETDVALID`](SETDVALID.md), or the [`UNPACR_NOP`](UNPACR_NOP_SETDVALID.md) that only gives it), what `MOVD2A` wrote is still there once the Matrix Unit has the bank.

If `MOVD2A` is used, then on the next cycle, the only instructions that the Matrix Unit (FPU) can accept are `MOVD2A` and `MOVB2A`. If a thread presents any other Matrix Unit (FPU) instruction, then hardware will automatically stall the thread for one cycle. On Blackhole, this restriction instead applies for the next two cycles, and the automatic stall is for up to two cycles.

It is strongly recommended to set `DISABLE_IMPLIED_SRCA_FMT_Base` on Blackhole when using this instruction, as the interaction with `ImpliedSrcAFmt` is ill-specified when the bank is not valid. In practice, `SFPU_DEST_FMT_Base` will be used as the default implied format for an invalid bank, but this is a `NonContractualBehavior` and should not be relied on by software.
