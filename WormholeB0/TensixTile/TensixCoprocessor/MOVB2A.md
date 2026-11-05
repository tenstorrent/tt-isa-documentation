# `MOVB2A` (Move one row or four rows from `SrcB` to `SrcA`)

**Summary:** Move one row of datums from `SrcB` to `SrcA`, or move an aligned block of four rows of datums from `SrcB` to `SrcA`.

**Backend execution unit:** [Matrix Unit (FPU)](MatrixUnit.md)

## Syntax

```c
TT_MOVB2A(/* u6 */ SrcARow,
          /* u2 */ AddrMod,
         (/* bool */ Move4Rows) << 1,
          /* u6 */ SrcBRow)
```

## Encoding

![](../../../Diagrams/Out/Bits32_MOVB2A.svg)

On Blackhole, `AddrMod` is a `u3` rather than a `u2`, giving this encoding:

![](../../../Diagrams/Out/Bits32_MOVB2A_BH.svg)

## Functional model

This instruction will, if necessary, spend time waiting at the Wait Gate before being dispatched to the Matrix Unit (FPU):

```c
while (SrcB[MatrixUnit.SrcBBank].AllowedClient != MatrixUnit) {
  wait;
}
```

Once dispatched to the Matrix Unit (FPU):
```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];
uint4_t SrcBFmt = ConfigState.ALU_FORMAT_SPEC_REG_SrcB_override ? ConfigState.ALU_FORMAT_SPEC_REG_SrcB_val : ConfigState.ALU_FORMAT_SPEC_REG1_SrcB;
if ((TTArchitecture == Blackhole) && !ThreadConfig[CurrentThread].DISABLE_IMPLIED_SRCB_FMT_Base) {
  SrcBFmt = ImpliedSrcBFmt[MatrixUnit.SrcBBank];
}
bool FlushDenormals = !ConfigState.ALU_ACC_CTRL_Zero_Flag_disabled_src;

// Determine the row range.
unsigned NumRows;
SrcARow += RWCs[CurrentThread].SrcA;
SrcBRow += RWCs[CurrentThread].SrcB;
if (Move4Rows) {
  if ((TTArchitecture == Blackhole) && (SrcARow & 3)) {
    // On Blackhole, in practice the SrcA rows are not aligned down: the move writes SrcA rows
    // starting at SrcARow (the SrcB rows are still aligned down).
    UndefinedBehavior();
  }
  NumRows = 4;
  SrcARow &= 0x3c;
  SrcBRow &= 0x3c;
} else {
  NumRows = 1;
  SrcARow &= 0x3f;
  SrcBRow &= 0x3f;
}

// Actually copy the row(s).
unsigned FirstSrcARow = SrcARow;
for (; NumRows; --NumRows, ++SrcARow, ++SrcBRow) {
  for (unsigned Column = 0; Column < 16; ++Column) {
    if (LaneConfig[Column / 2].BLOCK_DEST_MOV.Bit[Column & 1]) continue;
    uint19_t SrcVal = SrcB[MatrixUnit.SrcBBank][SrcBRow][Column];
    if (FlushDenormals && !(SrcVal & 0xff)) SrcVal = 0;
    SrcVal = TruncateSrc(SrcVal, SrcBFmt);
    SrcA[MatrixUnit.SrcABank][SrcARow][Column] = SrcVal;
  }
}
if (TTArchitecture == Blackhole) {
  // Blackhole erratum: SrcA rows FirstSrcARow + 4 through FirstSrcARow + 7 that are in the same
  // aligned group of 16 rows as FirstSrcARow can also become zero, for one-row and four-row moves
  // alike (in practice, after a four-row move they always do).
  for (unsigned Row = FirstSrcARow + 4; Row < FirstSrcARow + 8 && (Row & ~15) == (FirstSrcARow & ~15); ++Row) {
    for (unsigned Column = 0; Column < 16; ++Column) {
      if (LaneConfig[Column / 2].BLOCK_DEST_MOV.Bit[Column & 1]) continue;
      if (UnpredictableValue()) SrcA[MatrixUnit.SrcABank][Row][Column] = 0;
    }
  }
}

// Advance the RWCs.
ApplyAddrMod(AddrMod);
```

## Instruction scheduling

`MOVB2A` does not wait at the Wait Gate for `SrcA[MatrixUnit.SrcABank].AllowedClient == SrcClient::MatrixUnit`: it writes the bank that `MatrixUnit.SrcABank` selects even while the Unpackers own it, which is the bank unpacker 0 writes next. If unpacker 0 writes that bank (an [`UNPACR`](UNPACR_Regular.md), or an [`UNPACR_NOP`](UNPACR_NOP_ZEROSRC.md) that clears it) before giving it to the Matrix Unit, and `MOVB2A` runs before the Matrix Unit has the bank, then which of the two writes survives depends on timing, and the result is `UndefinedBehavior`. This includes an unpacker instruction issued before `MOVB2A`, even from the same thread, as the Unpackers can finish it after `MOVB2A` writes. Software should first make sure the Matrix Unit has the bank: with [`STALLWAIT`](STALLWAIT.md) (block bit B6 and condition code C10, or C7 on Blackhole), with an earlier instruction from the same thread that waits for it (e.g. `MOVA2D` or `ELWADD`), or by having the thread that issued the unpacker's instructions wait for that unpacker to finish (`STALLWAIT` condition C1) before it signals this thread. If the Unpackers give the bank without writing it ([`SETDVALID`](SETDVALID.md), or the [`UNPACR_NOP`](UNPACR_NOP_SETDVALID.md) that only gives it), what `MOVB2A` wrote is still there once the Matrix Unit has the bank.

If `MOVB2A` is used, then on the next cycle, the only instructions that the Matrix Unit (FPU) can accept are `MOVD2A` and `MOVB2A`. If a thread presents any other Matrix Unit (FPU) instruction, then hardware will automatically stall the thread for one cycle. On Blackhole, this restriction instead applies for the next two cycles, and the automatic stall is for up to two cycles.

`MOVB2A` must not start exactly three cycles after the Matrix Unit (FPU) starts an `MVMUL`, `DOTPV`, `ELWADD`, `ELWSUB`, `ELWMUL`, `GAPOOL` or `GMPOOL`; doing so is `UndefinedBehavior`. In practice, one entry of an internal queue is lost for good, after which the `Dst` writes of later instructions from that list can go to the wrong rows or be dropped. As the Matrix Unit (FPU) can start an instruction later than the thread issues it, counting instructions (or `NOP`s) between the two is not a reliable way to avoid this; one reliable way is to use [`STALLWAIT`](STALLWAIT.md) (with block bit B6 and condition code C7, or C4 on Blackhole) prior to `MOVB2A`.
