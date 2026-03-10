# Overlay streams transmitting to DRAM buffers

Some overlay streams are capable of transmitting to buffers in DRAM (either GDDR attached to the ASIC, or pinned host memory over PCIe). See [stream capabilities](README.md#stream-capabilities) for details.

To configure the phase at the transmitter, software should:
1. Set `REMOTE_RECEIVER` within `STREAM_MISC_CFG_REG_INDEX` (and clear both `RECEIVER_ENDPOINT` and `LOCAL_RECEIVER`). `DEST_DATA_BUF_NO_FLOW_CTRL` also needs to be set within `STREAM_MISC_CFG_REG_INDEX`.
2. Set [`STREAM_REMOTE_DEST_REG_INDEX`](TransferBetweenTiles.md#stream_remote_dest_reg_index) with the [X/Y coordinates](../Coordinates.md) of the DRAM tile (or of the PCIe tile if transmitting to pinned host memory). The stream ID within `STREAM_REMOTE_DEST_REG_INDEX` can be set to anything.
3. Set `STREAM_REMOTE_DEST_BUF_START_REG_INDEX` and `STREAM_REMOTE_DEST_BUF_START_HI_REG_INDEX` to specify the start address of the DRAM buffer. This is in the address space of the tile referenced by step 2. These two registers are combined to form a 32-bit value, and then shifted left by four bits to form a 36-bit address. `STREAM_REMOTE_DEST_BUF_START_REG_INDEX` is 17 bits wide, and the remaining 15 bits come from `STREAM_REMOTE_DEST_BUF_START_HI_REG_INDEX`.
4. Set `STREAM_REMOTE_DEST_BUF_SIZE_REG_INDEX` and `STREAM_REMOTE_DEST_BUF_SIZE_HI_REG_INDEX` to specify the size of the DRAM buffer. As per the previous step, `STREAM_REMOTE_DEST_BUF_SIZE_REG_INDEX` and `STREAM_REMOTE_DEST_BUF_SIZE_HI_REG_INDEX` have 17 and 15 bits respectively, are joined together to form a 32-bit value, and then shifted left by four bits to form a 36-bit length. Note that the DRAM buffer is a plain array; it is not circular.
5. If there is a message header array in DRAM, set `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_REG_INDEX` and `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_HI_REG_INDEX` to its start address, following the usual pattern.
6. Set `NCRISC_CMD_ID` and either (or both) of `NCRISC_TRANS_EN` / `NCRISC_TRANS_EN_IRQ_ON_BLOB_END` within [`STREAM_SCRATCH_REG_INDEX + 0`](#stream_scratch_reg_index).
7. If the stream is _capable_ of transmitting in multicast mode, set the `STREAM_MCAST_EN` field within [`STREAM_MCAST_DEST_REG_INDEX`](TransferBetweenTiles.md#stream_mcast_dest_reg_index) to `false` (if the stream is not capable of transmitting in multicast mode, this field is always `false`, and writes to [`STREAM_MCAST_DEST_REG_INDEX`](TransferBetweenTiles.md#stream_mcast_dest_reg_index) are ignored).
8. If the stream is _capable_ of transmitting in multicast mode, set `STREAM_MCAST_DEST_NUM_REG_INDEX` to `1` (if the stream is not capable of transmitting in multicast mode, this register always contains `1`, and writes to it are ignored).

To configure the phase at the NIU of the receiving tile, software should:
1. If there is a message header array in DRAM, clear the "Double store disable" bit of [`NIU_CFG_0`](../MemoryMap.md). Otherwise, set the "Double store disable" bit of `NIU_CFG_0`.

## Handshake

At the start of the phase, if the _previous_ phase specified `NEXT_PHASE_DEST_CHANGE` (or if the stream has just come out of reset and therefore there was no previous phase) the stream will:
1. Set `STREAM_REMOTE_DEST_WR_PTR_REG_INDEX` to zero.
2. If `NCRISC_TRANS_EN` was set within `STREAM_SCRATCH_REG_INDEX + 0`, send an IRQ to the PIC.
3. Wait to receive an appropriate handshake response packet from the DRAM buffer. This will not happen naturally; it requires software to write to [`STREAM_DEST_PHASE_READY_UPDATE_REG_INDEX`](#stream_dest_phase_ready_update_reg_index).

If `NEXT_PHASE_DEST_CHANGE` was _not_ specified, then the transmitter skips the above, and can start transmitting straight way. Software may wish to manually reset `STREAM_REMOTE_DEST_WR_PTR_REG_INDEX` in this case. Software may wish to lie and clear in `NEXT_PHASE_DEST_CHANGE` in the previous phase to avoid having to perform a handshake.

## Flow control

There is no flow control when transmitting to a DRAM buffer. The NoC requests are all posted writes, so there is no direct way for software to know that the writes have arrived. If software needs to confirm that the writes have arrived, it needs to manually send a non-posted read or write request to the same DRAM buffer, [using the same static virtual channel assignment as used by the stream](TransferBetweenTiles.md#virtual-channel-control), and wait for the read response or write acknowledgement.

## Register reference

### `STREAM_SCRATCH_REG_INDEX`

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|1|`NCRISC_TRANS_EN`|If `true`, will send an IRQ to the PIC as the phase starts|
|1|1|`NCRISC_TRANS_EN_IRQ_ON_BLOB_END`|If `true`, will send an IRQ to the PIC as the phase ends|
|2|1|`NCRISC_CMD_ID`|Should be set to `true` when transmitting to a DRAM buffer|
|3|21|Available for general use|

Note that `STREAM_SCRATCH_REG_INDEX + 1` through `STREAM_SCRATCH_REG_INDEX + 5` are also available for general use, containing 24 bits each.

### `STREAM_DEST_PHASE_READY_UPDATE_REG_INDEX`

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|6|`PHASE_READY_DEST_NUM`|Should be set to zero|
|6|20|`PHASE_READY_NUM`|Should be set to `STREAM_CURR_PHASE_BASE_REG_INDEX + STREAM_CURR_PHASE_REG_INDEX`|
|26|1|`PHASE_READY_MCAST`|Should be set to `false`|
|27|5|Reserved|Can be set to anything|
