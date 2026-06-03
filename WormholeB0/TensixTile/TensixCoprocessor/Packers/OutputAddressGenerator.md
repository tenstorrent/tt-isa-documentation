# Output Address Generator

## Functional model

When a pack instruction starts, logic like the following executes to possibly set new output addresses:

```c
uint32_t Packer0InitialAddr;
bool ADCsToAdvance[3] = {false, false, false};
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];
for (unsigned i = 0; i < 4; ++i) {
  auto& PackerI = Packers[i];
  auto& PackerIConfig = ConfigState.Packers[i];

  uint32_t Addr = PackerIConfig.L1_Dest_addr + !PackerIConfig.Sub_l1_tile_header_size;
  if (i == 0) Packer0InitialAddr = Addr;
  else if (Packer0InitialAddr.Bit[31]) Addr += Packer0InitialAddr;

  if (!(CurrentInstruction.PackerMask.Bit[i])) continue;

  uint2_t WhichADC = CurrentThread;
  if (CurrentInstruction.OvrdThreadId) {
    WhichADC = PackerIConfig.Addr_cnt_context;
    if (WhichADC == 3) WhichADC = 0;
  }
  auto& ADC = ADCs[WhichADC].Packers.Channel[1];
  uint32_t YZW_Addr = ConfigState.PCK0_ADDR_BASE_REG_1_Base
    + ADC.Y * ConfigState.PCK0_ADDR_CTRL_XY_REG_1_Ystride
    + ADC.Z * ConfigState.PCK0_ADDR_CTRL_ZW_REG_1_Zstride
    + ADC.W * ConfigState.PCK0_ADDR_CTRL_ZW_REG_1_Wstride;
  if (TTArchitecture == Blackhole) {
    YZW_Addr >>= 4; // Blackhole: YZW_Addr is in units of bytes, with 16B alignment required
  } else {
    YZW_Addr &= ~15; // Wormhole: YZW_Addr is in units of 16B chunks, with 256B alignment required
  }
  Addr += YZW_Addr;
  ADCsToAdvance[WhichADC] = true;

  if (PackerIConfig.Add_l1_dest_addr_offset) {
    Addr += PackerI.l1_dest_addr_offset; // This 16b field is set by TDMA-RISC
  }
  if (Addr > PackerIConfig.Pack_limit_address * 2 + 1) {
    Addr -= PackerIConfig.Pack_fifo_size * 2;
    // Note that Pack_limit_address and Pack_fifo_size are in THCON_SEC[01]_REG9, with non-standard naming
  }

  bool PerformingCompression = !(ConfigState.THCON_SEC0_REG1_All_pack_disable_zero_compress_ovrd ? ConfigState.THCON_SEC0_REG1_All_pack_disable_zero_compress.Bit[i] : PackerIConfig.Disable_zero_compress);
  if (PerformingCompression) {
    if (PackerI.RSIStream.NeedsNewAddress) {
      PackerI.RSIStream.ByteAddress = (Addr & 0x1ffff) << 4;
      PackerI.RSIStream.NeedsNewAddress = false;
    }
    Addr += PackerIConfig.Row_start_section_size;
    // NB: The RLEZero stream does not need an address, as when performing
    // compression, said stream gets interleaved with the data stream: there
    // will be 32x datum, then 32x 4b RLEZero counts, then 32x datum, then
    // 32x 4b RLEZero counts, and so forth.
  }

  bool OutputFormatLessThan16Bits = !!(PackerIConfig.Out_data_format & 2);
  if (OutputFormatLessThan16Bits) {
    // Note that this captures all BFP output formats, but also FP8 and I8,
    // even though FP8 and I8 don't produce an exponent stream.
    if (PackerI.ExponentStream.NeedsNewAddress) {
      PackerI.ExponentStream.ByteAddress = (Addr & 0x1ffff) << 4;
      PackerI.ExponentStream.NeedsNewAddress = false;
    }
    Addr += PackerIConfig.Exp_section_size;
  }

  if (PackerI.DataStream.NeedsNewAddress) {
    PackerI.DataStream.ByteAddress = (Addr & 0x1ffff) << 4;
    PackerI.DataStream.NeedsNewAddress = false;
  }

  if (CurrentInstruction.Last || CurrentInstruction.Flush) {
    // Note that these assignments do not affect the current instruction,
    // but they mean that the _next_ instruction will compute new addresses.
    PackerI.RSIStream.NeedsNewAddress = true;
    PackerI.ExponentStream.NeedsNewAddress = true;
    PackerI.DataStream.NeedsNewAddress = true;
  }
}

auto AddrMod = ThreadConfig[CurrentThread].ADDR_MOD_PACK_SEC[CurrentInstruction.AddrMod];
for (unsigned i = 0; i < 3; ++i) {
  if (!ADCsToAdvance[i]) continue;
  auto& ADC = ADCs[i].Packers.Channel[1];
  // NB: Channel[0] is modified as part of the input address generator

  if (AddrMod.YdstClear) {
    ADC.Y = 0;
    ADC.Y_Cr = 0;
  } else if (AddrMod.YdstCR) {
    ADC.Y_Cr += AddrMod.YdstIncr;
    ADC.Y = ADC.Y_Cr;
  } else {
    ADC.Y += AddrMod.YdstIncr;
  }

  if (AddrMod.ZdstClear) {
    ADC.Z = 0;
    ADC.Z_Cr = 0;
  } else {
    ADC.Z += AddrMod.ZdstIncr;
  }
}
```

