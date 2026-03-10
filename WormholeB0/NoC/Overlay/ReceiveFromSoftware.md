# Overlay streams receiving from software

An overlay stream can be configured to receive messages from software (i.e. RISCV / Tensix). If so configured, software is effectively pushing messages onto the stream. If messages are too large to be transmitted as a single packet by the underlying transport medium, the overlay will automatically split messages up into multiple packets.

## Pushing messages using the receive buffer FIFO and message header array

To configure the phase, software should:
1. Set `SOURCE_ENDPOINT` within `STREAM_MISC_CFG_REG_INDEX` (and clear both `LOCAL_SOURCES_CONNECTED` and `REMOTE_SOURCE`).
2. Allocate some space in L1 to act as the receive buffer FIFO, and set `STREAM_BUF_START_REG_INDEX` and `STREAM_BUF_SIZE_REG_INDEX` to tell the stream about it (these are both in units of 16 bytes, so `>> 4` required to convert from byte addresses).
3. Allocate some space in L1 to act as the message header array, and write the base address to both `STREAM_MSG_INFO_PTR_REG_INDEX` and `STREAM_MSG_INFO_WR_PTR_REG_INDEX` (these are both in units of 16 bytes, so `>> 4` required to convert from byte addresses). The length of the array needs to be greater than or equal to (16 bytes times) the number of messages expected to be received during the phase.

Before pushing any messages, software should:
1. Wait until `STREAM_CURR_PHASE_REG_INDEX` contains the phase number that software is expecting.
2. Wait until `STREAM_WAIT_STATUS_REG_INDEX` reports `MSG_FWD_ONGOING` being `true`.

To push a message to the stream, software should:
1. Read `STREAM_BUF_SPACE_AVAILABLE_REG_INDEX` until it indicates that there is enough space in the message contents FIFO for the message. Note that `<< 4` is required to convert this to a number of bytes.
2. Write the entire message (including its 16 byte header) to `(STREAM_BUF_START_REG_INDEX + STREAM_WR_PTR_REG_INDEX) << 4`, wrapping around at `(STREAM_BUF_START_REG_INDEX + STREAM_BUF_SIZE_REG_INDEX) << 4` if necessary. The length of the message should be somewhere within the header. One way of avoiding wraparound is to have all messages be the same size, and have the size of the receive buffer FIFO be an integer multiple of the message size.
3. Write a copy of the message header (16 bytes) to `STREAM_MSG_INFO_WR_PTR_REG_INDEX << 4`.
4. Write to `STREAM_NUM_MSGS_RECEIVED_INC_REG_INDEX`, where the low 12 bits contain the value `1` and the remaining bits contain the length of the message (`>> 4`). Hardware uses the low 12 bits to increment `STREAM_MSG_INFO_WR_PTR_REG_INDEX` (the message header array write pointer), and the remaining bits to increment `STREAM_WR_PTR_REG_INDEX` (the receive buffer FIFO write pointer, which will wrap around if necessary). To push multiple messages at once, set the low 12 bits to the number of messages and the remaining bits to the sum of the lengths of those messages (`>> 4`).

## Pushing messages using the receive buffer FIFO, without the message header array

To configure the phase, software should:
1. Set `SOURCE_ENDPOINT` within `STREAM_MISC_CFG_REG_INDEX` (and clear both `LOCAL_SOURCES_CONNECTED` and `REMOTE_SOURCE`).
2. Allocate some space in L1 to act as the receive buffer FIFO, and set `STREAM_BUF_START_REG_INDEX` and `STREAM_BUF_SIZE_REG_INDEX` to tell the stream about it (these are both in units of 16 bytes, so `>> 4` required to convert from byte addresses).
3. Decide on an arbitrary address, and write it `>> 4` to both `STREAM_MSG_INFO_PTR_REG_INDEX` and `STREAM_MSG_INFO_WR_PTR_REG_INDEX`. Writing `0` to both is acceptable; the important part is that they contain the same value.

Before pushing any messages, software should:
1. Wait until `STREAM_CURR_PHASE_REG_INDEX` contains the phase number that software is expecting.
2. Wait until `STREAM_WAIT_STATUS_REG_INDEX` reports `MSG_FWD_ONGOING` being `true`.

To push a message, software should:
1. Read `STREAM_BUF_SPACE_AVAILABLE_REG_INDEX` until it indicates that there is enough space in the receive buffer FIFO for the message. Note that `<< 4` is required to convert this to a number of bytes.
2. Write the entire message (including its 16 byte header) to `(STREAM_BUF_START_REG_INDEX + STREAM_WR_PTR_REG_INDEX) << 4`, wrapping around at `(STREAM_BUF_START_REG_INDEX + STREAM_BUF_SIZE_REG_INDEX) << 4` if necessary. The length of the message (`>> 4`) should be somewhere within the header (if the message is transmitted over the NoC or over Ethernet, the receiving overlay will make use of this length), though it can be absent if [transmitting to a DRAM buffer](TransmitToDRAMBuffer.md) or [transmitting to nowhere](TransmitToNowhere.md).
3. Read `STREAM_MSG_INFO_CAN_PUSH_NEW_MSG_REG_INDEX` until it returns non-zero, thereby indicating that there is space in the message metadata FIFO.
4. If this is a stream for which the message metadata FIFO includes a copy of message header, and software wishes to be able to subsequently read the message header from the message metadata FIFO (e.g. because the stream is both receiving from software and transmitting to software), write a copy of the message header as four 32-bit writes to `STREAM_RECEIVER_ENDPOINT_SET_MSG_HEADER_REG_INDEX+0` through `STREAM_RECEIVER_ENDPOINT_SET_MSG_HEADER_REG_INDEX+3`.
5. Write to `STREAM_SOURCE_ENDPOINT_NEW_MSG_INFO_REG_INDEX`, where the low 17 bits contain `STREAM_BUF_START_REG_INDEX + STREAM_WR_PTR_REG_INDEX`, and the remaining bits contain the length of the message. This will cause hardware to:
    1. Increment both `STREAM_MSG_INFO_PTR_REG_INDEX` and `STREAM_MSG_INFO_WR_PTR_REG_INDEX` by one (message header array tracking). As the two registers remain equal, hardware will not use their values for anything.
    2. Increment `STREAM_WR_PTR_REG_INDEX` by the specified length (the receive buffer FIFO write pointer, which will wrap around if necessary).
    3. Append an entry to the message metadata FIFO.

