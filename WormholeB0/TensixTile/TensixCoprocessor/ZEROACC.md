# `ZEROACC` (Mark some rows of `Dst` as undefined)

**Summary:** Mark either 1, 16, 256, 512, or 1024 rows of `Dst` as undefined. Subsequent operations which read from `Dst` then interpret undefined:
* Packers reading from `Dst` read undefined rows as zero.
* Matrix Unit (FPU) instructions read undefined rows as the identity element for the instruction being executed, which is negative infinity for `GMPOOL` / `MPOOL3S1` / `MPOOL3S2`, and is zero for all other instructions. In any event, the write performed by these instructions will then cause the row contents to become well defined, with the sole exception of [`MVMUL`](MVMUL.md) with `BroadcastSrcBRow` set, which updates the valid bits of a set of rows that is neither a subset nor a superset of the rows that it writes.
* The Vector Unit (SFPU) exhibits `UndefinedBehavior` when reading (i.e. `SFPLOAD` / `SFPLOADMACRO`) an undefined row. It also exhibits `UndefinedBehavior` if `SFPSTORE` writes to _some_ columns of an undefined row but leaves other columns unwritten.
* Unpackers exhibit `UndefinedBehavior` if an unpack to `Dst` writes to _some_ columns of an undefined row but leaves other columns unwritten.
* If a Vector Unit or unpacker write to `Dst` executes in the same cycle, rows in the same 256-row group as the written rows, and congruent to them modulo 8, may not be marked undefined. On Blackhole it is the other way around: the `ZEROACC` takes full effect and the write's update of `DstRowValid` is lost (see [`Dst.md` in the Blackhole tree](../../../BlackholeA0/TensixTile/TensixCoprocessor/Dst.md)).

**Backend execution unit:** [Matrix Unit (FPU)](MatrixUnit.md)

## Syntax

```c
TT_ZEROACC(((/* bool */ UseDst32b) << 2) +
             /* u2 */ Mode,
             /* u2 */ AddrMod,
             /* u10 */ Imm10)
```

There is no syntax to specify `/* bool */ Revert`; if a non-zero value is desired for this field, the raw encoding must be used.

On Blackhole, the syntax is instead:

```c
TT_ZEROACC(/* u3 */ Mode,
           /* bool */ UseDst32b,
           /* bool */ Revert,
           /* u3 */ AddrMod,
           /* u10 */ Imm10)
```

## Encoding

![](../../../Diagrams/Out/Bits32_ZEROACC.svg)

On Blackhole, `AddrMod` is a `u3` rather than a `u2`, `UseDst32b` is no longer part of `Mode`, and `Mode` is a `u3`, giving this encoding:

![](../../../Diagrams/Out/Bits32_ZEROACC_BH.svg)

## Functional model

On Blackhole, the 16-row mode's `Imm10` is relative to the half of `Dst` that the instruction addresses, unless `DEST_ACCESS_CFG_zeroacc_absolute_tile_mode` is set. Hardware picks the half using the row that the one-row mode would clear, i.e. `Imm10` plus `DEST_TARGET_REG_CFG_MATH_Offset` plus the `Dst` RWC plus `DEST_REGW_BASE_Base`, with `Imm10` added in as a row number even though this mode treats it as a face number; the upper half is rows 512 and up, or rows 256 and up with `UseDst32b`. Software double-buffering `Dst` normally keeps the base of the current half in `DEST_TARGET_REG_CFG_MATH_Offset`, so `Imm10` should then be the face number within that half. Note that the sum can reach the upper half even when `DEST_TARGET_REG_CFG_MATH_Offset` is in the lower half (e.g. `DEST_TARGET_REG_CFG_MATH_Offset == 496` and `Imm10 == 20`), and that an `Imm10` which already includes the half (e.g. 32 or more for the upper half of a 16-bit `Dst`) is out of bounds once the half is added again. On Wormhole, `Imm10` is always absolute.

