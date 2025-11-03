# NIU Counters

Each NIU contains an array of counters, which software can use to monitor the status of requests that it has issued. They are presented as an array of 32-bit values, [starting at address `NIU_BASE + 0x200`](MemoryMap.md):

|Index|Name|Counter width|
|--:|---|---|
|0|`NIU_MST_ATOMIC_RESP_RECEIVED`|32 bits (will eventually wrap around)|
|1|`NIU_MST_WR_ACK_RECEIVED`|32 bits (will eventually wrap around)|
|2|`NIU_MST_RD_RESP_RECEIVED`|32 bits (will eventually wrap around)|
|3|`NIU_MST_RD_DATA_WORD_RECEIVED`|32 bits (will eventually wrap around)|
|4|`NIU_MST_CMD_ACCEPTED`|32 bits (will eventually wrap around)|
|5|`NIU_MST_RD_REQ_SENT`|32 bits (will eventually wrap around)|
|6|`NIU_MST_NONPOSTED_ATOMIC_SENT`|32 bits (will eventually wrap around)|
|7|`NIU_MST_POSTED_ATOMIC_SENT`|32 bits (will eventually wrap around)|
|8|`NIU_MST_NONPOSTED_WR_DATA_WORD_SENT`|32 bits (will eventually wrap around)|
|9|`NIU_MST_POSTED_WR_DATA_WORD_SENT`|32 bits (will eventually wrap around)|
|10|`NIU_MST_NONPOSTED_WR_REQ_SENT`|32 bits (will eventually wrap around)|
|11|`NIU_MST_POSTED_WR_REQ_SENT`|32 bits (will eventually wrap around)|
|12|`NIU_MST_NONPOSTED_WR_REQ_STARTED`|32 bits (will eventually wrap around)|
|13|`NIU_MST_POSTED_WR_REQ_STARTED`|32 bits (will eventually wrap around)|
|14|`NIU_MST_RD_REQ_STARTED`|32 bits (will eventually wrap around)|
|15|`NIU_MST_NONPOSTED_ATOMIC_STARTED`|32 bits (will eventually wrap around)|
|16<br/>to&nbsp;31|`NIU_MST_REQS_OUTSTANDING_ID(i)`<br/>For `0 ≤ i ≤ 15`|8 bits each (gets both incremented and decremented, so will only overflow or underflow if software has too many outstanding requests)|
|32<br/>to&nbsp;47|`NIU_MST_WRITE_REQS_OUTGOING_ID(i)`<br/>For `0 ≤ i ≤ 15`|8 bits each (gets both incremented and decremented, so will only overflow or underflow if software has too many outstanding requests)|
|48|`NIU_SLV_ATOMIC_RESP_SENT`|32 bits (will eventually wrap around)|
|49|`NIU_SLV_WR_ACK_SENT`|32 bits (will eventually wrap around)|
|50|`NIU_SLV_RD_RESP_SENT`|32 bits (will eventually wrap around)|
|51|`NIU_SLV_RD_DATA_WORD_SENT`|32 bits (will eventually wrap around)|
|52|`NIU_SLV_REQ_ACCEPTED`|32 bits (will eventually wrap around)|
|53|`NIU_SLV_RD_REQ_RECEIVED`|32 bits (will eventually wrap around)|
|54|`NIU_SLV_NONPOSTED_ATOMIC_RECEIVED`|32 bits (will eventually wrap around)|
|55|`NIU_SLV_POSTED_ATOMIC_RECEIVED`|32 bits (will eventually wrap around)|
|56|`NIU_SLV_NONPOSTED_WR_DATA_WORD_RECEIVED`|32 bits (will eventually wrap around)|
|57|`NIU_SLV_POSTED_WR_DATA_WORD_RECEIVED`|32 bits (will eventually wrap around)|
|58|`NIU_SLV_NONPOSTED_WR_REQ_RECEIVED`|32 bits (will eventually wrap around)|
|59|`NIU_SLV_POSTED_WR_REQ_RECEIVED`|32 bits (will eventually wrap around)|
|60|`NIU_SLV_NONPOSTED_WR_REQ_STARTED`|32 bits (will eventually wrap around)|
|61|`NIU_SLV_POSTED_WR_REQ_STARTED`|32 bits (will eventually wrap around)|

