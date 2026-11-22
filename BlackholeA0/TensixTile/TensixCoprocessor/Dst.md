# `Dst`

The `Dst` register can be viewed as either having 1024 rows and 16 columns of 16-bit data, or 512 rows and 16 columns of 32-bit data. Instruction descriptions use `Dst16b` for the former, and `Dst32b` for the latter. In either case, the underlying storage is the same:

```c
uint16_t DstBits[1024][16] = UnpredictableValue(); // no power-on reset value
```

In addition, each of the 1024 rows has 1 valid bit associated with it:

```c
bool DstRowValid[1024] = {true, ..., true};
```

Note that the power-on reset state can result in reads of `UnpredictableValue()`. Software should scrub `Dst` at initialization time, preferably with an `SFPSTORE` of all 1024 rows to a known value, or minimally with a [`ZEROACC`](ZEROACC.md) of all rows to clear `DstRowValid` to `false`.

Most of the time, `Dst16b[Row][Col]` is simple syntactic sugar for `DstBits[Adj16(Row)][Col]`.

The same region of memory can instead be viewed as a 512x16 matrix of 32-bit data; reads from `Dst32b[Row][Col]` give `(DstBits[Adj32(Row)][Col] << 16) | DstBits[Adj32(Row) + 8][Col]`, and writes to `Dst32b[Row][Col]` perform the inverse unpacking and write to `DstBits[Adj32(Row)][Col]` and `DstBits[Adj32(Row) + 8][Col]`. At any given time, software is expected to be exclusively using `Dst16b` or exclusively using `Dst32b`; mixing and matching `Dst16b` and `Dst32b` is _possible_, but tends to require great care. When using `Dst32b`, `Row` remains a 10-bit index, though the mapping down to `Adj32(Row)` can only yield 512 distinct values.

If bit 11 of `RISCV_DEBUG_REG_DBG_FEATURE_DISABLE` is set, then `Dst16b[Row][Col]` stops being syntactic sugar for `DstBits[Adj16(Row)][Col]`, and instead reads from `Dst16b[Row][Col]` give the high 16 bits of `Dst32b[Row][Col]`, and writes to `Dst16b[Row][Col]` write to the high 16 bits of `Dst32b[Row][Col]` (and also write an `UnpredictableValue()` to the low 16 bits). Use of this bit in software is `UnsupportedFunctionality` because the resulting `UnpredictableValue` semantics can lead to difficult-to-diagnose issues.

The `Adj16` and `Adj32` functions are:
```c
uint10_t Adj16(uint10_t r) {
  if (Config.DEST_ACCESS_CFG_remap_addrs) {
    r = (r & 0x3c7) ^ ((r & 0x030) >> 1) ^ ((r & 0x008) << 2);
  }
  return r;
}

uint10_t Adj32(uint10_t r) {
  r = Adj16(r);
  if (Config.DEST_ACCESS_CFG_swizzle_32b) {
    r = (r & 0x3f3) ^ ((r & 0x018) >> 1) ^ ((r & 0x004) << 1);
  }
  return ((r & 0x1f8) << 1) | (r & 0x207);
}
```

Note that `Config` in the above functions refers to Tensix backend configuration. In addition to their usage in these two functions, `Config.DEST_ACCESS_CFG_remap_addrs` and `Config.DEST_ACCESS_CFG_swizzle_32b` also affect how packers address `Dst`: a packer reads `Dst16b` and `Dst32b` rows through these functions too, `remap_addrs` sets the row spacing of [`PACR`](PACR.md)'s strided reads, and a strided 32-bit read needs `swizzle_32b`. `Config.DEST_ACCESS_CFG_zeroacc_absolute_tile_mode` affects only [`ZEROACC`](ZEROACC.md).

