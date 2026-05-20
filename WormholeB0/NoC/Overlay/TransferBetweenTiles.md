# Overlay streams transmitting / receiving with other streams

An overlay stream can be configured to transmit messages to another overlay stream using the NoC. Some overlay streams can also use Ethernet to transmit messages to an overlay stream at the other end of the point-to-point ethernet link; see [stream capabilities](README.md#stream-capabilities) for details. This will cause two streams to be interacting: one as the transmitter, and one as the receiver.

## General configuration

To configure the phase at the receiver, software should:
1. Set `REMOTE_SOURCE` within `STREAM_MISC_CFG_REG_INDEX` (and clear both `SOURCE_ENDPOINT` and `LOCAL_SOURCES_CONNECTED`).
2. Allocate some space in L1 to act as a receive buffer (message contents FIFO), and set `STREAM_BUF_START_REG_INDEX` and `STREAM_BUF_SIZE_REG_INDEX` to tell the stream about it (these are both in units of 16 bytes, so `>> 4` required to convert from byte addresses).
3. Allocate some space in L1 to act as a message header array, and write the base address to both `STREAM_MSG_INFO_PTR_REG_INDEX` and `STREAM_MSG_INFO_WR_PTR_REG_INDEX` (these are both in units of 16 bytes, so `>> 4` required to convert from byte addresses). The length of the array needs to be greater than or equal to (16 bytes times) the number of messages expected to be received during the phase.
4. Set [`STREAM_REMOTE_SRC_REG_INDEX`](#stream_remote_src_reg_index) with the [X/Y coordinates](../Coordinates.md) and stream ID of transmitter (this is required for handshaking, and for sending flow control packets to the correct place).
5. Set `STREAM_REMOTE_SRC_PHASE_REG_INDEX` such that `STREAM_CURR_PHASE_BASE_REG_INDEX + STREAM_REMOTE_SRC_PHASE_REG_INDEX` as computed by the receiver will equal `STREAM_CURR_PHASE_BASE_REG_INDEX + STREAM_CURR_PHASE_REG_INDEX` as computed by the transmitter (this acts as a handshake to ensure that the two streams are ready to communicate with each other).
6. Optionally set [`STREAM_MEM_BUF_SPACE_AVAILABLE_ACK_THRESHOLD_REG_INDEX`](#stream_mem_buf_space_available_ack_threshold_reg_index) to configure how often to send flow control updates to the transmitter.

To configure the phase at the transmitter, software should:
1. Set `REMOTE_RECEIVER` within `STREAM_MISC_CFG_REG_INDEX` (and clear both `RECEIVER_ENDPOINT` and `LOCAL_RECEIVER`).
2. Set `STREAM_REMOTE_DEST_BUF_START_REG_INDEX` and `STREAM_REMOTE_DEST_BUF_SIZE_REG_INDEX` equal to that of the receiver's step 2 above. If the stream is _capable_ of transmitting to DRAM, `STREAM_REMOTE_DEST_BUF_START_HI_REG_INDEX` and `STREAM_REMOTE_DEST_BUF_SIZE_HI_REG_INDEX` also need to be set to zero (if the stream is not capable of transmitting to DRAM, these settings are always zero, and writes to them are ignored).
3. Set `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_REG_INDEX` equal to that of the receiver's step 3 above. If the stream is _capable_ of transmitting to DRAM, `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_HI_REG_INDEX` also needs to be set to zero (if the stream is not capable of transmitting to DRAM, this setting is always zero, and writes to it are ignored).
4. Set [`STREAM_REMOTE_DEST_REG_INDEX`](#stream_remote_dest_reg_index) with the [X/Y coordinates](../Coordinates.md) (†) and stream ID of receiver.
5. If the stream is _capable_ of transmitting to DRAM, ensure that the low three bits of `STREAM_SCRATCH_REG_INDEX + 0` do not contain `0b101` or `0b110` or `0b111` (if the stream is not capable of transmitting to DRAM, these bits are always zero, and writes to them are ignored).

## Unicast configuration

In addition to the general configuration above, to configure the phase at the receiver, software should:
1. Set the `REMOTE_SRC_IS_MCAST` field within `STREAM_MISC_CFG_REG_INDEX` to `false` (this is a performance optimization, so things still work if software sets this incorrectly).
2. Set the `STREAM_REMOTE_SRC_DEST_INDEX` field within [`STREAM_REMOTE_SRC_REG_INDEX`](#stream_remote_src_reg_index) to `0`.

In addition to the general configuration above, to configure the phase at the transmitter, software should:
1. If the stream is _capable_ of transmitting in multicast mode, set the `STREAM_MCAST_EN` field within [`STREAM_MCAST_DEST_REG_INDEX`](#stream_mcast_dest_reg_index) to `false` (if the stream is not capable of transmitting in multicast mode, this field is always `false`, and writes to [`STREAM_MCAST_DEST_REG_INDEX`](#stream_mcast_dest_reg_index) are ignored).
2. If the stream is _capable_ of transmitting in multicast mode, set `STREAM_MCAST_DEST_NUM_REG_INDEX` to `1` (if the stream is not capable of transmitting in multicast mode, this register always contains `1`, and writes to it are ignored).

## Multicast configuration

Some streams are capable of transmitting in multicast mode, with up to 32 distinct receiver streams in different tiles. The receivers need to all have the same stream ID, and have their L1 buffers in the same location in their local tile's L1.

In addition to the general configuration above, to configure the phase at the receiver, software should:
1. Set the `REMOTE_SRC_IS_MCAST` field within `STREAM_MISC_CFG_REG_INDEX` to `true` (this is a performance optimization, so things still work if software sets this incorrectly).
2. Set the `STREAM_REMOTE_SRC_DEST_INDEX` field within [`STREAM_REMOTE_SRC_REG_INDEX`](#stream_remote_src_reg_index) to `i`, where all receivers have `i` less than the transmitter's `STREAM_MCAST_DEST_NUM_REG_INDEX`, and every receiver has a distinct `i`.

In addition to the general configuration above, to configure the phase at the transmitter, software should:
1. Set all fields of [`STREAM_MCAST_DEST_REG_INDEX`](#stream_mcast_dest_reg_index).
2. Set `STREAM_MCAST_DEST_NUM_REG_INDEX` to the number of multicast receivers (which can be between 1 and 31).

## Handshake

At the start of the phase, if the _previous_ phase specified `NEXT_PHASE_SRC_CHANGE` (or if the stream has just come out of reset and therefore there was no previous phase) the receiving stream will:
1. Expect the transmitter's first transmission to arrive at `STREAM_BUF_START_REG_INDEX`.
2. Speculatively send a handshake response packet to the transmitter. The packet will contain `STREAM_CURR_PHASE_BASE_REG_INDEX + STREAM_REMOTE_SRC_PHASE_REG_INDEX` as the phase number.
3. Wait for the transmitter to send a handshake request or to send data. During this time, if it receives a handshake request from the transmitter, it'll send a handshake response back, and then switch to exclusively waiting for data.

If `NEXT_PHASE_SRC_CHANGE` was _not_ specified, then the receiver skips the above, and goes straight through to waiting for data. Notably, this means it won't respond to handshake requests, so `NEXT_PHASE_SRC_CHANGE` and `NEXT_PHASE_DEST_CHANGE` need to be consistent between transmitter and receiver.

At the start of the phase, if the _previous_ phase specified `NEXT_PHASE_DEST_CHANGE` (or if the stream has just come out of reset and therefore there was no previous phase) the transmitting stream will:
1. Set `STREAM_REMOTE_DEST_WR_PTR_REG_INDEX` to zero (corresponding to the transmitter's step 1 above).
2. Check whether it recently received an appropriate handshake response from (all) the receiver(s). If so, skip the remaining steps. This might happen because of the transmitter's step 2 above. In this context, "appropriate" means that the phase number in the handshake response equals `STREAM_CURR_PHASE_BASE_REG_INDEX + STREAM_CURR_PHASE_REG_INDEX`.
3. Send a handshake request packet to (all) the receiver(s).
4. Wait to receive appropriate handshake response packets from (all) the receiver(s). This should happen due to the transmitter's step 2 or step 3 above.

If `NEXT_PHASE_DEST_CHANGE` was _not_ specified, then the transmitter skips the above, and can start transmitting straight away.

## Flow control

The receiving stream can set `DATA_BUF_NO_FLOW_CTRL` in `STREAM_MISC_CFG_REG_INDEX` to `true`. In this case, no flow control packets will be sent to the transmitter. This can be set if the receiver's receive buffer is capable of receiving all of the phase's messages without needing to wrap. The transmitting stream may also need `DEST_DATA_BUF_NO_FLOW_CTRL` set, otherwise it might wait for flow control updates at the end of the phase.

The transmitting stream can set `DEST_DATA_BUF_NO_FLOW_CTRL` in `STREAM_MISC_CFG_REG_INDEX` to `true`. This will cause the "Wait for destination mostly (or entirely) done" step in the stream state machine to be skipped. It is also skipped when `NEXT_PHASE_DEST_CHANGE` in `STREAM_MISC_CFG_REG_INDEX` is `false` (though this has additional effects).

## Virtual channel control

To ensure that data arrives in order, the transmitter will use static virtual channel assignment for its data packets and for its handshake request packets. For multicast transmission, the buddy bit is controlled by the `STREAM_MCAST_VC` field within `STREAM_MCAST_DEST_REG_INDEX`. For unicast transmission, the buddy bit and the class bits come from `UNICAST_VC_REG` within `STREAM_MISC_CFG_REG_INDEX`. It is possible for a unicast transmitter to bend the rules slightly and specify a multicast class within these bits; if this is done, then the packets will remain unicast, but travel with virtual channel numbers normally reserved for multicast traffic.

The receiver also uses static virtual channel assignment for handshake responses. The buddy bit and class bits come from `REG_UPDATE_VC_REG` within `STREAM_MISC_CFG_REG_INDEX`.

## Register reference

### `STREAM_REMOTE_SRC_REG_INDEX`

This register is present in the receiving stream, and contains details about the transmitter:

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|6|`STREAM_REMOTE_SRC_X`|[X coordinate](../Coordinates.md) of the transmitting overlay, or `63` if this stream is capable of receiving over ethernet and the transmitter is the overlay at the other end of the point-to-point ethernet link|
|6|6|`STREAM_REMOTE_SRC_Y`|[Y coordinate](../Coordinates.md) of the transmitting overlay, or `63` if this stream is capable of receiving over ethernet and the transmitter is the overlay at the other end of the point-to-point ethernet link|
|12|6|`REMOTE_SRC_STREAM_ID`|Stream ID of the transmitter stream within the transmitting overlay (between `0` and `63`)|
|18|6|`STREAM_REMOTE_SRC_DEST_INDEX`|Unique index of the particular receiver within all of the transmitter's receivers; must be `0` when the transmitter is unicast, and less than the transmitter's `STREAM_MCAST_DEST_NUM_REG_INDEX` when the transmitter is multicast|
|24|8|Reserved|Writes ignored, reads as zero|

### `STREAM_REMOTE_DEST_REG_INDEX`

This register is present in the transmitting stream, and contains details about the receiver:

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|6|`STREAM_REMOTE_DEST_X`|[X coordinate](../Coordinates.md) of the receiving overlay, or `63` if this stream is capable of transmitting over ethernet and the receiver is the overlay at the other end of the point-to-point ethernet link. If transmitting in multicast mode, this is the `StartX` of the rectangle defining the range of receivers (see `STREAM_MCAST_DEST_REG_INDEX` for `EndX`)|
|6|6|`STREAM_REMOTE_DEST_Y`|[Y coordinate](../Coordinates.md) of the receiving overlay, or `63` if this stream is capable of transmitting over ethernet and the receiver is the overlay at the other end of the point-to-point ethernet link. If transmitting in multicast mode, this is the `StartY` of the rectangle defining the range of receivers (see `STREAM_MCAST_DEST_REG_INDEX` for `EndY`)|
|12|6|`STREAM_REMOTE_DEST_STREAM_ID`|Stream ID of the receiver stream within the receiving overlay (between `0` and `63`)|
|18|14|Reserved|Writes ignored, reads as zero|

### `STREAM_MCAST_DEST_REG_INDEX`

In streams capable of transmitting in multicast mode, the `STREAM_MCAST_EN` field within `STREAM_MCAST_DEST_REG_INDEX` controls whether it is transmitting in multicast mode. The other fields of `STREAM_MCAST_DEST_REG_INDEX` specify the properties of the multicast, and only have an effect when `STREAM_MCAST_EN` is `true`.

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|6|`STREAM_MCAST_END_X`|`EndX` of the rectangle defining the range of receivers|
|6|6|`STREAM_MCAST_END_Y`|`EndY` of the rectangle defining the range of receivers|
|12|1|`STREAM_MCAST_EN`|Corresponds to `NOC_CMD_BRCST_PACKET` in [`NOC_CTRL`](../MemoryMap.md#noc_ctrl); `true` means transmitting in multicast mode, whereas `false` means transmitting in unicast mode|
|13|1|`STREAM_MCAST_LINKED`|Corresponds to `NOC_CMD_VC_LINKED` in [`NOC_CTRL`](../MemoryMap.md#noc_ctrl); `true` means that the stream will submit multiple NoC request packets in a single NoC transaction. If `NEXT_PHASE_DEST_CHANGE` is set within `STREAM_MISC_CFG_REG_INDEX`, the stream will automatically unset `NOC_CMD_VC_LINKED` on the last outbound packet within a phase. Long-lived NoC transactions are dangerous things, so software is discouraged from setting this, though it is made safer by setting both `STREAM_MCAST_SRC_SIDE_DYNAMIC_LINKED` and `STREAM_MCAST_DEST_SIDE_DYNAMIC_LINKED`.|
|14|1|`STREAM_MCAST_VC`|Corresponds to the buddy bit of `NOC_CMD_STATIC_VC` in [`NOC_CTRL`](../MemoryMap.md#noc_ctrl)|
|15|1|`STREAM_MCAST_NO_PATH_RES`|Corresponds to the _inverse_ of `NOC_CMD_PATH_RESERVE` in [`NOC_CTRL`](../MemoryMap.md#noc_ctrl); `false` means that all routers along the multicast tree need to reserve virtual channel numbers for the transaction before any data leaves the initiating overlay. When set to `false`, multicast takes longer to happen, but when set to `true`, software is responsible for ensuring that its traffic patterns do not cause deadlocks|
|16|1|`STREAM_MCAST_XY`|Corresponds to `NOC_CMD_BRCST_XY` in [`NOC_CTRL`](../MemoryMap.md#noc_ctrl)|
|17|1|`STREAM_MCAST_SRC_SIDE_DYNAMIC_LINKED`|If `true`, makes `STREAM_MCAST_LINKED` somewhat safer: `NOC_CMD_VC_LINKED` will be automatically unset when the message metadata FIFO in the transmitter contains less than two entries|
|18|1|`STREAM_MCAST_DEST_SIDE_DYNAMIC_LINKED`|If `true`, makes `STREAM_MCAST_LINKED` somewhat safer: `NOC_CMD_VC_LINKED` will be automatically unset when the transmitter's view of the receiver's receive window is not large enough to receive two packets|

## `STREAM_MEM_BUF_SPACE_AVAILABLE_ACK_THRESHOLD_REG_INDEX`

In the receiving stream, `STREAM_MEM_BUF_SPACE_AVAILABLE_ACK_THRESHOLD_REG_INDEX` can be set to a value between 0 and 15, which controls the threshold for sending flow control update packets to the transmitting stream:

|Value|Threshold|
|--:|---|
|0|`0` (i.e. send immediately)|
|1|`STREAM_BUF_SIZE_REG_INDEX >> 1` (i.e. send once at least half of our receive buffer is available)|
|2|`STREAM_BUF_SIZE_REG_INDEX >> 2` (i.e. send once at least a quarter of our receive buffer is available)|
|3|`STREAM_BUF_SIZE_REG_INDEX >> 3` (i.e. send once at least an eighth of our receive buffer is available)|
|4|`STREAM_BUF_SIZE_REG_INDEX >> 4`|
|5|`STREAM_BUF_SIZE_REG_INDEX >> 5`|
|6|`STREAM_BUF_SIZE_REG_INDEX >> 6`|
|7|`STREAM_BUF_SIZE_REG_INDEX >> 7`|
|8|`0` (i.e. send immediately)|
|9|`STREAM_BUF_SIZE_REG_INDEX - (STREAM_BUF_SIZE_REG_INDEX >> 1)`|
|10|`STREAM_BUF_SIZE_REG_INDEX - (STREAM_BUF_SIZE_REG_INDEX >> 2)`|
|11|`STREAM_BUF_SIZE_REG_INDEX - (STREAM_BUF_SIZE_REG_INDEX >> 3)`|
|12|`STREAM_BUF_SIZE_REG_INDEX - (STREAM_BUF_SIZE_REG_INDEX >> 4)`|
|13|`STREAM_BUF_SIZE_REG_INDEX - (STREAM_BUF_SIZE_REG_INDEX >> 5)`|
|14|`STREAM_BUF_SIZE_REG_INDEX - (STREAM_BUF_SIZE_REG_INDEX >> 6)`|
|15|`STREAM_BUF_SIZE_REG_INDEX - (STREAM_BUF_SIZE_REG_INDEX >> 7)`|

Note that `STREAM_MEM_BUF_SPACE_AVAILABLE_ACK_THRESHOLD_REG_INDEX` is ignored at the very end of each phase; a flow control packet will always be sent to the transmitting stream to inform it that the receiver has received the last packet of the phase (unless `DATA_BUF_NO_FLOW_CTRL` is set).
