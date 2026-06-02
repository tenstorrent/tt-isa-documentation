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

## Functional model

```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];

// Determine the data formats.
bool UseDst32b;
uint4_t SrcAStyle;
if (ThreadConfig[CurrentThread].FP16A_FORCE_Enable) {
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

`MOVD2A` does not automatically wait at the Wait Gate to ensure that `SrcA[MatrixUnit.SrcABank].AllowedClient == SrcClient::MatrixUnit`, so software may wish to use [`STALLWAIT`](STALLWAIT.md) (with block bit B6 and condition code C10) prior to `MOVD2A`.

If `MOVD2A` is used, then on the next cycle, the only instructions that the Matrix Unit (FPU) can accept are `MOVD2A` and `MOVB2A`. If a thread presents any other Matrix Unit (FPU) instruction, then hardware will automatically stall the thread for one cycle.

It is strongly recommended to set `DISABLE_IMPLIED_SRCA_FMT_Base` on Blackhole when using this instruction, as the interaction with `ImpliedSrcAFmt` is ill-specified when the bank is not valid. In practice, `SFPU_DEST_FMT_Base` will be used as the default implied format for an invalid bank, but this is a `NonContractualBehavior` and should not be relied on by software.
