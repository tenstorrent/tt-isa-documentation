# `SFPLOAD` (Move from `Dst` to `LReg`)

**Summary:** Move (up to) 32 datums from the even or odd columns of four consecutive rows of [`Dst`](Dst.md) to an `LReg`. To bridge the gap between [`Dst` data types](Dst.md#data-types) and [`LReg` data types](LReg.md#data-types), some data type conversions are supported as part of the instruction, though software might still want a subsequent `SFPSTOCHRND` or `SFPCAST` instruction to achieve a richer set of conversions.

**Backend execution unit:** [Vector Unit (SFPU)](VectorUnit.md), load sub-unit

## Syntax

```c
TT_SFPLOAD(/* u4 */ VD, /* u4 */ Mod0, /* u2 */ AddrMod, /* u10 */ Imm10)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SFPLOAD.svg)

## Data type conversions

One of the following data type conversions is specified using the `Mod0` field:

|`SFPLOAD` Mode|Expected [`Dst` data type](Dst.md#data-types)|→|Resultant [`LReg` data type](LReg.md#data-types)|
|---|---|---|---|
|`MOD0_FMT_FP16`|FP16 (configurable handling of infinity)|→|FP32|
|`MOD0_FMT_BF16`|BF16|→|FP32|
|`MOD0_FMT_FP32`|FP32 or Integer "32"|→|FP32 or sign-magnitude integer (as per `Dst` type)|
|`MOD0_FMT_INT32`|FP32 or Integer "32"|→|FP32 or sign-magnitude integer (as per `Dst` type)|
|`MOD0_FMT_INT32_ALL` (‡)|FP32 or Integer "32"|→|FP32 or sign-magnitude integer (as per `Dst` type)|
|`MOD0_FMT_INT32_SM`|Integer "32"|→|Two's complement integer|
|`MOD0_FMT_INT8`|Integer "8" in range ±127|→|Sign-magnitude integer|
|`MOD0_FMT_INT8_COMP`|Integer "8"|→|Two's complement integer|
|`MOD0_FMT_LO16_ONLY`|Integer "16" containing opaque 16 bits|→|Unsigned integer (write to low 16 bits, preserve high 16)|
|`MOD0_FMT_HI16_ONLY`|Integer "16" containing opaque 16 bits|→|Unsigned integer (write to high 16 bits, preserve low 16)|
|`MOD0_FMT_INT16`|Integer "16"|→|Sign-magnitude integer|
|`MOD0_FMT_UINT16`|Integer "16" containing opaque 16 bits|→|Unsigned integer (zero-extend to 32 bits)|
|`MOD0_FMT_LO16`|Integer "16" containing opaque 16 bits|→|Unsigned integer (zero-extend to 32 bits)|
|`MOD0_FMT_HI16`|Integer "16" containing opaque 16 bits|→|Unsigned integer (write to high 16 bits, zero low 16)|

(‡) This mode also changes the addressing scheme slightly, and causes `LaneEnabled` to be ignored; see the functional model for details.

The `MOD0_FMT_SRCB` mode resolves to one of `MOD0_FMT_FP16` or `MOD0_FMT_BF16` or `MOD0_FMT_FP32`; see the functional model for details.

## Cross-lane data movement pattern

Assuming all 32 lanes active:

![](../../../Diagrams/Out/CrossLane_SFPLOAD.svg)

Note that this pattern is the exact inverse of [`SFPSTORE`](SFPSTORE.md).

## Functional model

```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];

// Resolve MOD0_FMT_SRCB to something concrete.
if (Mod0 == MOD0_FMT_SRCB) {
  if (ConfigState.ALU_ACC_CTRL_SFPU_Fp32_enabled) {
    Mod0 = MOD0_FMT_FP32; // NB: Functionally identical to MOD0_FMT_INT32.
  } else {
    uint4_t SrcBFmt = ConfigState.ALU_FORMAT_SPEC_REG_SrcB_override ? ConfigState.ALU_FORMAT_SPEC_REG_SrcB_val : ConfigState.ALU_FORMAT_SPEC_REG1_SrcB;
    if (SrcBFmt in {FP32, TF32, BF16, BFP8, BFP4, BFP2, INT32, INT16}) {
      Mod0 = MOD0_FMT_BF16;
    } else {
      Mod0 = MOD0_FMT_FP16;
    }
  }
}

// Apply various Dst address adjustments.
// The top 8 bits of Addr end up selecting an aligned group of four rows of Dst, the
// next bit selects between even and odd columns, and the low bit goes unused.
uint10_t Addr = Imm10 + ThreadConfig[CurrentThread].DEST_TARGET_REG_CFG_MATH_Offset;
if (Mod0 == MOD0_FMT_INT32_ALL) {
  Addr += (RWCs[CurrentThread].Dst + ConfigState.DEST_REGW_BASE_Base) & 3;
} else {
  Addr += RWCs[CurrentThread].Dst + ConfigState.DEST_REGW_BASE_Base;
}

