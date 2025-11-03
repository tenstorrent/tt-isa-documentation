# Input Address Generator

## Functional model

When a pack instruction starts, logic like the following executes to determine the starting input address and datum count:

```c
bool ADCsToAdvance[3] = {false, false, false};
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];
for (unsigned i = 0; i < 4; ++i) {
  if (!(CurrentInstruction.PackerMask.Bit[i])) continue;

  auto& PackerI = Packers[i];
  auto& PackerIConfig = PackerI.Config[StateID];
  uint2_t WhichADC = CurrentThread;
  if (CurrentInstruction.OvrdThreadId) {
    WhichADC = PackerIConfig.Addr_cnt_context;
    if (WhichADC == 3) WhichADC = 0;
  }
  auto& ADC = ADCs[WhichADC].Packers.Channel[0];
  uint32_t Addr = ConfigState.PCK0_ADDR_BASE_REG_0_Base
    + ADC.X * (ConfigState.PCK0_ADDR_CTRL_XY_REG_0_Xstride & 0xf)
    + ADC.Y * ConfigState.PCK0_ADDR_CTRL_XY_REG_0_Ystride
    + ADC.Z * ConfigState.PCK0_ADDR_CTRL_ZW_REG_0_Zstride
    + ADC.W * ConfigState.PCK0_ADDR_CTRL_ZW_REG_0_Wstride;
  ADCsToAdvance[WhichADC] = true;

  uint32_t BytesPerDatum, ADC_X_Mask;
  switch (PackerIConfig.In_data_format & 3) {
  case 0:  BytesPerDatum = 4, ADC_X_Mask = 0x3; break; // FP32, TF32, I32
  case 1:  BytesPerDatum = 2, ADC_X_Mask = 0x7; break; // FP16, BF16, I16
  default: BytesPerDatum = 1, ADC_X_Mask = 0xf; break; // All other formats
  }

  if (CurrentInstruction.Flush) {
    PackerI.InputNumDatums = 0;
  } else {
    PackerI.InputNumDatums = ADCs[WhichADC].Packers.Channel[1].X - ADC.X + 1;
  }
  if (CurrentInstruction.ZeroWrite || CurrentInstruction.Flush) {
    PackerI.InputSource = INPUT_SOURCE_DEV_NULL;
    PackerI.InputSourceAddr = 0;
    PackerI.InputSourceStride = 0;
  } else if (i == 0 && PackerIConfig.Source_interface_selection == 1) {
    Addr = (PackerIConfig.L1_source_addr << 18) + (Addr & 0x3ffff); // Only low 18 bits of Addr used; high bits of L1 address come from L1_source_addr
    Addr = (Addr & ~0xf) + BytesPerDatum * (ADC.X & ADC_X_Mask);
    PackerI.InputSource = INPUT_SOURCE_L1;
    PackerI.InputSourceAddr = Addr & 0x1fffff; // Byte address into L1
    PackerI.InputSourceStride = BytesPerDatum; // L1 is addressed in bytes
    // If In_data_format specifies a BFP format, then signs and mantissas are fetched
    // from L1, but the shared exponent is always taken as zero.
  } else {
    Addr = ((Addr / BytesPerDatum) & ~ADC_X_Mask) + (ADC.X & ADC_X_Mask);
    Addr += Config.DEST_TARGET_REG_CFG_PACK_SEC[i].Offset << 4;
    PackerI.InputSource = INPUT_SOURCE_Dst;
    PackerI.InputSourceAddr = Addr & 0x3fff; // Datum index into Dst; `>> 4` is row, `& 0xf` is column
    PackerI.InputSourceStride = 1; // Dst is addressed in datums, not in bytes
  }
}

auto AddrMod = ThreadConfig[CurrentThread].ADDR_MOD_PACK_SEC[CurrentInstruction.AddrMod];
for (unsigned i = 0; i < 3; ++i) {
  if (!ADCsToAdvance[i]) continue;
  auto& ADC = ADCs[i].Packers.Channel[0];
  // NB: Channel[1] is modified as part of the output address generator

  if (AddrMod.YsrcClear) {
    ADC.Y = 0;
    ADC.Y_Cr = 0;
  } else if (AddrMod.YsrcCR) {
    ADC.Y_Cr += AddrMod.YsrcIncr;
    ADC.Y = ADC.Y_Cr;
  } else {
    ADC.Y += AddrMod.YsrcIncr;
  }

  if (AddrMod.ZsrcClear) {
    ADC.Z = 0;
    ADC.Z_Cr = 0;
  } else {
    ADC.Z += AddrMod.ZsrcIncr;
  }
}
```

## Input alignment

The input address must be aligned to a complete datum. When fetching datums from L1, `ADC.X` is the only address component capable of addressing more precisely than 16 bytes. When fetching datums from `Dst`, `ADC.X` is again the only address component capable of particularly fine addressing, though in this case the exact definition of _fine_ depends on `In_data_format`.

Note that `PCK0_ADDR_CTRL_XY_REG_0_[XYZW]stride` are used to determine the _starting_ address, but once the starting address has been determined, datums are fetched from the contiguous addresses `InputSourceAddr + i * InputSourceStride for i in range(InputNumDatums)`. For discontiguous input, either use the downsampling functionality, or issue multiple pack instructions.

Though `PCK0_ADDR_CTRL_XY_REG_0_Xstride` can in theory take any value, the only _sane_ values for `PCK0_ADDR_CTRL_XY_REG_0_Xstride` are `PCK0_ADDR_CTRL_XY_REG_0_Xstride == 0` or `PCK0_ADDR_CTRL_XY_REG_0_Xstride == BytesPerDatum`.

## ADCs and `AddrMod`

The X, Y, Z, and W counters of _some_ ADC are used to compute `Addr`.

After the address has been computed, the Y and Z counters are updated based on `CurrentInstruction.AddrMod`. The X, Y, Z, and W counters can also be updated using `SETADC`, `SETADCXX`, `SETADCXY`, `INCADCXY`, `ADDRCRXY`, `SETADCZW`, `INCADCZW`, `ADDRCRZW`, and [`REG2FLOP`](../REG2FLOP_ADC.md).

Note that `Channel[1].X` is used as part of the `InputNumDatums` computation (along with `Channel[0].X`), whereas all other places within the input address generator exclusively use `Channel[0]`. Meanwhile, the output address generator uses all of `Channel[1]` _except_ `Channel[1].X`.
