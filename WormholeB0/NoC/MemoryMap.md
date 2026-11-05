# NIU Memory Map

Each NIU ([NoC](README.md) interface unit) has an assortment of command and configuration and status registers mapped into the address space of the containing tile. Each tile will contain two NIUs; NIU #0 will be connected to a NoC #0 router, and NIU #1 will be connected to a NoC #1 router. The two NIUs are identical, other than which NoC they're part of and where in the address space they are presented. The base address for where they are presented (`NIU_BASE`) is:

|Tile type|`NIU_BASE` for NoC #0|`NIU_BASE` for NoC #1|
|---|---|---|
|Tensix or Ethernet|`0x0_FFB2_0000` or `0x?_FFB2_0000`|`0x0_FFB3_0000` or `0x?_FFB3_0000`|
|Other, when accessed through NoC #0|`0xF_FFB2_0000` or `0xF_????_?000`|Cannot access
|Other, when accessed through NoC #1|Cannot access|`0xF_FFB3_0000` or `0xF_????_?000`|

The high-level contents at this address are:

|Address range start|Example address range|Contents|Software access|
|---|---|---|---|
|`NIU_BASE + 0x000`|`0xFFB2_0000` to `0xFFB2_002B`|[NIU request initiator](#niu-request-initiators) #0|Read / write|
|`NIU_BASE + 0x02C`|`0xFFB2_002C` to `0xFFB2_0033`|[NIU identification details](#niu-identification-details)|Read only|
|`NIU_BASE + 0x050`|`0xFFB2_0050` to `0xFFB2_0053`|[Clear NIU transaction ID counters](Counters.md#clear-niu-transaction-id-counters)|Write only|
|`NIU_BASE + 0x054`|`0xFFB2_0054` to `0xFFB2_0057`|[NIU combined request initiator status](#niu-combined-request-initiator-status)|Read only|
|`NIU_BASE + 0x100`|`0xFFB2_0100` to `0xFFB2_013B`|[NIU and NoC router configuration](#niu-and-noc-router-configuration)|Read / write|
|`NIU_BASE + 0x200`|`0xFFB2_0200` to `0xFFB2_02FF`|[NIU counters](Counters.md)|Read only|
|`NIU_BASE + 0x300`|`0xFFB2_0300` to `0xFFB2_037F`|NoC router debug information|Read only|
|`NIU_BASE + 0x380`|`0xFFB2_0380` to `0xFFB2_03FF`|NIU debug information|Read only|
|`NIU_BASE + 0x400`|`0xFFB2_0400` to `0xFFB2_042B`|[NIU request initiator](#niu-request-initiators) #1|Read / write|
|`NIU_BASE + 0x42C`|`0xFFB2_042C` to `0xFFB2_0433`|[NIU identification details](#niu-identification-details) (again)|Read only|
|`NIU_BASE + 0x800`|`0xFFB2_0800` to `0xFFB2_082B`|[NIU request initiator](#niu-request-initiators) #2|Read / write|
|`NIU_BASE + 0x82C`|`0xFFB2_082C` to `0xFFB2_0833`|[NIU identification details](#niu-identification-details) (again)|Read only|
|`NIU_BASE + 0xC00`|`0xFFB2_0C00` to `0xFFB2_0C2B`|[NIU request initiator](#niu-request-initiators) #3|Read / write|
|`NIU_BASE + 0xC2C`|`0xFFB2_0C2C` to `0xFFB2_0C33`|[NIU identification details](#niu-identification-details) (again)|Read only|

## NIU Request Initiators

Each NIU has four request initiators, starting at addresses `NIU_BASE + i * NOC_CMD_BUF_OFFSET` (`0 ≤ i ≤ 3`). The four initiators are functionally identical, so software is free to use any initiator for any purpose, though it can avoid the need to repeatedly reprogram certain registers by statically assigning particular purposes to particular initiators.

|Name|Example Address|Contents|
|---|---|---|
|[`NOC_TARG_ADDR_LO`](#noc_targ_addr-and-noc_ret_addr)|`0xFFB2_0000`|Low 32 bits of "target" memory address|
|[`NOC_TARG_ADDR_MID`](#noc_targ_addr-and-noc_ret_addr)|`0xFFB2_0004`|High 4 bits of "target" memory address and "target" [X/Y coordinates](Coordinates.md)|
|[`NOC_RET_ADDR_LO`](#noc_targ_addr-and-noc_ret_addr)|`0xFFB2_000C`|Low 32 bits of "return" memory address|
|[`NOC_RET_ADDR_MID`](#noc_targ_addr-and-noc_ret_addr)|`0xFFB2_0010`|High 4 bits of "return" memory address and "return" [X/Y coordinates](Coordinates.md)|
|[`NOC_PACKET_TAG`](#noc_packet_tag)|`0xFFB2_0018`|Transaction ID (4 bits) and uncommonly set request flags|
|[`NOC_CTRL`](#noc_ctrl)|`0xFFB2_001C`|Request type (2 bits) and commonly set request flags|
|[`NOC_AT_LEN_BE`](#noc_at_len_be)|`0xFFB2_0020`|Depending on the request type, either contains [the atomic opcode and operands](Atomics.md), or the length (in bytes) of a read or write, or a byte-enable mask for short writes|
|`NOC_AT_DATA`|`0xFFB2_0024`|For inline writes, and most types of atomics, contains the 32 bits of immediate data|
|[`NOC_CMD_CTRL`](#noc_cmd_ctrl)|`0xFFB2_0028`|Writing `1` to the low bit indicates that software wishes to initiate a request using the fields of this initiator; hardware will transition the bit back to `0` once the request has been initiated|

> [!WARNING]
> Software can only use the NIU request initiators in Tensix tiles and Ethernet tiles. Host software can also cause the PCI Express tile to send NoC requests, but the mechanism for doing so is different to the mechanism described here. Software can cause NoC requests to be sent _to_ other types of tile, and receive responses _from_ those tiles, but it cannot initiate NoC requests _at_ those tiles.

### `NOC_CTRL`

This field contains the request type and some commonly set request flags:

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|2|Request type|`NOC_CMD_RD` (`0`) for read requests<br/>`NOC_CMD_AT` (`1`) for atomic requests<br/>`NOC_CMD_WR` (`2`) for write requests<br/>The value `3` is reserved and should not be used<br/><br/>:warning: `NOC_CMD_AT` requires that the request be destined for the L1 of a Tensix tile or Ethernet tile|
|2|1|`NOC_CMD_WR_BE`|For write requests, `true` if `NOC_AT_LEN_BE` contains a byte-enable mask (and hence the write is at most 32 bytes), or `false` if `NOC_AT_LEN_BE` contains a length (and hence the write is between 1 and 8192 bytes); ignored for other types of request|
|3|1|`NOC_CMD_WR_INLINE`|For write requests, `true` if `NOC_AT_DATA` contains the data to be written, `false` otherwise (in which case `NOC_TARG_ADDR` contains the address of the data in the initiator's address space); ignored for other types of request<br/><br/>:warning: `NOC_CMD_WR_INLINE` requires that the request be destined for a Tensix tile or an Ethernet tile|
|4|1|`NOC_CMD_RESP_MARKED`|For write requests and atomic requests, `false` if the request is posted (i.e. a response / acknowledgement will not be sent), `true` otherwise (i.e. a response / acknowledgement is desired); ignored for read requests (they always generate a response)|
|5|1|`NOC_CMD_BRCST_PACKET`|`false` if the request is unicast, `true` if the request is broadcast; should always be `false` for read requests|
|6|1|`NOC_CMD_VC_LINKED`|`false` if the request is the sole request in a transaction or the final request in a multi-request transaction; `true` if the request is part of a multi-request transaction but is not the final request in the transaction. If this flag is used, then: <ul><li>The next request issued by the NIU will be part of the same transaction as the request with `NOC_CMD_VC_LINKED` set on it.</li><li>All requests in the transaction must be to the same destination tile, or for broadcast, to the same destination rectangle (and using the same value of `NOC_CMD_BRCST_XY`). Failure to comply with this requirement will lead to complete NoC failure.</li><li>The NIU will be unable to initiate requests on any virtual channel number other than the one used for the transaction. Attempting to initiate a request with an incompatible virtual channel number will cause virtual channel number assignment to continuously fail, leaving the NIU unable to initiate any requests.</li><li>All NoC routers along the path (or, for broadcast, the tree) taken by the request will not allow the chosen virtual channel numbers to be used by any other transactions until the last request in the transaction has finished passing through them.</li><li>The NoC Overlay in the tile will be unable to initiate any requests until the last request in the transaction has been initiated. The converse is true when the NoC Overlay is in the middle of a multi-request transaction: the regular NIU request initiators will be unable to initiate any requests.</li></ul>Given all this, if software initiates a request with `NOC_CMD_VC_LINKED` set to `true`, it is responsible for promptly completing the transaction by initiating a request with it set to `false`.|
|7|1|`NOC_CMD_VC_STATIC`|`true` if software dictates the class bits and buddy bit of the virtual channel number for all hops (see bits 13/14/15 of this register); `false` if the initiating NIU dynamically chooses the class bits and buddy bit for the initial hop to the router and any router along the path can dynamically flip the buddy bit|
|8|1|`NOC_CMD_PATH_RESERVE`|For broadcast requests that are the first (or sole) request in a transaction, `true` if all routers along the path need to reserve virtual channel numbers for the transaction before any data leaves the initiating NIU, `false` otherwise; ignored for other types of request. When this is `true`, broadcasts take longer to happen, but when it is `false`, software is responsible for ensuring that its traffic patterns do not cause deadlocks<br/><br/>:warning: Due to a hardware bug, a broadcast with `NOC_CMD_PATH_RESERVE` set can lose a flit and hang the NoC if its reservation is refused at a router two or more hops past the initiating tile's router, which happens when another broadcast (with or without path reservation, from any initiator) holds the virtual channel that the reservation needs there. Whether the request is posted (`NOC_CMD_RESP_MARKED`) makes no difference. Broadcasts with `NOC_CMD_PATH_RESERVE` set to `false` are not affected, though the deadlock rule above applies to them. Software that sets `NOC_CMD_PATH_RESERVE` should keep other broadcasts off the routers that its broadcast passes through while it is in flight, e.g. by waiting for each broadcast to be acknowledged before starting another one that isn't linked to it|
|9|1|`NOC_CMD_MEM_RD_DROP_ACK`|For outgoing write requests, `true` if the NoC Overlay does not require a notification of when the request data has finished leaving the NIU, `false` if it does require a notification|
|10|3|Reserved|When software writes `1` to the low bit of `NOC_CMD_CTRL`, hardware will populate these bits with a mask of which output ports the packet will be sent to at the first NoC router (the low bit is the port back to the NIU, the middle bit is the Y axis output port, and the high bit is the X axis output port)|
|13|1|`NOC_CMD_STATIC_VC`|When `NOC_CMD_VC_STATIC` is set, the buddy bit; ignored when `NOC_CMD_VC_STATIC` is not set|
|14|2|`NOC_CMD_STATIC_VC`|When `NOC_CMD_VC_STATIC` is set, the class bits (which must be either `0b00` or `0b01` for unicast requests, and must be `0b10` for multicast requests); ignored when `NOC_CMD_VC_STATIC` is not set|
|16|1|`NOC_CMD_BRCST_XY`|When `NOC_CMD_BRCST_PACKET` is set, `0` if the broadcast should use [X as the major axis](RoutingPaths.md#broadcast-routes-x-as-major-axis), or `1` if it should use [Y as the major axis](RoutingPaths.md#broadcast-routes-y-as-major-axis); ignored in other cases|
|17|1|`NOC_CMD_BRCST_SRC_INCLUDE`|When `NOC_CMD_BRCST_PACKET` is set and the initiating NIU is part of the recipient rectangle, `true` if the NIU should indeed be a recipient of the packet, or `false` if the initiating NIU should be excluded from the recipient rectangle; ignored in other cases|
|18|9|Reserved|Software should always write `0` to these bits, but hardware might subsequently change them|
|27|4|`NOC_CMD_ARB_PRIORITY`|When set to value `i`, if this request is at a router and contending for virtual channel number assignment against some other request, and that other request has priority `j`, then this request will always have priority if `0 < j < i`. When set to a value other than `0`, software is responsible for ensuring that its traffic patterns do not cause deadlocks|
|31|1|Reserved|Software should always write `0` to this bit, but hardware might subsequently change it|

### `NOC_TARG_ADDR` and `NOC_RET_ADDR`

The meaning of `NOC_TARG_ADDR` and `NOC_RET_ADDR` differs depending on the request type:

|Request type|Packet flow|
|---|---|
|Atomic request|An atomic request packet consisting of a single flit travels from the initiating NIU to `NOC_TARG_ADDR`, and then if `NOC_CMD_RESP_MARKED` was set to `true`, an atomic response packet consisting of a single flit travels back to `NOC_RET_ADDR`. Software is strongly encouraged to set the [X/Y coordinates](Coordinates.md) within `NOC_RET_ADDR` to those of the initiating NIU, and the memory addresses within `NOC_TARG_ADDR` and `NOC_RET_ADDR` must both point to somewhere in L1.|
|Read request|A read request packet consisting of a single flit travels from the initiating NIU to `NOC_TARG_ADDR`, and then a read response packet (consisting of multiple flits) containing the data travels back to `NOC_RET_ADDR`. Software is strongly encouraged to set the [X/Y coordinates](Coordinates.md) within `NOC_RET_ADDR` to those of the initiating NIU.|
|Write request with `NOC_CMD_WR_INLINE=true`|A write request packet consisting of a single flit travels from the initiating NIU to `NOC_TARG_ADDR`, and then if `NOC_CMD_RESP_MARKED` was set to `true`, a write acknowledgement packet consisting of a single flit travels back to the initiating NIU. Note that `NOC_RET_ADDR` is not used at all.|
|Write request with `NOC_CMD_WR_INLINE=false`|The initiating NIU reads data from the memory address within `NOC_TARG_ADDR`, and a write request packet (consisting of multiple flits) containing that data travels from the initiating NIU to `NOC_RET_ADDR`. If `NOC_CMD_RESP_MARKED` was set to `true`, a write acknowledgement packet consisting of a single flit travels back to the NIU at the [X/Y coordinates](Coordinates.md) within `NOC_TARG_ADDR`. Software is strongly encouraged to set the [X/Y coordinates](Coordinates.md) within `NOC_TARG_ADDR` to those of the initiating NIU.|

Expressed differently:

|Request type|Data comes from|Data written to|Acknowledgement sent to|
|---|---|---|---|
|Atomic request|`NOC_AT_DATA` or some bits within `NOC_AT_LEN_BE`|L1 memory address and [X/Y coordinates](Coordinates.md) of `NOC_TARG_ADDR` (atomic operation happens here)|L1 memory address and [X/Y coordinates](Coordinates.md) of `NOC_RET_ADDR` (when `NOC_CMD_RESP_MARKED` is set)|
|Read request|Memory address and [X/Y coordinates](Coordinates.md) of `NOC_TARG_ADDR`|Memory address and [X/Y coordinates](Coordinates.md) of `NOC_RET_ADDR`|[X/Y coordinates](Coordinates.md) of `NOC_RET_ADDR`|
|Write request with `NOC_CMD_WR_INLINE=true`|`NOC_AT_DATA`|Memory address and [X/Y coordinates](Coordinates.md) of `NOC_TARG_ADDR`|[X/Y coordinates](Coordinates.md) of initiating NIU (when `NOC_CMD_RESP_MARKED` is set)|
|Write request with `NOC_CMD_WR_INLINE=false`|Memory address of `NOC_TARG_ADDR` (at the initiating NIU)|Memory address and [X/Y coordinates](Coordinates.md) of `NOC_RET_ADDR`|[X/Y coordinates](Coordinates.md) of `NOC_TARG_ADDR` (when `NOC_CMD_RESP_MARKED` is set)|

The combination of the `LO` field and the `MID` field forms 64 bits. For unicast request packets, and all types of response packet, these bits contain:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|36|Memory address (the high 4 bits of which are usually zero). Some [alignment requirements](Alignment.md) apply.|
|36|6|[X coordinate](Coordinates.md)|
|42|6|[Y coordinate](Coordinates.md)|
|48|12|Reserved (do not affect the request or response in any way)|
|60|4|Reserved (ignored by hardware)|

For broadcast request packets (which are allowed for atomic requests and write requests), the bits instead contain:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|36|Memory address (the high 4 bits of which are usually zero). Some [alignment requirements](Alignment.md) apply.|
|36|6|[EndX coordinate](Coordinates.md)|
|42|6|[EndY coordinate](Coordinates.md)|
|48|6|[StartX coordinate](Coordinates.md)|
|54|6|[StartY coordinate](Coordinates.md)|
|60|4|Reserved (ignored by hardware)|

When `StartX ≤ EndX`, the X span of the broadcast is all `x` such that `StartX ≤ x ≤ EndX`. When `StartX > EndX`, the X span of the broadcast is all `x` such that `x ≤ EndX || StartX ≤ x`. Similarly, when `StartY ≤ EndY`, the Y span of the broadcast is all `y` such that `StartY ≤ y ≤ EndY`, and when `StartY > EndY`, the Y span of the broadcast is all `y` such that `y ≤ EndY || StartY ≤ y`. The broadcast rectangle is then the product of the X span and the Y span. Note that individual NIUs can opt out of receiving broadcast packets, and firmware will configure things such that all NIUs are opted out, other than those in Tensix tiles (some products contain Tensix tiles which are fused off for yield reasons, and any such tiles will also be opted out). When [coordinate translation](Coordinates.md#coordinate-translation) is enabled, all four of `StartX` / `EndX` / `StartY` / `EndY` will be translated to NoC coordinates, and _then_ the X / Y spans determined.

### `NOC_AT_LEN_BE`

The meaning of `NOC_AT_LEN_BE` differs depending on the request type:

|Request type|Meaning of `NOC_AT_LEN_BE`|
|---|---|
|Atomic request|[Atomic opcode and operands](Atomics.md) in some bits, with other bits ignored|
|Read request|Number of bytes to read from `NOC_TARG_ADDR` and write to `NOC_RET_ADDR`; the maximum allowed value for a single request is 8192 bytes when `NOC_TARG_ADDR` and `NOC_RET_ADDR` are both L1 addresses, whereas the only allowed value is 4 bytes when either is an MMIO address|
|Write request with `NOC_CMD_WR_BE=false` and `NOC_CMD_WR_INLINE=false`|Number of bytes to read from the memory address within `NOC_TARG_ADDR` and write to `NOC_RET_ADDR`; the maximum allowed value for a single request is 8192 bytes when `NOC_TARG_ADDR` and `NOC_RET_ADDR` are both L1 addresses, whereas the only allowed value is 4 bytes when either is an MMIO address (†)|
|Write request with `NOC_CMD_WR_BE=true` and `NOC_CMD_WR_INLINE=false`|When `NOC_RET_ADDR` is an L1 address: at most 32 bytes will be read from `NOC_TARG_ADDR &~ 0xf` and written to `NOC_RET_ADDR &~ 0xf`; `NOC_AT_LEN_BE` contains a mask of which bytes<br/>When `NOC_RET_ADDR` is an MMIO address (†): `NOC_AT_LEN_BE` is ignored; a 32-bit store to `NOC_RET_ADDR` will be performed|
|Write request with `NOC_CMD_WR_INLINE=true`|When `NOC_TARG_ADDR` is an L1 address: at most 16 bytes will be written to `NOC_TARG_ADDR &~ 0xf`; each byte address `i` in this range will be written using byte `i & 3` of `NOC_AT_DATA` when either bit `i & 15` or bit `16 + (i & 15)` of `NOC_AT_LEN_BE` is set (and left unchanged when neither such bit is set) - for maximum performance, either the low 16 bits or the high 16 bits of `NOC_AT_LEN_BE` should be entirely zero<br/>When `NOC_TARG_ADDR` is an MMIO address (†): `NOC_AT_LEN_BE` is ignored; a 32-bit store of `NOC_AT_DATA` to `NOC_TARG_ADDR` will be performed|

(†) A handful of MMIO addresses within the NoC Overlay address range are special: they sit within the address range normally used for MMIO, and are wired to MMIO logic rather than to plain SRAM, but up to 32 bytes can be written to them at once, and rules similar to those of L1 writes are used to determine the length of the write.

### `NOC_PACKET_TAG`

This field contains some uncommonly set request flags:

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|6|Stream ID|When `DeliverToReceiverOverlay` is `true`, the stream ID within the NoC Overlay to deliver the packet to|
|6|1|`DeliverToReceiverOverlay`|When write requests have this flag set to `true`, the packet will be delivered to the receiver's NoC Overlay (in addition to being written to the receiver's address space as per normal). If software does not know what value to use for this flag, it should use `false`|
|7|1|First packet of message flag|When `DeliverToReceiverOverlay` is `true`, this flag is delivered to the receiver's NoC Overlay as part of the packet|
|8|1|Last packet of message flag|When `DeliverToReceiverOverlay` is `true`, this flag is delivered to the receiver's NoC Overlay as part of the packet|
|9|1|`NOC_PACKET_TAG_HEADER_STORE`|If a posted write request has this flag set to `true`, then the receiver will write the first 128 bits of the packet's data to the address `NOC_AT_DATA << 4` (in addition to writing all of the packet's data to `NOC_RET_ADDR` as per normal)|
|10|4|`NOC_PACKET_TRANSACTION_ID`|Affects which [counters](Counters.md) are incremented when software writes to `NOC_CMD_CTRL` and are then later decremented|
|14|2|Reserved||
|16|16|Reserved|Writes to these bits are ignored; they always read as zero|

> [!CAUTION]
> Due to a hardware bug, when sending write requests to the PCI Express tile (or the ARC tile) with `NOC_CMD_RESP_MARKED` set, `NOC_PACKET_TRANSACTION_ID` must be set to zero. Otherwise, the counters identified by `NOC_PACKET_TRANSACTION_ID` will be incremented by the write request, but the counters at index zero will be decremented when the write acknowledgement arrives.

### `NOC_CMD_CTRL`

Software instructs the NIU to initiate a NoC request by writing details of the request to the _other_ fields of the initiator, and then writing to `NOC_CMD_CTRL` with the low bit set. This will immediately cause the NIU to:
* Increment the `NIU_MST_REQS_OUTSTANDING_ID` and `NIU_MST_WRITE_REQS_OUTGOING_ID` [counters](Counters.md), if appropriate for the configured request.
* If coordinate translation is enabled, apply coordinate translation to the X and Y coordinates in `NOC_TARG_ADDR_MID` and `NOC_RET_ADDR_MID`, writing the translated coordinates back to `NOC_TARG_ADDR_MID` and `NOC_RET_ADDR_MID`.
* Write values to some of the reserved fields within `NOC_CTRL`.
* Append the initiator to an internal queue of initiators waiting to have a virtual channel number assigned to them.

If the queue referenced in the final step above has any initiators in it, then hardware will continuously try to assign a virtual channel number to the initiator at the front of the queue. Until this assignment has happened, software must not write to any fields of the initiator. Once this assignment happens, hardware will clear the low bit of `NOC_CMD_CTRL`, at which point software is free to reconfigure the initiator again and instruct another request through it. Given all this, it is recommended that software always checks the low bit of `NOC_CMD_CTRL` before writing to any fields of the initiator.

## NIU Combined Request Initiator Status

This 32-bit register provides a convenient way to simultaneously query the status of all of the NIU's request initiators.

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|1|Low bit of request initiator #0's [`NOC_CMD_CTRL`](#noc_cmd_ctrl)|
|1|1|Low bit of request initiator #1's [`NOC_CMD_CTRL`](#noc_cmd_ctrl)|
|2|1|Low bit of request initiator #2's [`NOC_CMD_CTRL`](#noc_cmd_ctrl)|
|3|1|Low bit of request initiator #3's [`NOC_CMD_CTRL`](#noc_cmd_ctrl)|
|4|28|Reserved (always zero)|

## NIU Identification Details

A pair of read-only 32-bit registers provide details about the NIU and what it is attached to.

|Name|Example Address|Purpose|
|---|---|---|
|[`NOC_NODE_ID`](#noc_node_id)|`0xFFB2_002C`|Provides details about the NIU, the attached router, and the containing NoC|
|[`NOC_ENDPOINT_ID`](#noc_endpoint_id)|`0xFFB2_0030`|Uniquely identifies each NIU within an ASIC|

### `NOC_NODE_ID`

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|6|NIU's [X coordinate](Coordinates.md), which in practice will always be between `0` and `9`|
|6|6|NIU's [Y coordinate](Coordinates.md), which in practice will always be between `0` and `11`|
|12|7|Number of NIUs in each row of the NoC (also known as the width of the NoC). This value will be the same at all NIUs, and in practice is always `10`|
|19|7|Number of NIUs in each column of the NoC (also known as the height of the NoC). This value will be the same at all NIUs, and in practice is always `12`|
|26|1|If `true`, the dateline bit of the virtual circuit number can flip when packets transit through the outbound X port of the router attached to this NIU|
|27|1|If `true`, the dateline bit of the virtual circuit number can flip when packets transit through the outbound Y port of the router attached to this NIU|
|28|1|If `true`, unicast packet routes always perform all movement in the X axis before any movement in the Y axis. If `false`, unicast packet routes always perform all movement in the Y axis before any movement in the X axis. This value will be the same at all NIUs within a NoC, and in practice is always `true` at all NoC #0 NIUs and `false` at all NoC #1 NIUs|
|29|3|Reserved (always zero)|

If coordinate translation is enabled (see bit 14 of `NIU_CFG_0`), the software might also want to know the X and Y coordinates of the NIU in translated space. It can find these in `NOC_ID_LOGICAL`.

### `NOC_ENDPOINT_ID`

All NIUs within a given ASIC have distinct values for `NOC_ENDPOINT_ID`, and the values can be inspected to determine what kind of tile is attached to the NIU:

|First&nbsp;bit|#&nbsp;Bits|Contents|Values|
|--:|--:|---|---|
|0|8|Tile index|Tensix tiles: a value between `0` and `79`<br/>Ethernet tiles: a value between `0` and `15`<br/>PCIe tile: always `2`<br/>Empty tiles: some value other than `2`<br/>ARC tile: always `0`<br/>DRAM tiles: a value between `0` and `2`|
|8|8|Group index|DRAM tiles: a value between `0` and `5`<br/>Other tiles: always `0`|
|16|8|Tile type|<code>1</code> - Tensix tile<br/><code>2</code> - Ethernet tile<br/><code>3</code> - PCIe tile or empty tile<br/><code>5</code> - ARC tile<br/><code>8</code> - DRAM tile|
|24|8|NoC index|`0` for all NoC #0 NIUs<br/>`1` for all NoC #1 NIUs|

## NIU and NoC Router Configuration

Each NIU has a handful of configuration registers in its memory map. Some of the bits in these registers have a particular purpose, and then the remaining bits in them are available for general use by software.

|Name|Example Address|Size|
|---|---|---|
|[`NIU_CFG_0`](#niu_cfg_0)|`0xFFB2_0100`|Low 15 bits have particular purpose,<br/>high 17 bits available for general use|
|[`ROUTER_CFG_0`](#router_cfg_0)|`0xFFB2_0104`|Low 19 bits have particular purpose,<br/>high 13 bits available for general use|
|[`ROUTER_CFG_1`](#router_cfg_1)|`0xFFB2_0108`|Low 10 bits have particular purpose,<br/>high 22 bits available for general use|
|`ROUTER_CFG_2`|`0xFFB2_010C`|All 32 bits available for general use|
|[`ROUTER_CFG_3`](#router_cfg_3)|`0xFFB2_0110`|Low 12 bits have particular purpose,<br/>high 20 bits available for general use|
|`ROUTER_CFG_4`|`0xFFB2_0114`|All 32 bits available for general use|
|[`NOC_X_ID_TRANSLATE_TABLE_0`](#noc_x_id_translate_table_0-and-noc_y_id_translate_table_0)|`0xFFB2_0118`|128-bit lookup table|
|[`NOC_Y_ID_TRANSLATE_TABLE_0`](#noc_x_id_translate_table_0-and-noc_y_id_translate_table_0)|`0xFFB2_0128`|128-bit lookup table|
|[`NOC_ID_LOGICAL`](#noc_id_logical)|`0xFFB2_0138`|Low 12 bits have particular purpose,<br/>high 20 bits available for general use|

### `NIU_CFG_0`

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|12|Reserved; software should preserve the values of these bits when modifying other bits|
|12|1|Tile clock disable; if set to `true`, then the tile attached to the NIU will be disabled (firmware will set this to `true` for fused-off tiles)|
|13|1|Double store disable; has no effect in Tensix tiles and Ethernet tiles, but if set to `true` in other types of tile, the tile will ignore the `NOC_PACKET_TAG_HEADER_STORE` flag|
|14|1|Coordinate translation enable; if set to `true`, `NOC_X_ID_TRANSLATE_TABLE_0` and `NOC_Y_ID_TRANSLATE_TABLE_0` [define a coordinate translation scheme](Coordinates.md#coordinate-translation)|
|15|17|Available for general use|

### `ROUTER_CFG_0`

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|19|Reserved; software should preserve the values of these bits when modifying other bits|
|19|13|Available for general use|

### `ROUTER_CFG_1`

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|10|Broadcast opt-out mask for columns|
|10|22|Available for general use|

Any given NIU will use one bit out of the first ten bits, based on its X coordinate. If that bit is set, then the NIU is opted-out from receiving broadcast packets. The same mask should be set at all NIUs (most of the time this is just a convenience for software, but at the PCI Express tile the entire mask needs to be accurate). Firmware will configure this mask such that only Tensix tiles receive broadcasts.

### `ROUTER_CFG_3`

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|12|Broadcast opt-out mask for rows|
|12|20|Available for general use|

Any given NIU will use one bit out of the first twelve bits, based on its Y coordinate. If that bit is set, then the NIU is opted-out from receiving broadcast packets. The same mask should be set at all NIUs (most of the time this is just a convenience for software, but at the PCI Express tile the entire mask needs to be accurate). Firmware will configure this mask such that only Tensix tiles receive broadcasts.

### `NOC_X_ID_TRANSLATE_TABLE_0` and `NOC_Y_ID_TRANSLATE_TABLE_0`

When bit 14 of `NIU_CFG_0` is set, coordinate translation is enabled at the NIU. When coordinate translation is disabled, the X/Y coordinates in `NOC_TARG_ADDR_MID` and `NOC_RET_ADDR_MID` are NoC coordinates. When coordinate translation is enabled, as software writes to `NOC_CMD_CTRL`, hardware will take each X coordinate in `NOC_TARG_ADDR_MID` / `NOC_RET_ADDR_MID` and run it through an X translation table to get an X in NoC coordinate space, and take each Y coordinate in `NOC_TARG_ADDR_MID` / `NOC_RET_ADDR_MID` and run it through a Y translation table to get a Y in NoC coordinate space. The X translation table is configured through 128 bits starting at `NOC_X_ID_TRANSLATE_TABLE_0`, and the Y translation table is configured through 128 bits starting at `NOC_Y_ID_TRANSLATE_TABLE_0`. For the purpose of MMIO, each 128 bits is four separate 32-bit registers. For the purpose of table lookup, each 128 bits is 32 entries of 4 bits each. [Firmware will configure these tables](Coordinates.md#coordinate-translation).

### `NOC_ID_LOGICAL`

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|6|NIU's X coordinate, in translated space|
|6|6|NIU's Y coordinate, in translated space|
|12|20|Available for general use|

Upon initial ASIC power-on, this register will contain the [X and Y coordinates](Coordinates.md) of the NIU, in NoC coordinate space (i.e. between `0` and `9` for X and between `0` and `11` for Y). When firmware configures the coordinate translation tables, firmware will also update this register to contain the X and Y coordinates of the NIU [in translated space](Coordinates.md#coordinate-translation) (i.e. between `16` and `25` for X, and between `16` and `27` for Y).