if (VD < 8) {
  for (unsigned Lane = 0; Lane < 32; ++Lane) {
    if (LaneConfig[Lane].BLOCK_SFPU_RD_FROM_DEST) continue;
    if (LaneEnabled[Lane] || Mod0 == MOD0_FMT_INT32_ALL) {
      uint32_t Datum;
      uint10_t Row = (Addr & ~3) + (Lane / 8);
      uint4_t Column = (Lane & 7) * 2;
      if ((Addr & 2) || LaneConfig[Lane & 7].DEST_RD_COL_EXCHANGE) {
        Column += 1;
      }
      switch (Mod0) {
      case MOD0_FMT_FP16:      Datum = ReadFP16(Dst16b[Row][Column], LaneConfig[Lane].ENABLE_FP16A_INF); break;
      case MOD0_FMT_BF16:      Datum = uint32_t(DstDecodeBF16(Dst16b[Row][Column])) << 16; break;
      case MOD0_FMT_FP32:      Datum = DstDecodeFP32(Dst32b[Row][Column]); break;
      case MOD0_FMT_INT32:     Datum = DstDecodeFP32(Dst32b[Row][Column]); break;
      case MOD0_FMT_INT32_ALL: Datum = DstDecodeFP32(Dst32b[Row][Column]); break;
      case MOD0_FMT_INT32_SM:  Datum = SignMagToTwosComp(DstDecodeFP32(Dst32b[Row][Column])); break;
      case MOD0_FMT_INT8:      Datum = SignMag8ToSignMag32(Dst16b[Row][Column]); break;
      case MOD0_FMT_INT8_COMP: Datum = SignMagToTwosComp(SignMag11ToSignMag32(Dst16b[Row][Column])); break;
      case MOD0_FMT_LO16_ONLY: Datum = (LReg[VD][Lane].u32 & 0xffff0000) | Dst16b[Row][Column]; break;
      case MOD0_FMT_HI16_ONLY: Datum = (Dst16b[Row][Column] << 16) | (LReg[VD][Lane].u32 & 0x0000ffff); break;
      case MOD0_FMT_INT16:     Datum = SignMag16ToSignMag32(Dst16b[Row][Column]); break;
      case MOD0_FMT_UINT16:    Datum = Dst16b[Row][Column]; break;
      case MOD0_FMT_LO16:      Datum = Dst16b[Row][Column]; break;
      case MOD0_FMT_HI16:      Datum = Dst16b[Row][Column] << 16; break;
      case MOD0_FMT_ZERO:      Datum = 0; break;
      // NB: MOD0_FMT_SRCB already resolved to either MOD0_FMT_FP32 or MOD0_FMT_BF16 or MOD0_FMT_FP16.
      }
      LReg[VD][Lane].u32 = Datum;
      if (VD < 4 && LaneConfig[Lane].ENABLE_DEST_INDEX && LaneConfig[Lane].CAPTURE_DEFAULT_DEST_INDEX) {
        LReg[VD + 4][Lane].u32 = (Row << 4) | Column;
      }
    }
  }
}

// Advance Dst / SrcA / SrcB RWCs (but _not_ Fidelity RWC).
ApplyPartialAddrMod(AddrMod);
```

See [RWCs](RWCs.md) for the definition of `ApplyPartialAddrMod`.

Supporting definitions:
```c
#define MOD0_FMT_SRCB      0
#define MOD0_FMT_FP16      1
#define MOD0_FMT_BF16      2
#define MOD0_FMT_FP32      3
#define MOD0_FMT_INT32     4
#define MOD0_FMT_INT8      5
#define MOD0_FMT_UINT16    6
#define MOD0_FMT_HI16      7
#define MOD0_FMT_INT16     8
#define MOD0_FMT_LO16      9
#define MOD0_FMT_INT32_ALL 10
#define MOD0_FMT_ZERO      11
#define MOD0_FMT_INT32_SM  12
#define MOD0_FMT_INT8_COMP 13
#define MOD0_FMT_LO16_ONLY 14
#define MOD0_FMT_HI16_ONLY 15

uint32_t ReadFP16(uint16_t x, bool ENABLE_FP16A_INF) {
  // Dst contained Sign,Man(10b),Exp(5b)
  uint32_t Sign = x >> 15;
  uint32_t Man = (x >> 5) & 0x3ff;
  uint32_t Exp = x & 0x1f;
  if (ENABLE_FP16A_INF && Exp == 0x1f && Man == 0x3ff) {
    Exp = 255, Man = 0; // Remap largest possible value to IEEE754 infinity
  } else if (Exp != 0) {
    Exp += 112; // Rebias from 5b Exp to 8b Exp
  } else {
    // Denormals become some other denormal, but subsequent arithmetic operations will flush denormals to zero
  }
  return (Sign << 31) | (Exp << 23) | (Man << 13);
}

uint32_t SignMag8ToSignMag32(uint16_t x) {
  // Dst contained Sign,Ignored(3b),Mag(7b),Ignored(5b)
  uint32_t Sign = x >> 15;
  uint32_t Mag  = (x >> 5) & 0x7f;
  return (Sign << 31) | Mag;
}

uint32_t SignMag11ToSignMag32(uint16_t x) {
  // Dst contained Sign,Mag(10b),Ignored(5b)
  uint32_t Sign = x >> 15;
  uint32_t Mag  = (x >> 5) & 0x3ff;
  return (Sign << 31) | Mag;
}

uint32_t SignMag16ToSignMag32(uint16_t x) {
  // Dst contained Sign,Mag(15b)
  uint32_t Sign = x >> 15;
  uint32_t Mag  = x & 0x7fff;
  return (Sign << 31) | Mag;
}

uint32_t SignMagToTwosComp(uint32_t x) {
  // Convert from sign and 31-bit magnitude to 32-bit two's complement.
  uint32_t Sign = x & 0x80000000;
  uint32_t Mag  = x & 0x7fffffff;
  return Sign ? -Mag : Mag;
}
```

## Instruction scheduling

At least three unrelated Tensix instructions need to execute after a Matrix Unit (FPU) instruction which writes (or accumulates) to `Dst` and an `SFPLOAD` instruction which wants to read that same region of `Dst`. If software lacks useful instructions to fill the gap, any kind of Tensix NOP instruction can be used for this purpose. Software can also use [`STALLWAIT`](STALLWAIT.md) (with block bit B8 and condition code C7), though the recommendation (in this context) is to insert three unrelated Tensix instructions rather than using `STALLWAIT`.