## Pushing messages using neither the receive buffer FIFO nor the message header array

To configure the phase, software should:
1. Set `SOURCE_ENDPOINT` within `STREAM_MISC_CFG_REG_INDEX` (and clear both `LOCAL_SOURCES_CONNECTED` and `REMOTE_SOURCE`).
2. Set `STREAM_BUF_START_REG_INDEX` to `0` and `STREAM_BUF_SIZE_REG_INDEX` to `~0`. Other values are also acceptable, so long as all pushed messages are within the memory span that starts at `STREAM_BUF_START_REG_INDEX << 4` and continues for `STREAM_BUF_SIZE_REG_INDEX << 4` bytes.
3. Decide on an arbitrary address, and write it `>> 4` to both `STREAM_MSG_INFO_PTR_REG_INDEX` and `STREAM_MSG_INFO_WR_PTR_REG_INDEX`. Writing `0` to both is acceptable; the important part is that they contain the same value.

Before pushing any messages, software should:
1. Wait until `STREAM_CURR_PHASE_REG_INDEX` contains the phase number that software is expecting.
2. Wait until `STREAM_WAIT_STATUS_REG_INDEX` reports `MSG_FWD_ONGOING` being `true`.

To push a message:
1. Choose an address aligned to 16 bytes, and write the entire message (including its 16 byte header) there. The length of the message (`>> 4`) should be somewhere within the header (if the message is transmitted over the NoC or over Ethernet, the receiving overlay will make use of this length), though it can be absent if [transmitting to a DRAM buffer](TransmitToDRAMBuffer.md) or [transmitting to nowhere](TransmitToNowhere.md).
2. Read `STREAM_MSG_INFO_CAN_PUSH_NEW_MSG_REG_INDEX` until it returns non-zero, thereby indicating that there is space in the message metadata FIFO.
3. If this is a stream for which the message metadata FIFO includes copy of message header, and software wishes to be able to subsequently read the message header from the message metadata FIFO (e.g. because the stream is both receiving from software and transmitting to software), write a copy of the message header as four 32-bit writes to `STREAM_RECEIVER_ENDPOINT_SET_MSG_HEADER_REG_INDEX+0` through `STREAM_RECEIVER_ENDPOINT_SET_MSG_HEADER_REG_INDEX+3`.
4. Write to `STREAM_SOURCE_ENDPOINT_NEW_MSG_INFO_REG_INDEX`, where the low 17 bits contain step 1's `address >> 4`, and the remaining bits contain the length of the message. This will cause hardware to:
    1. Increment both `STREAM_MSG_INFO_PTR_REG_INDEX` and `STREAM_MSG_INFO_WR_PTR_REG_INDEX` by one (message header array tracking). As the two registers remain equal, hardware will not use their values for anything.
    2. Increment `STREAM_WR_PTR_REG_INDEX` by the specified length (the receive buffer FIFO write pointer, which will wrap around if necessary).
    3. Append an entry to the message metadata FIFO.
5. Once hardware finishes transmitting the message, it'll increment `STREAM_RD_PTR_REG_INDEX` by the specified length (the receive buffer FIFO read pointer, which will wrap around if necessary). In this setup, the read and write pointers do not affect the _location_ of the message contents, but they are still used to track the amount of in-flight data. Software can inspect either `STREAM_RD_PTR_REG_INDEX` or `STREAM_BUF_SPACE_AVAILABLE_REG_INDEX` to determine when it is safe to modify or reuse the range of memory populated by step 1.

## Register reference

### `STREAM_MSG_INFO_CAN_PUSH_NEW_MSG_REG_INDEX`

Read-only.

Returns `true` if (and only if) both of the following are true:
* The message metadata FIFO has space for at least one more entry.
* `STREAM_MSG_INFO_PTR_REG_INDEX` equals `STREAM_MSG_INFO_WR_PTR_REG_INDEX`, i.e. there are no message headers sitting in L1 which hardware needs to load into the message metadata FIFO (whenever there is space in the FIFO, hardware should promptly advance `STREAM_MSG_INFO_PTR_REG_INDEX` until the FIFO is full, though the L1 read can take a few cycles to complete).

### `STREAM_BUF_SPACE_AVAILABLE_REG_INDEX`

Read-only.

If the stream's receive buffer FIFO is empty, reading `STREAM_BUF_SPACE_AVAILABLE_REG_INDEX` returns the value of `STREAM_BUF_SIZE_REG_INDEX`. Otherwise it returns `STREAM_RD_PTR_REG_INDEX` minus `STREAM_WR_PTR_REG_INDEX` modulo `STREAM_BUF_SIZE_REG_INDEX`.