Each of the valid bits is indexed by physical row, as the row would be placed without `DEST_ACCESS_CFG_swizzle_32b`: an access to `Dst32b[Row]` consults `DstRowValid[Adj32NoSwizzle(Row)]` (and does not consult `Adj32NoSwizzle(Row) + 8`), whereas an access to `Dst16b[Row]` consults `DstRowValid[Adj16(Row)]`. `Adj32NoSwizzle` is `Adj32` with its `swizzle_32b` step left out:
```c
uint10_t Adj32NoSwizzle(uint10_t r) {
  r = Adj16(r);
  return ((r & 0x1f8) << 1) | (r & 0x207);
}
```
So with `swizzle_32b` set, a `Dst32b` row's valid bit is not the valid bit of the 16-bit row that holds its high half; software that switches widths over data written with `swizzle_32b` set should not rely on rows that `ZEROACC` marked undefined in between.

Not every client consults them; [`ZEROACC`](ZEROACC.md) says how each reads an undefined row. In particular, `ZEROACC` doesn't give the Vector Unit (SFPU) zeros: [`SFPLOAD`](SFPLOAD.md) of an undefined row is `UndefinedBehavior`, so software that wants zeros in `Dst` for the Vector Unit to read must write them, e.g. with [`SFPSTORE`](SFPSTORE.md).

If a `ZEROACC` executes in the same cycle as a Vector Unit or unpacker write to `Dst`, the write's update of `DstRowValid` is lost, even if the `ZEROACC` targets other rows (e.g. the other half of a double-buffered `Dst`). Likewise, if writes to `Dst` from different clients (Matrix Unit, Vector Unit, unpacker, RISCV T) execute in the same cycle and would set the valid bits of physical rows in the same 256-row group that are congruent modulo 8, only one valid bit is set: that of the row whose number is the bitwise OR of theirs, which can be none of them. Software must not let such writes race with another thread's `ZEROACC` or with each other.

## Data types

Each datum in `Dst16b` is up to 16 bits wide, holding one of:
* **BF16 (1 sign bit, 8 bit exponent, 7 bit mantissa)**. Unpackers can losslessly convert BFP8 / BFP4 / BFP2 to BF16.
* **FP16 (1 sign bit, 5 bit exponent, 10 bit mantissa)**. Unpackers can losslessly convert FP8 (1 sign bit, 5 bit exponent, 2 bit mantissa) to FP16. They can also losslessly convert BFP8a / BFP4a / BFP2a to FP16.
* **Integer "8" (1 sign bit, 10 bit magnitude)**. The range of this type is -1023 through +1023, albeit the majority of hardware conversions to/from this type involve a range of -127 through +127 or 0 through 255. Internally, this type is overlaid onto FP16, using a fixed raw exponent of 16 (or sometimes a raw exponent of 0 when the magnitude is zero).
* **Integer "16" (1 sign bit, 15 bit magnitude)**. This type is intended only for opaque data transfer of 16 bits; there are no computation instructions involving this type. If used for opaque data transfer, this type can be used to contain _any_ 16 bits, including unsigned 16-bit data.

Each datum in `Dst32b` is 32 bits wide, holding one of:
* **FP32 (1 sign bit, 8 bit exponent, 23 bit mantissa)**. TF32 data can also be stored in this form, though most computation instructions will operate on it with full FP32 precision for as long as it is in `Dst32b`.
* **Integer "32" (1 sign bit, 31 bit magnitude)**. This is a sign/magnitude format rather than a two's complement format, though the Vector Unit (SFPU) can convert between the two.

Note that the coprocessor does not entirely conform to IEEE 754 for FP32 / FP16 / BF16. See [floating-point bit patterns](FloatBitPatterns.md) for details.

## Data type bit layout

Most of the time, software does not need to care about the exact bit layout of types in `Dst`. Nevertheless, the information is provided here to clarify the semantics of what happens if software does an implicit `bitcast` from one type to another.

**BF16:**

![](../../../Diagrams/Out/Bits32_Dst16_BF16.svg)

**FP16:**

![](../../../Diagrams/Out/Bits32_Dst16_FP16.svg)