```c
if (Revert) {
  // If this branch is taken, then in the below, the assignments of DstRowValid set it
  // to true instead of to false. Don't use this unless you really know what you're doing.
  UndefinedBehavior();
}
if (TTArchitecture == Blackhole && Mode >= 4) {
  UndefinedBehavior();
}
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];
uint10_t Row = Imm10;
Row += ThreadConfig[CurrentThread].DEST_TARGET_REG_CFG_MATH_Offset;
Row += RWCs[CurrentThread].Dst + ConfigState.DEST_REGW_BASE_Base;
if (Mode == ZEROACC_MODE_ONE_ROW) {
  if (TTArchitecture == Blackhole) {
    // Blackhole consults UseDst32b rather than the accumulation data format
    if (UseDst32b) {
      DstRowValid[Adj32NoSwizzle(Row)] = false;
    } else {
      DstRowValid[Adj16(Row)] = false;
    }
  } else if (ConfigState.ALU_ACC_CTRL_Fp32_enabled || ConfigState.ALU_ACC_CTRL_INT8_math_enabled) {
    DstRowValid[Adj32(Row)] = false;
  } else {
    DstRowValid[Row] = false;
  }
} else {
  if (Mode == ZEROACC_MODE_16_ROWS && TTArchitecture == Blackhole) {
    unsigned NumFaces = UseDst32b ? 32 : 64;
    unsigned Face = Imm10;
    if (!Config.DEST_ACCESS_CFG_zeroacc_absolute_tile_mode && Row >= (UseDst32b ? 256 : 512)) {
      Face += NumFaces / 2; // Relative to the upper half
    }
    if (Face >= NumFaces) {
      NonContractualBehavior {
        Face %= NumFaces; // Current silicon wraps around (not architecturally guaranteed)
      }
    }
    for (unsigned i = 0; i < 16; i++) {
      if (UseDst32b) {
        DstRowValid[Adj32NoSwizzle(Face*16 + i)] = false;
      } else {
        DstRowValid[Adj16(Face*16 + i)] = false;
      }
    }
  } else if (Mode == ZEROACC_MODE_16_ROWS) {
    if (Imm10 > 0xFF) {
      NonContractualBehavior {
        Imm10 &= 0xFF; // Current silicon only uses the low 8 bits (not architecturally guaranteed)
      }
    }
    if (UseDst32b) {
      if (Imm10 < 32) {
        for (unsigned i = 0; i < 16; i++) DstRowValid[Imm10*32 + (i & 8)*2 + (i & 7)] = false;
      } else {
        NonContractualBehavior {
          // Out of bounds values are a nop in current silicon (not architecturally guaranteed)
        }
      }
    } else {
      if (Imm10 < 64) {
        for (unsigned i = 0; i < 16; i++) DstRowValid[Imm10*16 + i] = false;
      } else {
        NonContractualBehavior {
          // Out of bounds values are a nop in current silicon (not architecturally guaranteed)
        }
      }
    }
  } else if (Mode == ZEROACC_MODE_HALF_OF_DST) {
    if (Imm10 & 1) {
      // High half
      for (unsigned i = 512; i < 1024; i++) DstRowValid[i] = false;
    } else {
      // Low half
      for (unsigned i = 0; i < 512; i++) DstRowValid[i] = false;
    }
  } else /* Mode == ZEROACC_MODE_ALL_OF_DST */ {
    for (unsigned i = 0; i < 1024; i++) DstRowValid[i] = false;
  }
}

if (Mode == ZEROACC_MODE_ONE_ROW || Mode == ZEROACC_MODE_16_ROWS) {
  ApplyAddrMod(AddrMod);
}
```

Supporting definitions:
```c
#define ZEROACC_MODE_ONE_ROW     0
#define ZEROACC_MODE_16_ROWS     1
#define ZEROACC_MODE_HALF_OF_DST 2
#define ZEROACC_MODE_ALL_OF_DST  3
```

On Blackhole, `Adj16` is as described in [`Dst.md` in the Blackhole tree](../../../BlackholeA0/TensixTile/TensixCoprocessor/Dst.md), and `Adj32NoSwizzle` is `Adj32` from there with its `DEST_ACCESS_CFG_swizzle_32b` step left out:
```c
uint10_t Adj32NoSwizzle(uint10_t r) {
  r = Adj16(r);
  return ((r & 0x1f8) << 1) | (r & 0x207);
}
```
