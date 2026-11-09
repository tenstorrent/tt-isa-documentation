# Using an overlay stream as general-purpose MMIO registers

If a NoC Overlay stream is idle, software can repurpose some of its MMIO configuration/state registers for general use. In aggregate, this presents a memory area of non-trivial size with some nice properties:
* Accessible from all RISCV cores, and accessible from other tiles (or the host system) over the NoC.
* Writes from RISCV have a maximum throughput of one write per cycle (whereas RISCV writes to L1 have a maximum throughput of one write every five cycles).
* Writes to some locations can perform atomic increments. This is the only memory space on which the host system can perform atomic increments, as the PCI Express tile cannot translate host atomics to NoC atomic requests. Along with [Tensix semaphores](../../TensixTile/TensixCoprocessor/SyncUnit.md#semaphores), it is also the only memory space on which RISCV cores can perform atomic increments by using plain `sw` instructions (as RISCV cores need to instruct either the [Tensix Scalar Unit (ThCon)](../../TensixTile/TensixCoprocessor/ScalarUnit.md) or an [NIU](../MemoryMap.md) to perform atomic increments on L1, even when the L1 is local).
* Accesses do not suffer from, nor contribute to, contention on L1 (though each NoC Overlay can only service one MMIO access per cycle, so contention isn't entirely avoided, merely moved around).

Within each stream (of which there are 64 per Tensix tile, and 32 per Ethernet tile), the repurposable MMIO registers are:

|Register Index|Width|Notes|
|---|--:|---|
|`STREAM_BUF_SIZE_REG_INDEX`|17 bits||
|`STREAM_BUF_START_REG_INDEX`|17 bits|Writing any value will also set `STREAM_RD_PTR_REG_INDEX` and `STREAM_WR_PTR_REG_INDEX` to zero|
|`STREAM_RD_PTR_REG_INDEX`|17 bits|Writes will also set `STREAM_NEXT_RECEIVED_MSG_SIZE_REG_INDEX` to zero, and `STREAM_NEXT_RECEIVED_MSG_ADDR_REG_INDEX` to `STREAM_BUF_START_REG_INDEX + STREAM_RD_PTR_REG_INDEX`|
|`STREAM_WR_PTR_REG_INDEX`|17 bits||
|`STREAM_CURR_PHASE_BASE_REG_INDEX`|20&nbsp;bits||
|`STREAM_CURR_PHASE_REG_INDEX`|20 bits|`STREAM_CURR_PHASE_BASE_REG_INDEX` is added on writes, and subtracted again on reads. Can be atomically incremented as part of writing to `STREAM_PHASE_AUTO_CFG_HEADER_REG_INDEX`|
|`STREAM_GATHER_CLEAR_REG_INDEX`|17 bits|Only available for streams capable of receiving in gather mode; otherwise writes are ignored and reads as zero|
|`STREAM_GATHER_REG_INDEX`|4 bits|Only available for streams capable of receiving in gather mode; otherwise writes are ignored and reads as zero|
|`STREAM_LOCAL_SRC_MASK_REG_INDEX`|24 bits|Only available for streams capable of receiving in gather mode; otherwise writes are ignored and reads as zero|
|`STREAM_LOCAL_SRC_MASK_REG_INDEX + 1`|24 bits|Only available for streams capable of receiving in gather mode; otherwise writes are ignored and reads as zero. In Ethernet tiles, width is only 8 bits|
|`STREAM_LOCAL_SRC_MASK_REG_INDEX + 2`|16 bits|Only available for streams capable of receiving in gather mode; otherwise writes are ignored and reads as zero. In Ethernet tiles, width is 0 bits|
|`STREAM_MCAST_DEST_NUM_REG_INDEX`|6 bits|Only available for streams capable of transmitting in multicast mode; otherwise writes are ignored and reads as zero|
|`STREAM_MCAST_DEST_REG_INDEX`|19 bits|Only available for streams capable of transmitting in multicast mode; otherwise writes are ignored and reads as zero|
|`STREAM_MEM_BUF_SPACE_AVAILABLE_ACK_THRESHOLD_REG_INDEX`|4 bits||
|`STREAM_MISC_CFG_REG_INDEX`|24 bits|Stream configuration bits; software should avoid setting the `PHASE_AUTO_CONFIG` field to `true`, as doing so can cause the stream to immediately start loading configuration from L1 (all other fields are safe to change while the stream is idle)|
|`STREAM_MSG_INFO_PTR_REG_INDEX`|17 bits||
|`STREAM_MSG_INFO_WR_PTR_REG_INDEX`|17 bits||
|`STREAM_MSG_INFO_CAN_PUSH_NEW_MSG_REG_INDEX`|N/A|Read only, returning `STREAM_MSG_INFO_PTR_REG_INDEX == STREAM_MSG_INFO_WR_PTR_REG_INDEX`|
|`STREAM_PHASE_AUTO_CFG_HEADER_REG_INDEX`|20 bits|On write, all 32 bits are relevant: the low 12 are used to increment `STREAM_CURR_PHASE_REG_INDEX` and the high 20 are stored. On read, the high 20 are from the previous write, and the low 12 should be ignored|
|`STREAM_PHASE_AUTO_CFG_PTR_BASE_REG_INDEX`|17 bits||
|`STREAM_PHASE_AUTO_CFG_PTR_REG_INDEX`|17 bits|`STREAM_PHASE_AUTO_CFG_PTR_BASE_REG_INDEX` is added on writes, and subtracted again on reads|
|`STREAM_REMOTE_DEST_BUF_SIZE_REG_INDEX`|17 bits|Writes will also write the value to all `STREAM_REMOTE_DEST_BUF_SPACE_AVAILABLE_REG_INDEX + i`|
|`STREAM_REMOTE_DEST_BUF_SPACE_AVAILABLE_REG_INDEX + i`|17 bits|Read-only, but can be written as part of `STREAM_REMOTE_DEST_BUF_SIZE_REG_INDEX`, and can be incremented by `j` by writing `(j << 6) + i` to `STREAM_REMOTE_DEST_BUF_SPACE_AVAILABLE_UPDATE_REG_INDEX`. For most streams, only `i == 0` exists, but in streams capable of transmitting in multicast mode, all of `0 ≤ i < 32` exist|
|`STREAM_DEBUG_STATUS_REG_INDEX + 2`|N/A|Read-only, but bit 3 will be set when all `STREAM_REMOTE_DEST_BUF_SPACE_AVAILABLE_REG_INDEX + i` are non-zero. This value can be up to two cycles stale.|
|`STREAM_REMOTE_DEST_BUF_START_HI_REG_INDEX`|15 bits|Only available for streams capable of transmitting to DRAM buffers; otherwise writes are ignored and reads as zero|
|`STREAM_REMOTE_DEST_BUF_START_REG_INDEX`|17 bits|Writes also set `STREAM_REMOTE_DEST_WR_PTR_REG_INDEX` to zero|
|`STREAM_REMOTE_DEST_WR_PTR_REG_INDEX`|17 bits||
|`STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_HI_REG_INDEX`|15 bits|Only available for streams capable of transmitting to DRAM buffers; otherwise writes are ignored and reads as zero|
|`STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_REG_INDEX`|17&nbsp;bits||
|`STREAM_REMOTE_DEST_REG_INDEX`|18 bits||
|`STREAM_REMOTE_DEST_TRAFFIC_PRIORITY_REG_INDEX`|4 bits||
|`STREAM_REMOTE_SRC_PHASE_REG_INDEX`|20 bits|`STREAM_CURR_PHASE_BASE_REG_INDEX` is added on writes, and subtracted again on reads|
|`STREAM_REMOTE_SRC_REG_INDEX`|24 bits||
|`STREAM_SCRATCH_REG_INDEX + i`|24&nbsp;bits|Only available for streams capable of transmitting to DRAM buffers; otherwise writes are ignored and reads as zero. Where available, the allowed `i` is `0 ≤ i < 6`|

On Blackhole, a read of `STREAM_REMOTE_DEST_BUF_SPACE_AVAILABLE_REG_INDEX + i` also returns a second 9-bit field in bits 25 through 17. That field has no reset value, writes to `STREAM_REMOTE_DEST_BUF_SIZE_REG_INDEX` leave it unchanged, a write of `m` to `STREAM_REMOTE_DEST_MSG_INFO_BUF_SIZE_REG_INDEX` (register index 12) sets it to 2<sup>m+1</sup>, and a write to `STREAM_REMOTE_DEST_BUF_SPACE_AVAILABLE_UPDATE_REG_INDEX` adds bits 31 through 23 of the written value to it (so writing `(j << 6) + i` with a negative `j` also subtracts one from it). Software using the register as a 17-bit counter should mask what it reads to the low 17 bits.

## Memory ordering

If RISCV code does an MMIO store to one of these registers followed by an MMIO load from a _different_ register (for example writing to `STREAM_REMOTE_DEST_BUF_SIZE_REG_INDEX` then reading from `STREAM_REMOTE_DEST_BUF_SPACE_AVAILABLE_REG_INDEX`), then [RISCV memory ordering](../../TensixTile/BabyRISCV/MemoryOrdering.md) needs to be considered, as otherwise the RISCV core might reorder the operations to have the load happen first. To avoid the problem, following a sequence of writes, it is sufficient to load from the most recently-written register (the load result does not need to be used for anything).

A similar concern applies if a NoC is used to perform multiple related requests. In this case, [NoC ordering](../Ordering.md) should be considered; it suffices to use `NOC_CMD_VC_STATIC` on all the NoC requests, or `NOC_CMD_VC_LINKED` on all NoC requests except for the last.
