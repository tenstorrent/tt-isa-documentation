# The Mover

There is a hardware block within each Tensix tile for accelerating `memcpy` and `memset` operations, which is called the mover. It can do two things:
* `memcpy`, from [L1](L1.md), to any of L1 or [Tensix Backend Configuration](TensixCoprocessor/BackendConfiguration.md) or [RISCV NC Instruction RAM](BabyRISCV/InstructionRAM.md), in aligned 16 byte units.
* `memset`, with a value of `0`, to any of L1 or Tensix Backend Configuration or RISCV NC Instruction RAM, in aligned 16 byte units.

The mover is made available to RISCV cores via [TDMA-RISC](TDMA-RISC.md), and is made available to the Tensix coprocessor via the Tensix [`XMOV`](TensixCoprocessor/XMOV.md) instruction.

The mover is the only entity capable of writing to RISCV NC Instruction RAM, though the RAM will become corrupted if the mover is writing to it at the same time as the RISCV NC Frontend is reading from it.

Other options also exist for accelerated `memcpy` from L1 to L1: the NoC can be instructed to perform a large read or write where both the source tile and the destination tile are set to the local tile, or unpackers and packers can be instructed.

## Functional model

```c
void Mover(uint32_t dst, uint32_t src, uint32_t count, uint32_t mode) {
  // Determine target address.
  if (mode == XMOV_L1_TO_L1 || mode == XMOV_L0_TO_L1) {
    // In the "_TO_L1" modes, dst must be an address in L1.
    if (dst >= (1024*1464)) UndefinedBehavior();
  } else {
    // In the "_TO_L0" modes, dst can refer to either Tensix Backend Configuration or Instruction RAM.
    if (dst <= 0xffff) dst += TENSIX_CFG_BASE;
    else if (0x40000 <= dst && dst <= 0x4ffff) dst = (dst - 0x40000) + MEM_NCRISC_IRAM_BASE;
    else dst = NOWHERE; // Operation still happens, but the writes get discarded.

    if ((dst & 0xffff) + count > 0x10000) {
      UndefinedBehavior(); // Don't even think about trying to access more than one region at a time.
    }
  }

  // Perform the operation.
  if (mode == XMOV_L1_TO_L1 || mode == XMOV_L1_TO_L0) {
    // In the "L1_TO_" modes, a memcpy is done, and src must be an address in L1.
    if (src >= (1024*1464)) UndefinedBehavior();
    memcpy(dst, src, count); // NB: Takes multiple cycles to complete.
  } else {
    // In the "L0_TO_" modes, a memset is done.
    memset(dst, 0, count);   // NB: Takes multiple cycles to complete.
  }
}
```

Supporting definitions:
```c
typedef enum {
  XMOV_L0_TO_L1 = 0,
  XMOV_L1_TO_L0 = 1,
  XMOV_L0_TO_L0 = 2,
  XMOV_L1_TO_L1 = 3,
} xmov_direction_t;
```

Note that the "L0" in the various mode names is a complete misnomer; the functional model above outlines what the modes do.

## Performance

The mover has two connections to [L1](L1.md); one that it uses for reads, and one that it uses for writes. The [L1 access ports](L1.md#port-assignments) that it uses are however shared with many other clients, so performance can suffer heavily if there is access port contention:

|Mode|Measured performance<br/>(ideal conditions)|Measured performance<br/>(with some L1 access port contention)|
|---|---|---|
|`XMOV_L1_TO_L1` or<br/>`XMOV_L1_TO_L0`<br/>(`memcpy`)|Eight 128b reads and eight 128b writes every 11 cycles<br/>i.e. 93.1 bits copied per cycle|One 128b read and one 128b write every four cycles<br/>i.e. 32 bits copied per cycle|
|`XMOV_L0_TO_L1`<br/>(L1 `memset`)|One 128b write per cycle<br/>i.e. 128 bits written per cycle|One 128b write every three cycles<br/>i.e. 42.7 bits written per cycle|
|`XMOV_L0_TO_L0`<br/>(Non-L1 `memset`)|One 128b write per cycle<br/>i.e. 128 bits written per cycle|One 128b write per cycle<br/>i.e. 128 bits written per cycle|