## Output alignment

Note the `(Addr & 0x1ffff) << 4` as part of all the assignments to `ByteAddress`: packer output is always done as aligned 16-byte writes to L1. Individual datums are at most 4 bytes, so datums get buffered up at the bottom of the packer pipeline, and then written out to L1 once 16 bytes have been buffered up. These buffers persist between consecutive pack instructions, so the output of an _individual_ pack instruction needn't be aligned, but the output of a _group_ of pack instructions will be. If these buffers are forcibly flushed before they are full, then they will be padded with zeroes to make them full.

When one of these buffers writes 16 bytes to L1, `ByteAddress` will be incremented by 16.

## `NeedsNewAddress`

Per the code in the functional model, output addresses are only changed when `NeedsNewAddress` is true. If `NeedsNewAddress` is false, then `ByteAddress` is not changed: output data will be appended to the pre-existing address. On reset, `NeedsNewAddress` will be true, and if `CurrentInstruction.Last` or `CurrentInstruction.Flush` is set, then `NeedsNewAddress` will be set to true at the _end_ of executing the instruction, meaning that `NeedsNewAddress` will be true for the _next_ instruction. If `CurrentInstruction.Last` or `CurrentInstruction.Flush` is set, then the output buffers sitting before L1 will be flushed: any buffer containing data will be padded with zeroes until it contains 16 bytes, then the 16 bytes will be written out to L1. Note that while `Last` and `Flush` are equivalent for the output address generator, they are not equivalent in the input address generator.

## ADCs and `AddrMod`

The Y, Z, and W counters of _some_ ADC are used to compute `YZW_Addr`, which is then incorporated into the output address. The masking in `YZW_Addr &= ~15` on Wormhole makes this feature less useful than it might otherwise be, as it means that these counters can only be used to adjust the output address in units of 256 bytes. Blackhole improves the usability of this feature by allowing the output address to be adjusted in units of 16 bytes.

After `YZW_Addr` has been computed, the Y and Z counters are updated based on `CurrentInstruction.AddrMod`. The Y, Z, and W counters can also be updated using `SETADC`, `SETADCXY`, `INCADCXY`, `ADDRCRXY`, `SETADCZW`, `INCADCZW`, `ADDRCRZW`, and `REG2FLOP`.
