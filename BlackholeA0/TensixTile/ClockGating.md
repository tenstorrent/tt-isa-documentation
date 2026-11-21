# Clock gating

Most blocks in a Tensix tile have a clock gater, which stops the block's clock while the block is idle and starts it again when the block has work to do. Each gater has an enable bit: while it is `false`, the block's clock runs all the time. Each also has a hysteresis: the number of cycles the block must have been idle before its clock stops. Apart from `Dst`'s, every enable on this page is `false` after reset, so none of these blocks has its clock stopped until software or firmware sets the enables.

The NIU and the router have their own enables, in [`NIU_CFG_0`](../NoC/MemoryMap.md#niu_cfg_0) and [`ROUTER_CFG_0`](../NoC/MemoryMap.md#router_cfg_0), and [bit 12 of `NIU_CFG_0`](../NoC/MemoryMap.md#tile-clock-disable) stops the clock of almost the whole tile regardless of whether it is idle.

## `RISCV_DEBUG_REG_CG_CTRL_EN`

**Address:** `0xFFB1_2244`

|Bit index|Clock gater enabled|
|--:|---|
|0|Tensix register blocks|
|1|Matrix Unit (FPU)|
|2|Matrix Unit tiles|
|3|Vector Unit (SFPU)|
|4|[Mover](Mover.md)|
|5|Packers|
|6|Unpacker 0|
|7|Unpacker 1|
|8|XSearch|
|9|Scalar Unit (ThCon)|
|10|RISCV T0|
|11|RISCV T1|
|12|RISCV T2|
|13|L1 return path|
|14|Tensix instruction frontend (shared by all three threads)|
|15|L1 banks|
|16|`SrcB`|
|≥17|No effect|

All 32 bits can be written and read back. The reset value is `0`.

## `RISCV_DEBUG_REG_CG_CTRL_HYST0` to `RISCV_DEBUG_REG_CG_CTRL_HYST2`

**Addresses:** `0xFFB1_2070`, `0xFFB1_2074` and `0xFFB1_207C`

Each byte holds the hysteresis, in cycles, of the gaters of one or more of the blocks above; only the low 7 bits of each byte are used. The reset value of every byte is 16.

|Register|Bits 0-7|Bits 8-15|Bits 16-23|Bits 24-31|
|---|---|---|---|---|
|`RISCV_DEBUG_REG_CG_CTRL_HYST0`|Tensix register blocks|Matrix Unit (FPU)|Mover|Packers|
|`RISCV_DEBUG_REG_CG_CTRL_HYST1`|Unpackers|XSearch|Scalar Unit (ThCon)|RISCV T0 / T1 / T2|
|`RISCV_DEBUG_REG_CG_CTRL_HYST2`|L1 return path|Tensix instruction frontend|L1 banks|`SrcB`|

### Hysteresis of the Tensix instruction frontend

The Tensix instruction frontend's gater also clocks the [Sync Unit](TensixCoprocessor/SyncUnit.md), which takes RISCV T<sub>i</sub>'s writes to [`SemaphoreAccess`](TensixCoprocessor/SyncUnit.md#riscv-access-to-semaphores). While that gater is enabled, its hysteresis must be at least 1. At 0, the frontend's clock runs only in cycles in which something kicks it, such as an instruction being pushed, however busy the RISCV T cores are, and a `SemaphoreAccess` write made while the clock is stopped completes without taking effect: the semaphore keeps its old value. At 1 or more, a running RISCV T core keeps the clock going, so no such write is lost, including one made right after the core wakes from a park on its PCBuf (see [idle RISCV cores](#idle-riscv-cores)).

## `RISCV_DEBUG_REG_DEST_CG_CTRL`

**Address:** `0xFFB1_2240`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|8|Hysteresis of the `Dst` gaters; only the low 7 bits are used|
|8|24|Enables of the 24 clock gaters of `Dst`|

The reset value is `0xFFFF_FF01`: unlike the other gaters on this page, the `Dst` gaters are enabled from reset, with a hysteresis of 1. Writing `0` disables them.

## `RISCV_TDMA_REG_CLK_GATE_EN`

Bits 0 to 6 of [`RISCV_TDMA_REG_CLK_GATE_EN`](TDMA-RISC.md) (`0xFFB1_1024`) are further enables, each ORed with an enable in `RISCV_DEBUG_REG_CG_CTRL_EN`, except for bit 6, which has none:

|Bit index|Clock gater enabled|Same as `RISCV_DEBUG_REG_CG_CTRL_EN` bit|
|--:|---|--:|
|0|Packers|5|
|1|XSearch|8|
|2|Scalar Unit (ThCon)|9|
|3|Mover|4|
|4|Unpacker 0|6|
|5|Unpacker 1|7|
|6|TDMA-RISC interface|None|

Their reset value is `0`.

## Idle RISCV cores

The clock gater of RISCV T<sub>i</sub> (enabled by bit 10 + i of `RISCV_DEBUG_REG_CG_CTRL_EN`) stops the core's clock while the core is blocked on a read of its [PCBuf](BabyRISCV/PCBufs.md) (`PC_BUF_BASE`) with that PCBuf's FIFO empty, and its instruction fetch has gone quiet. A core spinning in a loop, e.g. polling a mailbox or L1, keeps its clock running. To park RISCV T<sub>i</sub> with its clock stopped, have it load from `PC_BUF_BASE` and follow the load with at least one instruction that is not a branch or jump: a jump directly after the load keeps the instruction fetch busy, and the clock never stops. With a hysteresis of 2, the clock stops about 35 to 55 cycles after the load. RISCV B pushing a value to that PCBuf completes the load, and the core continues.

A RISCV T core held in [soft reset](SoftReset.md#riscv-soft-reset) keeps its clock running, whatever the enables say, so that its reset takes effect. It also counts as busy for the Tensix instruction frontend's gater, so while any of the three is held in soft reset, that clock doesn't stop either. To have the clocks of unused RISCV T cores and of the frontend stop, release the cores from soft reset and park them as above.

RISCV NC has no clock gater: its clock runs whenever the tile's clock runs.
