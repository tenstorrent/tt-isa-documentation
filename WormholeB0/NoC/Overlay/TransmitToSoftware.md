# Overlay streams transmitting to software

An overlay stream can be configured to transmit messages to software (i.e. RISCV / Tensix). If so configured, software is effectively pulling messages from the stream. If messages are too large to be transmitted as a single packet by the underlying transport medium, the overlay will automatically split messages up into multiple packets. In such cases, software will only be informed of arriving messages once all of their packets have arrived.

To configure the phase, software should:
1. Set `RECEIVER_ENDPOINT` within `STREAM_MISC_CFG_REG_INDEX` (and clear both `LOCAL_RECEIVER` and `REMOTE_RECEIVER`).
2. Set `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_REG_INDEX` to `0`, and if the stream is capable of transmitting to a DRAM buffer, also set `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_HI_REG_INDEX` to `0` (if the stream is not capable of this, then writes to `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_HI_REG_INDEX` are ignored, so software is free to write it regardless of the stream type, if it so wishes).

Before pulling any messages, software should:
1. Wait until `STREAM_CURR_PHASE_REG_INDEX` contains the phase number that software is expecting.
2. Wait until `STREAM_WAIT_STATUS_REG_INDEX` reports `MSG_FWD_ONGOING` being `true`.

To pull a message from the stream, software should:
1. Read from `STREAM_NUM_MSGS_RECEIVED_REG_INDEX` until it is non-zero. This returns the current size of the message metadata FIFO.
2. Obtain the start pointer and length of the message at the front of the message metadata FIFO: `STREAM_NEXT_RECEIVED_MSG_ADDR_REG_INDEX << 4` will be its start pointer, and `STREAM_NEXT_RECEIVED_MSG_SIZE_REG_INDEX << 4` will be its length.
3. Write the value `1` to `STREAM_MSG_INFO_CLEAR_REG_INDEX`. This will cause hardware to:
    1. Pop one entry from the message metadata FIFO. This will create space in the message metadata FIFO, which hardware will refill as appropriate.
    2. Push an entry onto the L1 read complete FIFO containing the length of the popped message.
4. Consume the span of memory obtained at step 2. Note that the data might wrap around at `(STREAM_BUF_START_REG_INDEX + STREAM_BUF_SIZE_REG_INDEX) << 4` back to `STREAM_BUF_START_REG_INDEX << 4`. One way of avoiding wraparound is to have all messages be the same size, and have the size of the receive buffer FIFO be an integer multiple of the message size. If the stream is receiving in gather mode, `STREAM_BUF_START_REG_INDEX` and `STREAM_BUF_SIZE_REG_INDEX` can vary from message to message.
5. Once the data has been consumed, write any value to `STREAM_MSG_DATA_CLEAR_REG_INDEX`. This will cause hardware to pop one entry from the L1 read complete FIFO (hopefully corresponding to step 3.2), and increment `STREAM_RD_PTR_REG_INDEX` by the popped length. This is the receive buffer FIFO read pointer, which will wrap around if necessary. This will create space in the receive buffer FIFO, which will be refilled as appropriate.