Various counters are incremented (or occasionally decremented) at various points in the lifetime of a NoC request, with this varying based on the type of request. See below sections for details.

> [!WARNING]
> If software initiates an NIU request [by writing to `NOC_CMD_CTRL`](MemoryMap.md#noc_cmd_ctrl) and then immediately reads from an NIU counter, [RISCV memory ordering](../TensixTile/BabyRISCV/MemoryOrdering.md) rules should be consulted to ensure that the read and the write are not reordered. To ensure correct ordering in this particular scenario, it suffices to read back from `NOC_CMD_CTRL` before performing the first counter read.

## Atomic requests

At the initiating NIU, as software writes to `NOC_CMD_CTRL`:
* If `NOC_CMD_RESP_MARKED` is set, increment `NIU_MST_REQS_OUTSTANDING_ID(NOC_PACKET_TRANSACTION_ID)`.

At the initiating NIU, as the virtual channel number for the first hop from the NIU to the router is assigned:
* Increment `NIU_MST_CMD_ACCEPTED`.
* If `NOC_CMD_RESP_MARKED` is set, increment `NIU_MST_NONPOSTED_ATOMIC_STARTED`.
* Revert the relevant `NOC_CMD_CTRL` back to `0`.

At the initiating NIU, as the atomic request packet leaves the NIU:
* If `NOC_CMD_RESP_MARKED` is set, increment `NIU_MST_NONPOSTED_ATOMIC_SENT`. Otherwise increment `NIU_MST_POSTED_ATOMIC_SENT`.

At each `NOC_TARG_ADDR` NIU, as the request arrives at the NIU:
* Increment `NIU_SLV_REQ_ACCEPTED`.
* If `NOC_CMD_RESP_MARKED` is set, increment `NIU_SLV_NONPOSTED_ATOMIC_RECEIVED`. Otherwise increment `NIU_SLV_POSTED_ATOMIC_RECEIVED`.

**Remainder only if `NOC_CMD_RESP_MARKED` is set:**

At each `NOC_TARG_ADDR` NIU, as L1 completes the atomic operation:
* Increment `NIU_SLV_ATOMIC_RESP_SENT`.

At the `NOC_RET_ADDR` NIU, for each response packet, after the write to L1 has completed:
* Increment `NIU_MST_ATOMIC_RESP_RECEIVED`.
* Decrement `NIU_MST_REQS_OUTSTANDING_ID(NOC_PACKET_TRANSACTION_ID)`.

## Read requests

At the initiating NIU, as software writes to `NOC_CMD_CTRL`:
* Increment `NIU_MST_REQS_OUTSTANDING_ID(NOC_PACKET_TRANSACTION_ID)` by `max(1, ceil(NOC_AT_LEN_BE / 8192.))`.

At the initiating NIU, as the virtual channel number for the first hop from the NIU to the router is assigned:
* Increment `NIU_MST_CMD_ACCEPTED`.
* Increment `NIU_MST_RD_REQ_STARTED`.
* Revert the relevant `NOC_CMD_CTRL` back to `0` (or, if `NOC_AT_LEN_BE > 8192`, leave `NOC_CMD_CTRL` as `1` but decrement `NOC_AT_LEN_BE` by 8192 and increment both of `NOC_TARG_ADDR_LO` and `NOC_RET_ADDR_LO` by 8192 - see [automatic request splitting](#automatic-request-splitting)).

At the initiating NIU, as the read request packet leaves the NIU:
* Increment `NIU_MST_RD_REQ_SENT`.

At the `NOC_TARG_ADDR` NIU, as each read request arrives at the NIU:
* Increment `NIU_SLV_REQ_ACCEPTED`.
* Increment `NIU_SLV_RD_REQ_RECEIVED`.

At the `NOC_TARG_ADDR` NIU, after the data reads from L1 or register space are complete:
* Increment `NIU_SLV_RD_RESP_SENT`.
* Increment `NIU_SLV_RD_DATA_WORD_SENT` by the number of data flits.

At the `NOC_RET_ADDR` NIU, after the data writes to L1 or register space are complete:
* Increment `NIU_MST_RD_RESP_RECEIVED`.
* Increment `NIU_MST_RD_DATA_WORD_RECEIVED` by the number of data flits.
* Decrement `NIU_MST_REQS_OUTSTANDING_ID(NOC_PACKET_TRANSACTION_ID)`.

## Write requests with `NOC_CMD_WR_INLINE=true`

At the initiating NIU, as software writes to `NOC_CMD_CTRL`:
* If `NOC_CMD_RESP_MARKED` is set, increment `NIU_MST_REQS_OUTSTANDING_ID(NOC_PACKET_TRANSACTION_ID)`.

At the initiating NIU, as the virtual channel number for the first hop from the NIU to the router is assigned:
* Increment `NIU_MST_CMD_ACCEPTED`.
* If `NOC_CMD_RESP_MARKED` is set, increment `NIU_MST_NONPOSTED_WR_REQ_STARTED` and `NIU_MST_NONPOSTED_WR_REQ_SENT`. Otherwise increment `NIU_MST_POSTED_WR_REQ_STARTED` and `NIU_MST_POSTED_WR_REQ_SENT`.
* Revert the relevant `NOC_CMD_CTRL` back to `0`.

At each `NOC_TARG_ADDR` NIU, as the request arrives at the NIU:
* If `NOC_CMD_RESP_MARKED` is set, increment `NIU_SLV_NONPOSTED_WR_REQ_STARTED` and `NIU_SLV_NONPOSTED_WR_REQ_RECEIVED` and `NIU_SLV_NONPOSTED_WR_DATA_WORD_RECEIVED`. Otherwise increment `NIU_SLV_POSTED_WR_REQ_STARTED` and `NIU_SLV_POSTED_WR_REQ_RECEIVED` and `NIU_SLV_POSTED_WR_DATA_WORD_RECEIVED`.

**Remainder only if `NOC_CMD_RESP_MARKED` is set:**

At each `NOC_TARG_ADDR` NIU, after the data writes to L1 or register space are complete:
* Increment `NIU_SLV_WR_ACK_SENT`.

At the initiating NIU, for each received write acknowledgement, as the packet arrives at the NIU:
* Increment `NIU_MST_WR_ACK_RECEIVED`.
* Decrement `NIU_MST_REQS_OUTSTANDING_ID(NOC_PACKET_TRANSACTION_ID)`.

## Write requests with `NOC_CMD_WR_INLINE=false`

At the initiating NIU, as software writes to `NOC_CMD_CTRL`:
* If `NOC_CMD_RESP_MARKED` is set, increment `NIU_MST_REQS_OUTSTANDING_ID(NOC_PACKET_TRANSACTION_ID)` by `NOC_CMD_WR_BE ? 1 : max(1, ceil(NOC_AT_LEN_BE / 8192.))`.
* Increment `NIU_MST_WRITE_REQS_OUTGOING_ID(NOC_PACKET_TRANSACTION_ID)` by `NOC_CMD_WR_BE ? 1 : max(1, ceil(NOC_AT_LEN_BE / 8192.))`.

At the initiating NIU, as the virtual channel number for the first hop from the NIU to the router is assigned:
* Increment `NIU_MST_CMD_ACCEPTED`.
* If `NOC_CMD_RESP_MARKED` is set, increment `NIU_MST_NONPOSTED_WR_REQ_STARTED`. Otherwise increment `NIU_MST_POSTED_WR_REQ_STARTED`.
* Revert the relevant `NOC_CMD_CTRL` back to `0` (or, if `!NOC_CMD_WR_BE && NOC_AT_LEN_BE > 8192`, leave `NOC_CMD_CTRL` as `1` but decrement `NOC_AT_LEN_BE` by 8192 and increment both of `NOC_TARG_ADDR_LO` and `NOC_RET_ADDR_LO` by 8192 - see [automatic request splitting](#automatic-request-splitting)).

At the initiating NIU, before the data reads from L1 or register space are complete:
* If `NOC_CMD_RESP_MARKED` is set, increment `NIU_MST_NONPOSTED_WR_REQ_SENT` by one and `NIU_MST_NONPOSTED_WR_DATA_WORD_SENT` by the number of data flits. Otherwise increment `NIU_MST_POSTED_WR_REQ_SENT` by one and `NIU_MST_POSTED_WR_DATA_WORD_SENT` by the number of data flits.

At the initiating NIU, after the data reads from L1 or register space are complete:
* Decrement `NIU_MST_WRITE_REQS_OUTGOING_ID(NOC_PACKET_TRANSACTION_ID)` by one.

At each `NOC_RET_ADDR` NIU, as the request arrives at the NIU:
* If `NOC_CMD_RESP_MARKED` is set, increment `NIU_SLV_NONPOSTED_WR_REQ_STARTED`. Otherwise increment `NIU_SLV_POSTED_WR_REQ_STARTED`.

At each `NOC_RET_ADDR` NIU, as each data flit arrives at the NIU:
* If `NOC_CMD_RESP_MARKED` is set, increment `NIU_SLV_NONPOSTED_WR_DATA_WORD_RECEIVED`. Otherwise increment `NIU_SLV_POSTED_WR_DATA_WORD_RECEIVED`.
* For the last data flit: If `NOC_CMD_RESP_MARKED` is set, increment `NIU_SLV_NONPOSTED_WR_REQ_RECEIVED`. Otherwise increment `NIU_SLV_POSTED_WR_REQ_RECEIVED`.

**Remainder only if `NOC_CMD_RESP_MARKED` is set:**

At each `NOC_RET_ADDR` NIU, after the data writes to L1 or register space are complete:
* Increment `NIU_SLV_WR_ACK_SENT`.

At `NOC_TARG_ADDR` NIU, for each received write acknowledgement, as the packet arrives at the NIU:
* Increment `NIU_MST_WR_ACK_RECEIVED`.
* Decrement `NIU_MST_REQS_OUTSTANDING_ID(NOC_PACKET_TRANSACTION_ID)`.

## Clear NIU transaction ID counters

If software writes the value `new_val` to `NIU_BASE + 0x050`, then the following happens:
```c
for (unsigned i = 0; i < 16; ++i) {
  if (new_val.Bit[i]) {
    NIU_MST_REQS_OUTSTANDING_ID(i) = 0;
  }
}
```

There are a few reasons why software might wish to clear counters in this manner:
1. It is performing a NoC transaction where the read response or write acknowledgement is sent to an NIU other than the originating NIU, as this will cause counter increments at the originating NIU, but counter decrements at the other NIU, leaving both NIUs with non-zero counters.
2. It is performing a NoC transaction with both `NOC_CMD_BRCST_PACKET` and `NOC_CMD_RESP_MARKED` set, as this will cause one counter increment when the request is initiated, but a counter decrement for _every_ response received, likely leaving the counter non-zero.

## Automatic request splitting

Each individual NoC packet can contain up to 256 data flits, and as each flit consists of 256 bits (32 bytes), this means that the maximum packet payload is 8192 bytes. If software wishes to transfer more than 8192 bytes, then the transfer needs to be split into multiple packets. Software can either do this itself, or rely on hardware to do it. If relying on hardware to do it:
* `NOC_AT_LEN_BE` should be set to the total length in bytes.
* Both of `NOC_TARG_ADDR_LO` and `NOC_RET_ADDR_LO` need to be aligned to 32 byte boundaries.
* After writing `1` to `NOC_CMD_CTRL` of the relevant request initiator, software must not write to `NOC_CMD_CTRL` of _any_ request initiator (at the same NIU) until `NOC_CMD_CTRL` of the relevant request initiator reverts back to `0`.
* Counters are incremented and decremented as they normally would be for a sequence of individual requests, except that the initial increments of `NIU_MST_REQS_OUTSTANDING_ID` and `NIU_MST_WRITE_REQS_OUTGOING_ID` (if applicable) are done all at once rather than one at a time. If software is relying on these counters, it needs to be aware that these counters are only 8 bits wide, so a large increment could cause overflow. In practice, this limits the maximum total length to just under 2 MiB.