The representation of infinity differs from IEEE 754, and NaN is not supported; see [FP16 bit patterns](../../../WormholeB0/TensixTile/TensixCoprocessor/FloatBitPatterns.md#fp16) for details.

**Integer "8":**

![](../../../Diagrams/Out/Bits32_Dst16_INT8.svg)

The low five bits usually contain the value `16`, but unpackers will instead set these bits to `0` when the magnitude is zero.

**Integer "16":**

![](../../../Diagrams/Out/Bits32_Dst16_INT16.svg)

**FP32:**

![](../../../Diagrams/Out/Bits32_Dst32_FP32.svg)

**Integer "32":**

![](../../../Diagrams/Out/Bits32_Dst32_INT32.svg)

## Moving data around

Unpacker 0 can be used to move from L1 to Dst (`UNPACR`), and [packers](Packers/README.md) can be used to move from Dst back to L1 ([`PACR`](PACR.md)).

The Vector Unit (SFPU) can move from Dst to LReg (`SFPLOAD`) and from LReg to Dst (`SFPSTORE`).

The Matrix Unit (FPU) can move from Dst to SrcA (`MOVD2A`) and from Dst to SrcB (`MOVD2B`). The other direction usually involves computation instructions rather than movement instructions, but plain movement is possible via `MOVA2D` and `MOVB2D`.

## Instruction scheduling

After issuing a Matrix Unit (FPU) instruction which writes to `Dst`, then for the next five cycles, the aligned 8x16 block of `Dst` containing that write cannot be read. If a thread presents a Matrix Unit (FPU) instruction which wants to read from that block, then hardware will automatically stall the thread for an appropriate number of cycles. In particular, for instructions which accumulate onto `Dst` (such as [`MVMUL`](MVMUL.md), [`GAPOOL`](GAPOOL.md), [`DOTPV`](DOTPV.md), [`GMPOOL`](GMPOOL.md), [`ELWMUL`](ELWMUL.md)), software needs to be looping over at least six distinct 8x16 blocks of `Dst` to avoid being stalled. Additionally, if using multiple fidelity phases, with one loop over blocks of `Dst` and one loop over fidelity phases, then the fidelity loop should be the _outer_ loop to avoid being stalled.

In addition, each half of `Dst` (either rows 0 through 511 of `DstBits`, or rows 512 through 1023) is only accessed by one client at a time, where the clients are the Matrix Unit (FPU), the Vector Unit (SFPU), the unpackers, the packers, and RISCV. While one client has an access in progress against a half of `Dst`, the other clients will wait before accessing that half. The accesses tracked in this way are Matrix Unit (FPU) instructions which access `Dst` (including `MOVD2A` and `MOVD2B`, which only read it), Vector Unit (SFPU) [`SFPLOAD`](SFPLOAD.md) and [`SFPSTORE`](SFPSTORE.md) instructions, unpacks to `Dst`, [`PACR`](PACR.md) instructions, and RISCV accesses to `Dst`. The wait lasts until the access in progress has finished, rather than for a fixed number of cycles. This keeps two clients from accessing the same half of `Dst` at the same time; it does not replace the instruction scheduling rules of individual instructions, such as [`SFPLOAD`'s](SFPLOAD.md#instruction-scheduling).

An `SFPSTORE` scheduled via [`SFPLOADMACRO`](SFPLOADMACRO.md) is the exception: the Vector Unit (SFPU) holds a half of `Dst` for a fixed seven cycles after each `SFPLOAD`, `SFPSTORE` or `SFPLOADMACRO` into it, and a scheduled store writes `Dst` about three cycles after its `SFPLOADMACRO` plus its delay. So a store scheduled with a delay of 5, 6 or 7 cycles, or one whose delay counts instructions and is still waiting for them, can write after the other clients have been let back into that half. Each half of `Dst` takes one write per cycle into each of its two groups of rows (the rows whose `DstBits` row, `Adj16(Row)` or `Adj32(Row)` as above, has bit 4 clear, and the rows whose `DstBits` row has bit 4 set), and the Vector Unit's write wins: if the store writes in the same cycle as a Matrix Unit (FPU) instruction or an unpack writes rows of the same half and group, that write is lost, all of it in that group, even though it targets other rows. With `DEST_ACCESS_CFG` at zero the group is bit 4 of a `Dst16b` row or bit 3 of a `Dst32b` row, and `DEST_ACCESS_CFG_remap_addrs` and `DEST_ACCESS_CFG_swizzle_32b` change which rows share a group: with `remap_addrs`, bit 5 of a `Dst16b` row or bit 4 of a `Dst32b` row; with `swizzle_32b` (which leaves `Dst16b` rows alone), bit 4 XOR bit 2 of a `Dst32b` row, or bit 5 XOR bit 2 with `remap_addrs` too. So with `swizzle_32b`, an instruction which writes an aligned group of eight `Dst32b` rows has rows in both groups of rows, and only its rows in the store's group are lost. A Matrix Unit (FPU) instruction that reads the store's rows before the store writes reads their old contents. For example, an `SFPLOADMACRO` whose store has a delay of 7 cycles, followed by a `MOVB2D` of one row into the same half and group anywhere from zero to six instructions later, loses the `MOVB2D`'s write, and a `MOVD2B` of the store's rows in the same place moves their old contents. To avoid this, a Matrix Unit (FPU) instruction or unpack which accesses that half of `Dst` should come at least 4 + Delay cycles after an `SFPLOADMACRO` whose store counts cycles, and after the `SFPNOP`s that drain a schedule which counts instructions, plus two more instructions. If the other client is on another thread, the thread that issued the `SFPLOADMACRO` drains its schedule before handing the half over, as it does for any `Dst` access. An unpack to `Dst` also meets the store from the other side: it writes `Dst` some 16 cycles after its [`UNPACR`](UNPACR_Regular.md) and claims its half only as it writes, so an `SFPLOADMACRO` issued shortly after an `UNPACR` to `Dst` takes the half first, and the unpack's write, held back for the seven cycles, can then land in the same cycle as a store with a delay of 7 cycles and be lost (with a shorter delay the store can instead write before the unpack, the reverse of their order). Waiting for the unpacker before the `SFPLOADMACRO`, e.g. `STALLWAIT` with block bit B8 and condition C1 (or with block bit B1 before a `SEMPOST`, if another thread issues the `SFPLOADMACRO`), avoids this.

An access is tracked from when it starts rather than from when its instruction is issued, so an access issued just after another can start first. A [`PACR`](PACR.md) reads `Dst` a few rows at a time, each read an access of its own, and a read that finds the Vector Unit (SFPU) using its half waits until the Vector Unit stops. So a Matrix Unit (FPU) instruction, an `SFPSTORE` or a [`ZEROACC`](ZEROACC.md) issued after a `PACR` can write rows of `Dst` that the `PACR` has yet to read, and once a stream of Vector Unit instructions (e.g. one replayed by [`REPLAY`](REPLAY.md)) gets to the half first, the `PACR` reads the rest of its rows only after the stream ends, seeing everything the stream wrote to them. No number of instructions between the two makes this safe: a `PACR`, then an `ELWADD` into the same rows with up to 2 instructions between them packs some of the `ELWADD`'s results (with 3 or more, none); a `PACR` of 64 rows of 32-bit `Dst` data to FP32 or BFP8, then a replayed stream of `SFPLOAD`, `SFPMUL`, `SFPSTORE` over the same 64 rows, packs what the stream wrote in its last 4 rows when nothing comes between them, and in up to its last 8 rows with up to 4 instructions between them when the NoC is also writing to L1. In the other direction, a `PACR` issued shortly after an [`UNPACR`](UNPACR_Regular.md) to `Dst` can read the old contents of the rows the unpack writes first (seen with up to 10 instructions between them, not with 12 or more). To reuse rows that a `PACR` reads, wait for the packer first, e.g. `STALLWAIT` with block bits B6 and B8 and condition C3; to pack rows that an unpack to `Dst` wrote, wait for the unpacker first, e.g. `STALLWAIT` with block bit B2 and condition C1. If the two instructions are on different threads, the thread that issued the first one waits before handing the rows over, e.g. `STALLWAIT` with block bit B1 before its `SEMGET` or `SEMPOST`.

A Matrix Unit (FPU) instruction pushed immediately after an `SFPSTORE`, with no instruction between them, can get to `Dst` first when the `SFPSTORE` is held back by [`SFPMAD`'s automatic stall](SFPMAD.md#instruction-scheduling) (it stores an `LReg` that an `SFPMAD` just before it writes): a `MOVD2A` or `MOVD2B` then moves the rows' old contents, and a `MOVA2D` writing the same rows has its result overwritten by the `SFPSTORE`. One instruction of any kind between the two (`NOP`, `SFPNOP`, `SETRWC`, `INCRWC` and `STALLWAIT` were tried) was enough in every case tried; a `STALLWAIT` with block bit B6 and condition C11 orders them regardless.

Unpacks to `Dst` and Matrix Unit (FPU) instructions share one write path into `Dst`, which the tracking of halves above doesn't cover. If an [`UNPACR`](UNPACR_Regular.md) to `Dst` writes in the same cycle as a Matrix Unit instruction writes its results, even into the other half of `Dst`, the two writes merge: the row at the bitwise OR of their two rows gets the bitwise OR of their data, and the rows they were meant to write keep their old contents (unless one of them is that row). So an unpack to `Dst` and Matrix Unit instructions which write `Dst` must not overlap: before an unpack to `Dst` starts, the thread that issued the Matrix Unit instructions waits for them with `STALLWAIT` condition C4 (e.g. with block bit B1 before its `SEMPOST`), and before Matrix Unit instructions follow an unpack to `Dst`, the thread that issued the unpack waits for it with condition C1. A RISCV write (to a semaphore, or to L1) isn't ordered after the Tensix instructions its thread issued earlier, so it can't take the place of that wait. For example, a math thread that ends a block of `MVMUL`s into one half of `Dst` and then lets another thread unpack partial sums into the other half, without waiting, can lose the results of its last `MVMUL`s.

So to hand a half of `Dst` that Matrix Unit (FPU) instructions wrote to a packer on another thread, that wait is all the thread needs: `STALLWAIT` with block bit B1 and condition C4 (and C11 if Vector Unit (SFPU) instructions also wrote the half), then `SEMPOST`. A `SEMPOST` behind that wait is seen only once those instructions' results are in `Dst`, so no further delay (`NOP`s or other padding) is needed, whatever the number of fidelity phases and whether `Dst` holds 16-bit or 32-bit data; the same wait before a `SEMPOST` that lets another thread unpack to `Dst` keeps the unpack's writes clear of the Matrix Unit's. With 32-bit data, the two halves are `Dst32b` rows 0 through 255 and rows 256 through 511 (`Adj32` maps row 256 to `DstBits` row 512).

Another thread's reads of rows that an unpack to `Dst` writes need the unpacker's wait too. The unpack holds its half of `Dst` only while it writes each row, so an [`SFPLOAD`](SFPLOAD.md), `MOVD2A` or `MOVD2B` from another thread can get to the half between two of its rows and read the old contents of the rows still to come (e.g. an [`UNPACR`](UNPACR_Regular.md) of 1024 FP32 datums to 32-bit `Dst` followed straight away by a `SEMPOST`, and on the other thread a `SEMWAIT` on that semaphore, then `SFPLOAD`s of the rows: up to 24 of the 64 rows read old; with four such `UNPACR`s before the `SEMPOST`, all of the last one's rows). So the thread that issued the unpack waits for it before handing the rows over: `STALLWAIT` with block bit B1 and condition C1, then `SEMPOST`. Once C1 is met, the unpack's writes are in `Dst`, and no further delay is needed. On the thread that issued the unpack, an `SFPLOAD`, `MOVD2A` or `MOVD2B` right behind the `UNPACR` read the new rows in every case tried; `STALLWAIT` with block bits B6 and B8 and condition C1 between them orders them regardless.

## RISCV access to `Dst`

RISCV T0 / T1 / T2 have `Dst` mapped into their address space, starting at address `0xFFBD_8000`. The nature of this mapping varies based on the Tensix backend configuration settings `RISC_DEST_ACCESS_CTRL_SEC[].{no_swizzle, unsigned_int, fmt}`; setting `no_swizzle` is `UnsupportedFunctionality`. Of these, the value of `fmt` controls the high level shape of the mapping:

|`fmt`|Shape of mapping|Possible conversions|
|--:|---|---|
|0|`float    Dst32b[ 512][16]` or<br/>`uint32_t Dst32b[ 512][16]`|Between IEEE754 FP32 bit layout and Dst FP32 bit layout,<br/>between conventional integer bit layout and Dst Integer "32" bit layout|
|1|`int32_t  Dst32b[ 512][16]`|Between two's complement and sign-magnitude,<br/>between conventional integer bit layout and Dst Integer "32" bit layout|
|2|`__fp16   Dst16b[1024][16]`|Between IEEE754 FP16 bit layout and Dst FP16 bit layout|
|3|`__bf16   Dst16b[1024][16]`|Between truncated IEEE754 FP32 bit layout and Dst BF16 bit layout|
|4|`int16_t  Dst16b[1024][16]` or<br/>`uint16_t Dst16b[1024][16]`|Between two's complement and sign-magnitude|
|5|`int8_t   Dst16b[1024][16]` or<br/>`uint8_t  Dst16b[1024][16]`|Between two's complement and sign-magnitude,<br/>between conventional integer bit layout and Dst Integer "8" bit layout|
|≥&nbsp;6|Reserved|N/A|

RISCV T0 and T1 can only access a single array element at a time, e.g. when viewing a 16-bit type, 16-bit `sh` / `lhu` instructions need to be used (32-bit `sw` / `lw` instructions will generally misbehave in these cases). RISCV T2 can access multiple array elements at once, using either scalar load/store instructions or vector load/store instructions, though the load or store still needs to be aligned to the overall size of the load or store.

For RISCV T0 and T1, the following functions describe the behavior of accessing a single element via a scalar load/store instruction. For RISCV T2, the behavior is similar, just splitting the load/store into an appropriate number of separate scalars based on `fmt`.

```c
uint32_t Load32(uint32_t Addr) {
  uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
  auto& ConfigState = Config[StateID];
  uint3_t fmt = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].fmt;
  bool no_swizzle = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].no_swizzle;
  if (no_swizzle) UnsupportedFunctionality(); // No known usage
  bool unsigned_int = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].unsigned_int;
  Addr = (Addr - 0xFFBD8000) / 4;
  uint32_t Value = Dst32b[Addr / 16][Addr % 16];
  if (!no_swizzle) {
    // Convert from Dst32b bit layout to CPU bit layout.
    Value = (Value & 0x8000ffff) | ((Value & 0x7f000000) >> 8) | ((Value & 0x00ff0000) << 7);
  }
  switch (fmt) {
  case 0: // float    Dst32b[ 512][16]
    break;
  case 1: // int32_t  Dst32b[ 512][16]
    if (no_swizzle || Value < 0x80000000) {
      // Value is Integer "32".
    } else {
      // Convert from sign-magnitude to two's complement (-0 becomes +0).
      Value = -(Value & 0x7fffffff);
    }
    break;
  default:
    UndefinedBehavior();
    break;
  }
  return Value;
}

uint16_t Load16(uint32_t Addr) {
  uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
  auto& ConfigState = Config[StateID];
  uint3_t fmt = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].fmt;
  bool no_swizzle = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].no_swizzle;
  if (no_swizzle) UnsupportedFunctionality(); // No known usage
  bool unsigned_int = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].unsigned_int;
  Addr = (Addr - 0xFFBD8000) / 2;
  uint16_t Value = Dst16b[Addr / 16][Addr % 16];
  switch (fmt) {
  case 2: // __fp16   Dst16b[1024][16]
    if (!no_swizzle) {
      // Convert from Dst16b FP16 bit layout to CPU bit layout.
      Value = (Value & 0x8000) | ((Value & 0x7fe0) >> 5) | ((Value & 0x001f) << 10);
    }
    break;
  case 3: // __bf16   Dst16b[1024][16]
    if (!no_swizzle) {
      // Convert from Dst16b BF16 bit layout to CPU bit layout.
      Value = (Value & 0x8000) | ((Value & 0x7f00) >> 8) | ((Value & 0x00ff) << 7);
    }
    break;
  case 4: // int16_t  Dst16b[1024][16]
    if (no_swizzle || unsigned_int || Value < 0x8000) {
      // Value is Integer "16".
    } else {
      // Convert from sign-magnitude to two's complement (-0 becomes +0).
      Value = -(Value & 0x7fff);
    }
    break;
  default:
    UndefinedBehavior();
    break;
  }
  return Value;
}

uint8_t Load8(uint32_t Addr) {
  uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
  auto& ConfigState = Config[StateID];
  uint3_t fmt = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].fmt;
  bool no_swizzle = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].no_swizzle;
  if (no_swizzle) UnsupportedFunctionality(); // No known usage
  bool unsigned_int = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].unsigned_int;
  Addr = (Addr - 0xFFBD8000) / 1;
  uint16_t Value16 = Dst16b[Addr / 16][Addr % 16];
  switch (fmt) {
  case 5: // int8_t   Dst16b[1024][16]
    if (no_swizzle || unsigned_int) {
      // Return low eight bits of Integer "8" magnitude.
      return (Value16 >> 5) & 0xff;
    } else {
      // Unwrap Integer "8" to sign bit and low seven bits of magnitude, then
      // convert from sign-magnitude to two's complement (-0 becomes +0).
      uint8_t Mag = (Value16 >> 5) & 0x7f;
      return Value16 & 0x8000 ? -Mag : Mag;
    }
  default:
    UndefinedBehavior();
    break;
  }
}

void Store32(uint32_t Addr, uint32_t Value) {
  uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
  auto& ConfigState = Config[StateID];
  uint3_t fmt = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].fmt;
  bool no_swizzle = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].no_swizzle;
  if (no_swizzle) UnsupportedFunctionality(); // No known usage
  switch (fmt) {
  case 0: // float    Dst32b[ 512][16]
    break;
  case 1: // int32_t  Dst32b[ 512][16]
    if (no_swizzle || Value < 0x80000000) {
      // Value is Integer "32".
    } else {
      // Convert from two's complement to sign-magnitude, clamping -2**31 to -(2**31-1).
      Value = 0x80000000 | -(Value + (Value == 0x80000000));
    }
    break;
  default:
    UndefinedBehavior();
    break;
  }
  if (!no_swizzle) {
    // Convert from CPU bit layout to Dst32b bit layout.
    Value = (Value & 0x8000ffff) | ((Value & 0x7f800000) >> 7) | ((Value & 0x007f0000) << 8);
  }
  Addr = (Addr - 0xFFBD8000) / 4;
  Dst32b[Addr / 16][Addr % 16] = Value;
}

void Store16(uint32_t Addr, uint16_t Value) {
  uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
  auto& ConfigState = Config[StateID];
  uint3_t fmt = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].fmt;
  bool no_swizzle = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].no_swizzle;
  if (no_swizzle) UnsupportedFunctionality(); // No known usage
  bool unsigned_int = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].unsigned_int;
  switch (fmt) {
  case 2: // __fp16   Dst16b[1024][16]
    if (!no_swizzle) {
      // Convert from CPU bit layout to Dst16b FP16 bit layout.
      Value = (Value & 0x8000) | ((Value & 0x7c00) >> 10) | ((Value & 0x03ff) << 5);
    }
    break;
  case 3: // __bf16   Dst16b[1024][16]
    if (!no_swizzle) {
      // Convert from CPU bit layout to Dst16b BF16 bit layout.
      Value = (Value & 0x8000) | ((Value & 0x7f80) >> 7) | ((Value & 0x007f) << 8);
    }
    break;
  case 4: // int16_t  Dst16b[1024][16]
    if (no_swizzle || unsigned_int || Value < 0x8000) {
      // Value is Integer "16".
    } else {
      // Convert from two's complement to sign-magnitude, clamping -2**15 to -(2**15-1).
      Value = 0x8000 | -(Value + (Value == 0x8000));
    }
    break;
  default:
    UndefinedBehavior();
    break;
  }
  Addr = (Addr - 0xFFBD8000) / 2;
  Dst16b[Addr / 16][Addr % 16] = Value;
}

void Store8(uint32_t Addr, uint8_t Value) {
  uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
  auto& ConfigState = Config[StateID];
  uint3_t fmt = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].fmt;
  bool no_swizzle = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].no_swizzle;
  if (no_swizzle) UnsupportedFunctionality(); // No known usage
  bool unsigned_int = ConfigState.RISC_DEST_ACCESS_CTRL_SEC[CurrentThread].unsigned_int;
  uint16_t Value16;
  switch (fmt) {
  case 5: // int8_t   Dst16b[1024][16]
    if (no_swizzle || unsigned_int || Value < 0x80) {
      // Value becomes 7 or 8 bits of Integer "8" magnitude.
      Value16 = (Value << 5) | (Value ? 16 : 0);
    } else {
      // Meant to be conversion from two's complement to sign-magnitude, but isn't.
      uint8_t Mag = 0x180 - Value - (Value == 0x80);
      // Result is then wrapped up as Integer "8".
      Value16 = 0x8000 | (Mag << 5) | 16;
    }
    break;
  default:
    UndefinedBehavior();
    break;
  }
  Addr = (Addr - 0xFFBD8000) / 1;
  Dst16b[Addr / 16][Addr % 16] = Value16;
}
```

## Debug reads of `Dst`

`Dst` can also be read by RISCV cores through the debug array registers (`RISCV_DEBUG_REG_DBG_ARRAY_RD_EN`, `RISCV_DEBUG_REG_DBG_ARRAY_RD_CMD` and `RISCV_DEBUG_REG_DBG_ARRAY_RD_DATA`), which are not otherwise described here. Such a read borrows packer 0's `Dst` read port, and due to a hardware bug it leaves packer 0 busy, even though the read itself returns the right data: a later [`STALLWAIT`](STALLWAIT.md) or other wait on the packers never finishes, and packer 0's next [`PACR`](PACR.md) either never finishes or packs the wrong data. This happens even if no `PACR` has run since reset. A [soft reset of packer 0](../SoftReset.md#packer-soft-reset) after the reads makes its next `PACR` work correctly again, so software should do that after reading `Dst` this way.

## Pseudocode helpers

The following pseudocode routines are shared across the various units that access `Dst`.

```c
uint16_t DstDecodeBF16(uint16_t x) {
  uint16_t e = x & 255;
  uint16_t m = (x >> 8) & 127;
  return (x & 0x8000) | (e << 7) | m;
}

uint16_t DstEncodeBF16(uint16_t x) {
  uint16_t e = (x >> 7) & 255;
  uint16_t m = x & 127;
  return (x & 0x8000) | (m << 8) | e;
}

uint16_t DstDecodeFP16(uint16_t x) {
  uint16_t e = x & 31;
  uint16_t m = (x >> 5) & 1023;
  return (x & 0x8000) | (e << 10) | m;
}

uint16_t DstEncodeFP16(uint16_t x) {
  uint16_t e = (x >> 10) & 31;
  uint16_t m = x & 1023;
  return (x & 0x8000) | (m << 5) | e;
}

// Note that the "FP32" encoding is also used for INT32
uint32_t DstDecodeFP32(uint32_t x) {
  return (uint32_t(DstDecodeBF16(x >> 16)) << 16) | (x & 0xFFFF);
}

uint32_t DstEncodeFP32(uint32_t x) {
  return (uint32_t(DstEncodeBF16(x >> 16)) << 16) | (x & 0xFFFF);
}
```