At step 2, software can instead choose to peek at the entire contents of the message metadata FIFO. If this is a stream for which the message metadata FIFO includes a copy of message header (see [stream capabilities](README.md#stream-capabilities)), then the entries of the message metadata FIFO can be found at `STREAM_RECEIVER_ENDPOINT_MSG_INFO_REG_INDEX + i*6 + j` for `0 ≤ i < STREAM_NUM_MSGS_RECEIVED_REG_INDEX` and `0 ≤ j < 6`. `i == 0` is the front of the FIFO, and subsequent `i` is looking further into the FIFO. `j == 0` is the message start pointer (which will need `<< 4` to give it in bytes), `j == 1` is the message length (which will also need `<< 4` to give it in bytes), `j == 2` is the first 32 bits of the message header, and subsequent `j` are the remaining chunks of the message header. If this is not a stream for which the message metadata FIFO includes a copy of message header, then the entries of the message metadata FIFO can be found at `STREAM_RECEIVER_ENDPOINT_MSG_INFO_REG_INDEX + i*2 + j` for `0 ≤ i < STREAM_NUM_MSGS_RECEIVED_REG_INDEX` and `0 ≤ j < 2`, with the same meaning of `i` and `j` as previously. In either case, `STREAM_RECEIVER_ENDPOINT_MSG_INFO_REG_INDEX + 0` is identical to `STREAM_NEXT_RECEIVED_MSG_ADDR_REG_INDEX` and `STREAM_RECEIVER_ENDPOINT_MSG_INFO_REG_INDEX + 1` is identical to `STREAM_NEXT_RECEIVED_MSG_SIZE_REG_INDEX`. When `STREAM_NUM_MSGS_RECEIVED_REG_INDEX < i < 16`, the returned values will be zero. When `i == STREAM_NUM_MSGS_RECEIVED_REG_INDEX`, the returned values are undefined.

At step 3, it is also possible to write other values to `STREAM_MSG_INFO_CLEAR_REG_INDEX`: the valid values are `0` or `1` or `2` or the stream's message metadata FIFO group size. At step 3.1, hardware will pop the specified number of messages from the message metadata FIFO, and at step 3.2 hardware will push a single entry onto the L1 read complete FIFO containing the sum of the lengths of the popped messages (so regardless of the value written to `STREAM_MSG_INFO_CLEAR_REG_INDEX` at step 3, just a single write to `STREAM_MSG_DATA_CLEAR_REG_INDEX` is required at step 5).

If software is consuming multiple messages in parallel, it is allowed to perform steps 1-4 multiple times before performing step 5, provided that:
* It performs steps 1-4 and step 5 an equal number of times.
* It ensures that the L1 read complete FIFO does not overflow. The capacity of this FIFO differs between streams; see [stream capabilities](README.md#stream-capabilities). If software needs to check whether this FIFO is full, it can consult the low bit of `STREAM_DEBUG_STATUS_REG_INDEX+2`, which will contain `false` if the FIFO is full and `true` otherwise.

To pop messages from the message metadata FIFO and the message contents FIFO at the same time, software can write `-2*N` to `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_REG_INDEX`, which will (eventually) pop `N` messages from both FIFOs. When transmitting to software (and `MSG_FWD_ONGOING` is `true`), the hardware behavior around `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_REG_INDEX` is:
* If `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_REG_INDEX` contains a non-zero even value, wait until the message metadata FIFO is non-empty and the L1 read complete FIFO is not full, and then:
  1. Write `1` to `STREAM_MSG_INFO_CLEAR_REG_INDEX` (i.e. pop one entry from the message metadata FIFO and move its length to the L1 read complete FIFO).
  2. Increment `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_REG_INDEX` by one (this takes a clock cycle).
* If `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_REG_INDEX` contains a non-zero odd value:
  1. Write `1` to `STREAM_MSG_DATA_CLEAR_REG_INDEX` (i.e. pop one entry from the L1 read complete FIFO and increment the message contents FIFO read pointer by the popped length).
  2. Increment `STREAM_REMOTE_DEST_MSG_INFO_WR_PTR_REG_INDEX` by one (this takes a clock cycle).

## Register reference

### `STREAM_MSG_GROUP_COMPRESS_REG_INDEX`

Read-only.

If this is a stream for which the message metadata FIFO includes a copy of message header, the read behavior for `STREAM_MSG_GROUP_COMPRESS_REG_INDEX` is:
```c
uint32_t result = 0;
for (unsigned i = 0; i < 4; ++i) {
  result.Bit[i] = read(STREAM_RECEIVER_ENDPOINT_MSG_INFO_REG_INDEX + i * 6 + 3).Bit[20];
}
return result;
```

If this is not a stream for which the message metadata FIFO includes a copy of message header, reads return `0`.

### `STREAM_MSG_GROUP_ZERO_MASK_AND_INDEX`

Read-only.

If this is a stream for which the message metadata FIFO includes a copy of message header, the read behavior for `STREAM_MSG_GROUP_ZERO_MASK_AND_INDEX` is:
```c
uint32_t result = ~(uint32_t)0;
for (unsigned i = 0; i < 4; ++i) {
  result &= read(STREAM_RECEIVER_ENDPOINT_MSG_INFO_REG_INDEX + i * 6 + 4);
}
return result;
```

If this is not a stream for which the message metadata FIFO includes a copy of message header, reads return `0`.
