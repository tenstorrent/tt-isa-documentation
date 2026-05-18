# Loading stream configuration from L1

Software can configure a stream to load configuration from L1. The loaded configuration can also include a pointer to the next phase's configuration, allowing a stream to autonomously proceed through an arbitrary number of phases (although unless the configuration pointers form a loop, L1 capacity will eventually impose a limit).

If a stream is idle (or partially configured), software can cause the stream to load configuration from L1 by:
1. Writing `(N - 1) << 24` to `STREAM_PHASE_AUTO_CFG_HEADER_REG_INDEX`, where `N * 4` is the size of the configuration blob (in bytes) in L1.
2. Writing the address (in bytes) of the configuration blob to `STREAM_PHASE_AUTO_CFG_PTR_REG_INDEX` (or writing a base address to `STREAM_PHASE_AUTO_CFG_PTR_BASE_REG_INDEX`, and then a relative index to `STREAM_PHASE_AUTO_CFG_PTR_REG_INDEX`, such that `STREAM_PHASE_AUTO_CFG_PTR_BASE_REG_INDEX + STREAM_PHASE_AUTO_CFG_PTR_REG_INDEX` gives the address in bytes).
3. Setting the `PHASE_AUTO_CONFIG` field within `STREAM_MISC_CFG_REG_INDEX` to `true`.

The format of the configuration blob in L1 is:
1. The first four bytes are a new value to write to `STREAM_PHASE_AUTO_CFG_HEADER_REG_INDEX`.
2. Every subsequent four bytes contains a register index in the high 8 bits, and a corresponding value to write (to that register index) in the low 24 bits.

After loading configuration from L1, if the `PHASE_AUTO_ADVANCE` field within `STREAM_MISC_CFG_REG_INDEX` is set, then the stream will start automatically. Otherwise it'll wait for software to write to `STREAM_PHASE_ADVANCE_REG_INDEX`.

At the end of a phase (at "Has pointer to configuration for next phase?" on the [state machine diagram](README.md#stream-state-machine)), if the `PHASE_AUTO_CONFIG` field within `STREAM_MISC_CFG_REG_INDEX` is set, then the stream will load configuration for the next phase from L1.

## Register reference

### `STREAM_PHASE_AUTO_CFG_HEADER_REG_INDEX`

<table><thead><tr><th align="right">First&nbsp;bit</th><th align="right">#&nbsp;Bits</th><th>Name</th><th>Write behavior</th><th>Read behavior</th></tr></thead>
<tr><td align="right">0</td><td align="right">12</td><td><code>PHASE_NUM_INCR</code></td><td><code>STREAM_CURR_PHASE_REG_INDEX += new_val</code></td><td><code>return NumMessagesRemainingInPhase</code></td></tr>
<tr><td align="right">12</td><td align="right">12</td><td><code>CURR_PHASE_NUM_MSGS</code></td><td><code>NumMessagesRemainingInPhase = new_val</code></td><td><code>return NumMessagesRemainingInPhase</code></td></tr>
<tr><td align="right">24</td><td align="right">8</td><td><code>NEXT_PHASE_NUM_CFG_REG_WRITES</code></td><td><pre><code>if (STREAM_MISC_CFG_REG_INDEX.PHASE_AUTO_CONFIG) {
  STREAM_PHASE_AUTO_CFG_PTR_REG_INDEX += (NextConfigSize + 1) * 4;
}
NextConfigSize = new_val</code></pre></td><td><code>return NextConfigSize</code></td></tr></table>

Note that `NumMessagesRemainingInPhase` is decremented as a phase progresses. If transmitting to software, when software writes to `STREAM_MSG_INFO_CLEAR_REG_INDEX`, `NumMessagesRemainingInPhase` is decremented by the written value.

### `STREAM_BLOB_AUTO_CFG_DONE_REG_INDEX`

`STREAM_BLOB_AUTO_CFG_DONE_REG_INDEX` and `STREAM_BLOB_AUTO_CFG_DONE_REG_INDEX+1` contain a 64-bit bitmask, with one bit per stream. Reading from these registers will return the bitmask. Writing to them will clear the specified bits (i.e. writes do `Bitmask &= ~new_val` rather than `Bitmask = new_val`).

When a stream takes the "No" edge out of "Has pointer to configuration for next phase?" on the [state machine diagram](README.md#stream-state-machine), hardware will set the bit within the bitmask corresponding to the stream. Hardware will clear the bit if the stream subsequently takes the edge from "Software sets configuration" to "Load configuration for phase from L1".

This pair of registers exists once per NoC Overlay. For the purpose of `STREAM_REG_ADDR`, they're part of stream ID 0, but they relate to all streams.

### `STREAM_BLOB_NEXT_AUTO_CFG_DONE_REG_INDEX`

If any bits within `STREAM_BLOB_AUTO_CFG_DONE_REG_INDEX` / `STREAM_BLOB_AUTO_CFG_DONE_REG_INDEX+1` are set, then reading from `STREAM_BLOB_NEXT_AUTO_CFG_DONE_REG_INDEX` will choose one bit (in a fair manner), clear it, and return its index plus `0x10000`. If all bits within `STREAM_BLOB_AUTO_CFG_DONE_REG_INDEX` / `STREAM_BLOB_AUTO_CFG_DONE_REG_INDEX+1` are clear, reading from `STREAM_BLOB_NEXT_AUTO_CFG_DONE_REG_INDEX` will do nothing and return zero.

This register exists once per NoC Overlay. For the purpose of `STREAM_REG_ADDR`, it's part of stream ID 0, but it relates to all streams.
