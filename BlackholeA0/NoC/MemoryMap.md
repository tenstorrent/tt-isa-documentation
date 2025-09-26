# NIU Memory Map

Each NIU ([NoC](README.md) interface unit) has an assortment of command and configuration and status registers mapped into the address space of the containing tile. Each tile will contain two NIUs; NIU #0 will be connected to a NoC #0 router, and NIU #1 will be connected to a NoC #1 router. The two NIUs are identical, other than which NoC they're part of and where in the address space they are presented. The base address for where they are presented (`NIU_BASE`) is:

|Tile type|`NIU_BASE` for NoC #0|`NIU_BASE` for NoC #1|
|---|---|---|
|Tensix or Ethernet|`0x0000_0000_FFB2_0000`|`0x0000_0000_FFB3_0000`|
|DRAM|`0x????_????_FFB2_0000`|`0x????_????_FFB3_0000`|
|Empty, when accessed through NoC #0|`0x0000_0000_FFB2_0000` or<br/>`0x0000_0000_FFB3_0000`|Cannot access|
|Empty, when accessed through NoC #1|Cannot access|`0x0000_0000_FFB2_0000` or<br/>`0x0000_0000_FFB3_0000`|
|Other, when accessed through NoC #0|`0xFFFF_FFFF_FFB2_0000` or<br/>`0xFFFF_FFFF_FFB3_0000`|Cannot access|
|Other, when accessed through NoC #1|Cannot access|`0xFFFF_FFFF_FFB2_0000` or<br/>`0xFFFF_FFFF_FFB3_0000`|

The high-level contents at this address are:

|Address range start|Example address range|Contents|Software access|
|---|---|---|---|
|`NIU_BASE + 0x0000`|`0xFFB2_0000` to `0xFFB2_0043`|[NIU request initiator](#niu-request-initiators) #0|Read / write|
|`NIU_BASE + 0x0044`|`0xFFB2_0044` to `0xFFB2_004B`|[NIU identification details](#niu-identification-details)|Read only|
|`NIU_BASE + 0x0060`|`0xFFB2_0060` to `0xFFB2_0063`|[Clear NIU transaction ID counters](Counters.md#clear-niu-transaction-id-counters)|Write only|
|`NIU_BASE + 0x0064`|`0xFFB2_0064` to `0xFFB2_006B`|NIU request FIFO status|Read only|
|`NIU_BASE + 0x0100`|`0xFFB2_0100` to `0xFFB2_017F`|[NIU and NoC router configuration](#niu-and-noc-router-configuration)|Read / write|
|`NIU_BASE + 0x0200`|`0xFFB2_0200` to `0xFFB2_02FF`|[NIU counters](Counters.md)|Read only|
|`NIU_BASE + 0x0300`|`0xFFB2_0300` to `0xFFB2_0377`|NoC router debug information|Read only|
|`NIU_BASE + 0x0378`|`0xFFB2_0378` to `0xFFB2_037F`|[NIU interrupt status](#interrupt-status)|Read only|
|`NIU_BASE + 0x0380`|`0xFFB2_0380` to `0xFFB2_03FF`|NIU debug information|Read only|
|`NIU_BASE + 0x0400`|`0xFFB2_0400` to `0xFFB2_04FF`|NIU security fence configuration|Read / write|
|`NIU_BASE + 0x0500`|`0xFFB2_0500` to `0xFFB2_05FF`|NoC router per-port per-VC packet counters|Read only|
|`NIU_BASE + 0x0800`|`0xFFB2_0800` to `0xFFB2_0843`|[NIU request initiator](#niu-request-initiators) #1|Read / write|
|`NIU_BASE + 0x0844`|`0xFFB2_0844` to `0xFFB2_084B`|[NIU identification details](#niu-identification-details) (again)|Read only|
|`NIU_BASE + 0x0864`|`0xFFB2_0864` to `0xFFB2_086B`|NIU request FIFO status (again)|Read only|
|`NIU_BASE + 0x1000`|`0xFFB2_1000` to `0xFFB2_102B`|[NIU request initiator](#niu-request-initiators) #2|Read / write|
|`NIU_BASE + 0x1044`|`0xFFB2_1044` to `0xFFB2_104B`|[NIU identification details](#niu-identification-details) (again)|Read only|
|`NIU_BASE + 0x1064`|`0xFFB2_1064` to `0xFFB2_106B`|NIU request FIFO status (again)|Read only|
|`NIU_BASE + 0x1800`|`0xFFB2_1800` to `0xFFB2_182B`|[NIU request initiator](#niu-request-initiators) #3|Read / write|
|`NIU_BASE + 0x1844`|`0xFFB2_1844` to `0xFFB2_184B`|[NIU identification details](#niu-identification-details) (again)|Read only|
|`NIU_BASE + 0x1864`|`0xFFB2_1864` to `0xFFB2_186B`|NIU request FIFO status (again)|Read only|

## NIU Request Initiators

Each NIU has four request initiators, starting at addresses `NIU_BASE + i * NOC_CMD_BUF_OFFSET` (`0 ≤ i ≤ 3`). The four initiators are functionally identical, so software is free to use any initiator for any purpose, though it can avoid the need to repeatedly reprogram certain registers by statically assigning particular purposes to particular initiators.

|Name|Example Address|Contents|
|---|---|---|
|[`NOC_TARG_ADDR_LO`](#noc_targ_addr-and-noc_ret_addr)|`0xFFB2_0000`|Low 32 bits of "target" memory address|
|[`NOC_TARG_ADDR_MID`](#noc_targ_addr-and-noc_ret_addr)|`0xFFB2_0004`|High 32 bits of "target" memory address (should be zero when the "target" tile only has a 32-bit address space)|
|[`NOC_TARG_ADDR_HI`](#noc_targ_addr-and-noc_ret_addr)|`0xFFB2_0008`|The "target" [X/Y coordinates](Coordinates.md)|
|[`NOC_RET_ADDR_LO`](#noc_targ_addr-and-noc_ret_addr)|`0xFFB2_000C`|Low 32 bits of "return" memory address|
|[`NOC_RET_ADDR_MID`](#noc_targ_addr-and-noc_ret_addr)|`0xFFB2_0010`|High 32 bits of "return" memory address (should be zero when the "return" tile only has a 32-bit address space)|
|[`NOC_RET_ADDR_HI`](#noc_targ_addr-and-noc_ret_addr)|`0xFFB2_0014`|The "return" [X/Y coordinates](Coordinates.md)|
|[`NOC_PACKET_TAG`](#noc_packet_tag)|`0xFFB2_0018`|Transaction ID (4 bits) and uncommonly set request flags|
|[`NOC_CTRL`](#noc_ctrl)|`0xFFB2_001C`|Request type (2 bits) and commonly set request flags|
|[`NOC_AT_LEN_BE`](#noc_at_len_be)|`0xFFB2_0020`|Depending on the request type, either contains [the atomic opcode and operands](Atomics.md), or the length (in bytes) of a read or write, or a byte-enable mask for short writes|
|`NOC_AT_LEN_BE_1`|`0xFFB2_0024`|High 32 bits of `NOC_AT_LEN_BE`, to form either a 64-bit length or a 64-bit byte-enable mask|
|`NOC_AT_DATA`|`0xFFB2_0028`|For inline writes, and most types of atomics, contains the 32 bits of immediate data|
|`NOC_BRCST_EXCLUDE`|`0xFFB2_002C`|For broadcast requests, additional configuration allowing for non-rectangular broadcasts|
|[`NOC_CMD_CTRL`](#noc_cmd_ctrl)|`0xFFB2_0040`|Writing `1` to the low bit indicates that software wishes to initiate a request using the fields of this initiator; hardware will transition the bit back to `0` once the request has been initiated|

> [!WARNING]
> Software can only use the NIU request initiators in Tensix tiles, Ethernet tiles, and DRAM tiles. Software can also cause the PCI Express tile and L2CPU tiles to send NoC requests, but the mechanism for doing so is different to the mechanism described here. Software can cause NoC requests to be sent _to_ other types of tile, and receive responses _from_ those tiles, but it cannot initiate NoC requests _at_ those tiles.

### `NOC_CTRL`

This field contains the request type and some commonly set request flags:

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|2|Request type|`NOC_CMD_RD` (`0`) for read requests<br/>`NOC_CMD_AT` (`1`) for atomic requests<br/>`NOC_CMD_WR` (`2`) for write requests<br/>The value `3` is reserved and should not be used<br/><br/>:warning: `NOC_CMD_AT` requires that the request be destined for the L1 of a Tensix tile or Ethernet tile|
|2|1|`NOC_CMD_WR_BE`|For write requests, `true` if `NOC_AT_LEN_BE` contains a byte-enable mask (and hence the write is at most 32 bytes), or `false` if `NOC_AT_LEN_BE` contains a length (and hence the write is between 1 and 16384 bytes); ignored for other types of request|
|3|1|`NOC_CMD_WR_INLINE`|For write requests, `true` if `NOC_AT_DATA` contains the data to be written, `false` otherwise (in which case `NOC_TARG_ADDR` contains the address of the data in the initiator's address space); ignored for other types of request<br/><br/>:warning: `NOC_CMD_WR_INLINE` requires that the request be destined for a Tensix tile or an Ethernet tile<br/><br/>:warning: Due to a hardware bug in Blackhole, `NOC_CMD_WR_INLINE` should not be used when the destination is an L1 address (it remains safe to use for MMIO addresses)|
|4|1|`NOC_CMD_RESP_MARKED`|For write requests and atomic requests, `false` if the request is posted (i.e. a response / acknowledgement will not be sent), `true` otherwise (i.e. a response / acknowledgement is desired); ignored for read requests (they always generate a response)|
|5|1|`NOC_CMD_BRCST_PACKET`|`false` if the request is unicast, `true` if the request is broadcast; should always be `false` for read requests|
|6|1|`NOC_CMD_VC_LINKED`|`false` if the request is the sole request in a transaction or the final request in a multi-request transaction; `true` if the request is part of a multi-request transaction but is not the final request in the transaction. If this flag is used, then: <ul><li>The next request issued by the NIU will be part of the same transaction as the request with `NOC_CMD_VC_LINKED` set on it.</li><li>All requests in the transaction must be to the same destination tile, or for broadcast, to the same destination rectangle (and using the same value of `NOC_CMD_BRCST_XY`). Failure to comply with this requirement will lead to complete NoC failure.</li><li>The NIU will be unable to initiate requests on any virtual channel number other than the one used for the transaction. Attempting to initiate a request with an incompatible virtual channel number will cause virtual channel number assignment to continuously fail, leaving the NIU unable to initiate any requests.</li><li>All NoC routers along the path (or, for broadcast, the tree) taken by the request will not allow the chosen virtual channel numbers to be used by any other transactions until the last request in the transaction has finished passing through them.</li><li>The NoC Overlay in the tile will be unable to initiate any requests until the last request in the transaction has been initiated. The converse is true when the NoC Overlay is in the middle of a multi-request transaction: the regular NIU request initiators will be unable to initiate any requests.</li></ul>Given all this, if software initiates a request with `NOC_CMD_VC_LINKED` set to `true`, it is responsible for promptly completing the transaction by initiating a request with it set to `false`.|
|7|1|`NOC_CMD_VC_STATIC`|`true` if software dictates the class bits and buddy bit of the virtual channel number for all hops (see bits 13/14/15 of this register); `false` if the initiating NIU dynamically chooses the class bits and buddy bit for the initial hop to the router and any router along the path can dynamically flip the buddy bit|
|8|1|`NOC_CMD_PATH_RESERVE`|For broadcast requests that are the first (or sole) request in a transaction, `true` if all routers along the path need to reserve virtual channel numbers for the transaction before any data leaves the initiating NIU, `false` otherwise; ignored for other types of request. When this is `true`, broadcasts take longer to happen, but when it is `false`, software is responsible for ensuring that its traffic patterns do not cause deadlocks|
|9|1|`NOC_CMD_MEM_RD_DROP_ACK`|For outgoing write requests, `true` if the NoC Overlay does not require a notification of when the request data has finished leaving the NIU, `false` if it does require a notification|
|10|3|Reserved|Software should always write `0` to these bits, but hardware might subsequently change them|
|13|1|`NOC_CMD_STATIC_VC`|When `NOC_CMD_VC_STATIC` is set, the buddy bit; ignored when `NOC_CMD_VC_STATIC` is not set|
|14|2|`NOC_CMD_STATIC_VC`|When `NOC_CMD_VC_STATIC` is set, the class bits (which must be either `0b00` or `0b01` for unicast requests, and must be `0b10` for multicast requests); ignored when `NOC_CMD_VC_STATIC` is not set|
|16|1|`NOC_CMD_BRCST_XY`|When `NOC_CMD_BRCST_PACKET` is set, `0` if the broadcast should use [X as the major axis](RoutingPaths.md#broadcast-routes-x-as-major-axis), or `1` if it should use [Y as the major axis](RoutingPaths.md#broadcast-routes-y-as-major-axis); ignored in other cases|
|17|1|`NOC_CMD_BRCST_SRC_INCLUDE`|When `NOC_CMD_BRCST_PACKET` is set and the initiating NIU is part of the recipient rectangle, `true` if the NIU should indeed be a recipient of the packet, or `false` if the initiating NIU should be excluded from the recipient rectangle; ignored in other cases|
|18|9|Reserved|Software should always write `0` to these bits, but hardware might subsequently change them|
|27|4|`NOC_CMD_ARB_PRIORITY`|When set to value `i`, if this request is at a router and contending for virtual channel number assignment against some other request, and that other request has priority `j`, then this request will always have priority if `0 < j < i`. When set to a value other than `0`, software is responsible for ensuring that its traffic patterns do not cause deadlocks|
|31|1|`NOC_CMD_L1_ACC_AT_EN`|For read requests and write requests, `true` if the request's eventual L1 write should be an atomic accumulate rather than a plain write<br/><br/>:warning: Due to a hardware bug, this functionality cannot be safely used, meaning that this bit should always be set to `false`|

### `NOC_TARG_ADDR` and `NOC_RET_ADDR`

The meaning of `NOC_TARG_ADDR` and `NOC_RET_ADDR` differs depending on the request type:

|Request type|Packet flow|
|---|---|
|Atomic request|An atomic request packet consisting of a single flit travels from the initiating NIU to `NOC_TARG_ADDR`, and then if `NOC_CMD_RESP_MARKED` was set to `true`, an atomic response packet consisting of a single flit travels back to `NOC_RET_ADDR`. Software is strongly encouraged to set the [X/Y coordinates](Coordinates.md) within `NOC_RET_ADDR_HI` to those of the initiating NIU, and the memory addresses within `NOC_TARG_ADDR` and `NOC_RET_ADDR` must both point to somewhere in L1.|
|Read request|A read request packet consisting of a single flit travels from the initiating NIU to `NOC_TARG_ADDR`, and then a read response packet (consisting of multiple flits) containing the data travels back to `NOC_RET_ADDR`. Software is strongly encouraged to set the [X/Y coordinates](Coordinates.md) within `NOC_RET_ADDR_HI` to those of the initiating NIU.|
|Write request with `NOC_CMD_WR_INLINE=true`|A write request packet consisting of a single flit travels from the initiating NIU to `NOC_TARG_ADDR`, and then if `NOC_CMD_RESP_MARKED` was set to `true`, a write acknowledgement packet consisting of a single flit travels back to the initiating NIU. Note that `NOC_RET_ADDR` is not used at all.|
|Write request with `NOC_CMD_WR_INLINE=false`|The initiating NIU reads data from the memory address within `NOC_TARG_ADDR`, and a write request packet (consisting of multiple flits) containing that data travels from the initiating NIU to `NOC_RET_ADDR`. If `NOC_CMD_RESP_MARKED` was set to `true`, a write acknowledgement packet consisting of a single flit travels back to the NIU at the [X/Y coordinates](Coordinates.md) within `NOC_TARG_ADDR_HI`. Software is strongly encouraged to set the [X/Y coordinates](Coordinates.md) within `NOC_TARG_ADDR_HI` to those of the initiating NIU.|

Expressed differently:

|Request type|Data comes from|Data written to|Acknowledgement sent to|
|---|---|---|---|
|Atomic request|`NOC_AT_DATA` or some bits within `NOC_AT_LEN_BE`|L1 memory address and [X/Y coordinates](Coordinates.md) of `NOC_TARG_ADDR` (atomic operation happens here)|L1 memory address and [X/Y coordinates](Coordinates.md) of `NOC_RET_ADDR` (when `NOC_CMD_RESP_MARKED` is set)|
|Read request|Memory address and [X/Y coordinates](Coordinates.md) of `NOC_TARG_ADDR`|Memory address and [X/Y coordinates](Coordinates.md) of `NOC_RET_ADDR`|[X/Y coordinates](Coordinates.md) of `NOC_RET_ADDR_HI`|
|Write request with `NOC_CMD_WR_INLINE=true`|`NOC_AT_DATA`|Memory address and [X/Y coordinates](Coordinates.md) of `NOC_TARG_ADDR`|[X/Y coordinates](Coordinates.md) of initiating NIU (when `NOC_CMD_RESP_MARKED` is set)|
|Write request with `NOC_CMD_WR_INLINE=false`|Memory address of `NOC_TARG_ADDR` (at the initiating NIU)|Memory address and [X/Y coordinates](Coordinates.md) of `NOC_RET_ADDR`|[X/Y coordinates](Coordinates.md) of `NOC_TARG_ADDR_HI` (when `NOC_CMD_RESP_MARKED` is set)|

Some [alignment requirements](Alignment.md) apply to the `LO` bits.

For unicast request packets, and all types of response packet, the `HI` bits contain:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|6|[X coordinate](Coordinates.md)|
|6|6|[Y coordinate](Coordinates.md)|
|12|12|Reserved (do not affect the request or response in any way)|
|24|8|Reserved (ignored by hardware)|

For broadcast request packets (which are allowed for atomic requests and write requests), the `HI` bits instead contain:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|6|[EndX coordinate](Coordinates.md)|
|6|6|[EndY coordinate](Coordinates.md)|
|12|6|[StartX coordinate](Coordinates.md)|
|18|6|[StartY coordinate](Coordinates.md)|
|24|8|Reserved (ignored by hardware)|

When `StartX ≤ EndX`, the X span of the broadcast is all `x` such that `StartX ≤ x ≤ EndX`. When `StartX > EndX`, the X span of the broadcast is all `x` such that `x ≤ EndX || StartX ≤ x`. Similarly, when `StartY ≤ EndY`, the Y span of the broadcast is all `y` such that `StartY ≤ y ≤ EndY`, and when `StartY > EndY`, the Y span of the broadcast is all `y` such that `y ≤ EndY || StartY ≤ y`. The broadcast rectangle is then the product of the X span and the Y span. Note that individual NIUs can opt out of receiving broadcast packets, and firmware will configure things such that all NIUs are opted out, other than those in Tensix tiles (some products contain Tensix tiles which are fused off for yield reasons, and any such tiles will also be opted out). When [coordinate translation](Coordinates.md#coordinate-translation) is enabled, all four of `StartX` / `EndX` / `StartY` / `EndY` will be translated to NoC coordinates, and _then_ the X / Y spans determined.

### `NOC_AT_LEN_BE`

The meaning of `NOC_AT_LEN_BE` differs depending on the request type:

|Request type|Meaning of `NOC_AT_LEN_BE`|
|---|---|
|Atomic request|[Atomic opcode and operands](Atomics.md) in some bits, with other bits ignored|
|Read request|Number of bytes to read from `NOC_TARG_ADDR` and write to `NOC_RET_ADDR`; the maximum allowed value for a single request is 16384 bytes when `NOC_TARG_ADDR` and `NOC_RET_ADDR` are both L1 addresses, whereas the only allowed value is 4 bytes when either is an MMIO address|
|Write request with `NOC_CMD_WR_BE=false` and `NOC_CMD_WR_INLINE=false`|Number of bytes to read from the memory address within `NOC_TARG_ADDR` and write to `NOC_RET_ADDR`; the maximum allowed value for a single request is 16384 bytes when `NOC_TARG_ADDR` and `NOC_RET_ADDR` are both L1 addresses, whereas the only allowed value is 4 bytes when either is an MMIO address (†)|
|Write request with `NOC_CMD_WR_BE=true` and `NOC_CMD_WR_INLINE=false`|When `NOC_RET_ADDR` is an L1 address: at most 64 bytes will be read from `NOC_TARG_ADDR &~ 0xf` and written to `NOC_RET_ADDR &~ 0xf`; `NOC_AT_LEN_BE` contains a mask of which bytes<br/>When `NOC_RET_ADDR` is an MMIO address (†): `NOC_AT_LEN_BE` is ignored; a 32-bit store to `NOC_RET_ADDR` will be performed|
|Write request with `NOC_CMD_WR_INLINE=true`|When `NOC_TARG_ADDR` is an L1 address: due to a hardware bug in Blackhole, write requests with `NOC_CMD_WR_INLINE=true` to L1 addresses are not safe and should be avoided<br/>When `NOC_TARG_ADDR` is an MMIO address (†): `NOC_AT_LEN_BE` is ignored; a 32-bit store of `NOC_AT_DATA` to `NOC_TARG_ADDR` will be performed|

> (†) A handful of MMIO addresses within the NoC Overlay address range are special: they sit within the address range normally used for MMIO, and are wired to MMIO logic rather than to plain SRAM, but up to 64 bytes can be written to them at once, and rules similar to those of L1 writes are used to determine the length of the write.

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

### `NOC_CMD_CTRL`

Software instructs the NIU to initiate a NoC request by writing details of the request to the _other_ fields of the initiator, and then writing to `NOC_CMD_CTRL` with the low bit set. This will immediately cause the NIU to:
* Increment the `NIU_MST_REQS_OUTSTANDING_ID` and `NIU_MST_WRITE_REQS_OUTGOING_ID` [counters](Counters.md), if appropriate for the configured request.
* If coordinate translation is enabled, apply coordinate translation to the X and Y coordinates in `NOC_TARG_ADDR_HI` and `NOC_RET_ADDR_HI`, writing the translated coordinates back to `NOC_TARG_ADDR_HI` and `NOC_RET_ADDR_HI`.
* Write values to some of the reserved fields within `NOC_CTRL`.
* Append the initiator to an internal queue of initiators waiting to have a virtual channel number assigned to them.

If the queue referenced in the final step above has any initiators in it, then hardware will continuously try to assign a virtual channel number to the initiator at the front of the queue. Until this assignment has happened, software must not write to any fields of the initiator. Once this assignment happens, hardware will clear the low bit of `NOC_CMD_CTRL`, at which point software is free to reconfigure the initiator again and instruct another request through it. Given all this, it is recommended that software always checks the low bit of `NOC_CMD_CTRL` before writing to any fields of the initiator.

## NIU Identification Details

A pair of read-only 32-bit registers provide details about the NIU and what it is attached to.

|Name|Example Address|Purpose|
|---|---|---|
|[`NOC_NODE_ID`](#noc_node_id)|`0xFFB2_0044`|Provides details about the NIU, the attached router, and the containing NoC|
|[`NOC_ENDPOINT_ID`](#noc_endpoint_id)|`0xFFB2_0048`|Uniquely identifies each NIU within an ASIC|

### `NOC_NODE_ID`

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|6|NIU's [X coordinate](Coordinates.md), which in practice will always be between `0` and `16`|
|6|6|NIU's [Y coordinate](Coordinates.md), which in practice will always be between `0` and `11`|
|12|7|Number of NIUs in each row of the NoC (also known as the width of the NoC). This value will be the same at all NIUs, and in practice is always `17`|
|19|7|Number of NIUs in each column of the NoC (also known as the height of the NoC). This value will be the same at all NIUs, and in practice is always `12`|
|26|1|If `true`, the dateline bit of the virtual circuit number can flip when packets transit through the outbound X port of the router attached to this NIU|
|27|1|If `true`, the dateline bit of the virtual circuit number can flip when packets transit through the outbound Y port of the router attached to this NIU|
|28|1|If `true`, unicast packet routes always perform all movement in the X axis before any movement in the Y axis. If `false`, unicast packet routes always perform all movement in the Y axis before any movement in the X axis. This value will be the same at all NIUs within a NoC, and in practice is always `true` at all NoC #0 NIUs and `false` at all NoC #1 NIUs|
|29|3|Reserved (always zero)|

If coordinate translation is enabled (see bit 14 of `NIU_CFG_0`), the software might also want to know the X and Y coordinates of the NIU in translated space. It can find these in `NOC_ID_LOGICAL`.

### `NOC_ENDPOINT_ID`

Most NIUs within a given ASIC have distinct values for `NOC_ENDPOINT_ID`, and the values can be inspected to determine what kind of tile is attached to the NIU:

|First&nbsp;bit|#&nbsp;Bits|Contents|Values|
|--:|--:|---|---|
|0|8|Tile index|Tensix tiles: a value between `0` and `139`<br/>Ethernet tiles: a value between `0` and `13`<br/>DRAM tiles: group index rather than tile index, i.e. a value between `0` and `7`<br/>L2CPU tiles: a value between `0` and `3`<br/>PCIe tile: always `2`<br/>ARC tile: always `0`<br/>Security tile: always `0`|
|8|16|Tile type|<code>0x0100</code> - Tensix tile<br/><code>0x0200</code> - Ethernet tile<br/><code>0x0300</code> - PCIe tile<br/><code>0x0500</code> - ARC tile<br/><code>0x0800</code> - DRAM tile<br/><code>0x0901</code> - L2CPU tile<br/><code>0x0A00</code> - Security tile|
|24|8|NoC index|`0` for all NoC #0 NIUs<br/>`1` for all NoC #1 NIUs (most of the time)|

> [!NOTE]
> Wormhole had a unique `NOC_ENDPOINT_ID` value for every NIU within a given ASIC. Unfortunately, the same is not true for Blackhole: it sometimes reuses `NOC_ENDPOINT_ID` values: both PCIe tiles have the same ID, all DRAM tiles within the same group have the same ID, and many empty tiles have the same ID.

## NIU and NoC Router Configuration

Each NIU has a handful of configuration registers in its memory map. Some of the bits in these registers have a particular purpose, and then the remaining bits in them are available for general use by software.

|Name|Example Address|Size|
|---|---|---|
|[`NIU_CFG_0`](#niu_cfg_0)|`0xFFB2_0100`|Low 17 bits have particular purpose,<br/>high 15 bits available for general use|
|[`ROUTER_CFG_0`](#router_cfg_0)|`0xFFB2_0104`|Low 19 bits have particular purpose,<br/>high 13 bits available for general use|
|[`ROUTER_CFG_1`](#router_cfg_1)|`0xFFB2_0108`|Low 17 bits have particular purpose,<br/>high 15 bits available for general use|
|`ROUTER_CFG_2`|`0xFFB2_010C`|All 32 bits available for general use|
|[`ROUTER_CFG_3`](#router_cfg_3)|`0xFFB2_0110`|Low 12 bits have particular purpose,<br/>high 20 bits available for general use|
|`ROUTER_CFG_4`|`0xFFB2_0114`|All 32 bits available for general use|
|[`NOC_X_ID_TRANSLATE_TABLE_0`](Coordinates.md#translation-algorithm)|`0xFFB2_0118`|160-bit lookup table split across 6x 32-bit registers|
|[`NOC_Y_ID_TRANSLATE_TABLE_0`](Coordinates.md#translation-algorithm)|`0xFFB2_0130`|160-bit lookup table split across 6x 32-bit registers|
|[`NOC_ID_LOGICAL`](#noc_id_logical)|`0xFFB2_0148`|Low 12 bits have particular purpose,<br/>high 20 bits available for general use|
|[`NOC_ID_TRANSLATE_COL_MASK`](Coordinates.md#translation-algorithm)|`0xFFB2_0150`|All 32 bits have particular purpose|
|[`NOC_ID_TRANSLATE_ROW_MASK`](Coordinates.md#translation-algorithm)|`0xFFB2_0154`|All 32 bits have particular purpose|
|[`DDR_COORD_TRANSLATE_TABLE_0`](Coordinates.md#translation-algorithm)|`0xFFB2_0158`|160-bit lookup table (plus 2 extra bits), split across 6x 32-bit registers|
|[`DDR_COORD_TRANSLATE_COL_SWAP`](Coordinates.md#translation-algorithm)|`0xFFB2_0170`|All 32 bits have particular purpose|
|`DEBUG_COUNTER_RESET`|`0xFFB2_0174`||
|[`NIU_TRANS_COUNT_RTZ_CFG`](#niu_trans_count_rtz_cfg)|`0xFFB2_0178`|17 non-contiguous bits have particular purpose|
|[`NIU_TRANS_COUNT_RTZ_CLR`](#niu_trans_count_rtz_clr)|`0xFFB2_017C`|Zero bits of storage, writes instead clear bits of [`NIU_TRANS_COUNT_RTZ_SOURCE`](#niu_trans_count_rtz_source)|

### `NIU_CFG_0`

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|12|Reserved; software should preserve the values of these bits when modifying other bits|
|12|1|Tile clock disable; if set to `true`, then the tile attached to the NIU will be disabled (firmware will set this to `true` for fused-off tiles)|
|13|1|Double store disable; has no effect in Tensix tiles and Ethernet tiles, but if set to `true` in other types of tile, the tile will ignore the `NOC_PACKET_TAG_HEADER_STORE` flag|
|14|1|Coordinate translation enable; if set to `true`, various other registers [define a coordinate translation scheme](Coordinates.md#coordinate-translation)|
|15|1|AXI subordinate enable; only has an effect in DRAM tiles, where it switches the NoC-visible address space between being GDDR-based and being RISCV/L1-based|
|16|1|Request FIFO enable|
|17|15|Available for general use|

### `ROUTER_CFG_0`

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|19|Reserved; software should preserve the values of these bits when modifying other bits|
|19|13|Available for general use|

### `ROUTER_CFG_1`

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|17|Broadcast opt-out mask for columns|
|17|15|Available for general use|

Any given NIU will use one bit out of the first seventeen bits, based on its X coordinate. If that bit is set, then the NIU is opted-out from receiving broadcast packets. The same mask should be set at all NIUs (most of the time this is just a convenience for software, but at the PCI Express tile the entire mask needs to be accurate). Firmware will configure this mask such that only Tensix tiles receive broadcasts.

### `ROUTER_CFG_3`

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|12|Broadcast opt-out mask for rows|
|12|20|Available for general use|

Any given NIU will use one bit out of the first twelve bits, based on its Y coordinate. If that bit is set, then the NIU is opted-out from receiving broadcast packets. The same mask should be set at all NIUs (most of the time this is just a convenience for software, but at the PCI Express tile the entire mask needs to be accurate). Firmware will configure this mask such that only Tensix tiles receive broadcasts.

### `NOC_ID_LOGICAL`

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|6|NIU's X coordinate, in translated space|
|6|6|NIU's Y coordinate, in translated space|
|12|20|Available for general use|

Upon initial ASIC power-on, this register will contain the [X and Y coordinates](Coordinates.md) of the NIU, in NoC coordinate space (i.e. between `0` and `16` for X and between `0` and `11` for Y). When firmware configures the coordinate translation tables, firmware will also update this register to contain the preferred X and Y coordinates of the NIU [in translated space](Coordinates.md#coordinate-translation).

### `NIU_TRANS_COUNT_RTZ_CFG`

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|16|`NIU_TRANS_COUNT_RTZ_CFG_INT_ENABLE`|Bitmask of which [`NIU_TRANS_COUNT_RTZ_SOURCE`](#niu_trans_count_rtz_source) bits cause an IRQ (and hence, if enabled at the [PIC](../TensixTile/PIC.md), an interrupt). Bit `i` relates to bit `i` of `NIU_TRANS_COUNT_RTZ_SOURCE`, which relates to the `NIU_MST_REQS_OUTSTANDING_ID(i)` [counter](Counters.md).|
|16|12|Reserved|
|28|1|`NIU_TRANS_COUNT_RTZ_CFG_RC_DISABLE`|Controls the semantics of reading from [`NIU_TRANS_COUNT_RTZ_NUM`](#niu_trans_count_rtz_num).|
|29|3|Reserved|

### `NIU_TRANS_COUNT_RTZ_CLR`

Writing the value `X` to `NIU_TRANS_COUNT_RTZ_CLR` atomically performs `NIU_TRANS_COUNT_RTZ_SOURCE &= ~X`. In particular, software can clear [`NIU_TRANS_COUNT_RTZ_SOURCE`](#niu_trans_count_rtz_source) by reading from `NIU_TRANS_COUNT_RTZ_SOURCE` and then immediately writing the returned value to `NIU_TRANS_COUNT_RTZ_CLR`.

Reading from `NIU_TRANS_COUNT_RTZ_CLR` always returns zero.

## Interrupt status

Two read-only registers in the memory map are useful for handling [NIU interrupts](Interrupts.md). They are closely related to the read/write [`NIU_TRANS_COUNT_RTZ_CFG`](#niu_trans_count_rtz_cfg) register and the write-only [`NIU_TRANS_COUNT_RTZ_CLR`](#niu_trans_count_rtz_clr) register which live together elsewhere in the memory map.

|Name|Example Address|Purpose|
|---|---|---|
|[`NIU_TRANS_COUNT_RTZ_NUM`](#niu_trans_count_rtz_num)|`0xFFB2_0378`|Index of which counter caused an interrupt|
|[`NIU_TRANS_COUNT_RTZ_SOURCE`](#niu_trans_count_rtz_source)|`0xFFB2_037C`|Bitmask of which `NIU_MST_REQS_OUTSTANDING_ID` [counters](Counters.md) have had a positive-to-zero transition (bits are sticky until explicitly cleared)|

### `NIU_TRANS_COUNT_RTZ_SOURCE`

Writing to `NIU_TRANS_COUNT_RTZ_SOURCE` has no effect. Instead, hardware will set bit `i` of `NIU_TRANS_COUNT_RTZ_SOURCE` whenever the `NIU_MST_REQS_OUTSTANDING_ID(i)` [counter](Counters.md) changes from positive to zero. Regardless of what subsequently happens to `NIU_MST_REQS_OUTSTANDING_ID(i)`, bit `i` will remain set until software clears it, which it can do by either:
* Writing to [`NIU_TRANS_COUNT_RTZ_CLR`](#niu_trans_count_rtz_clr)
* Reading from `NIU_TRANS_COUNT_RTZ_NUM` (when the `NIU_TRANS_COUNT_RTZ_CFG_RC_DISABLE` bit of [`NIU_TRANS_COUNT_RTZ_CFG`](#niu_trans_count_rtz_cfg) is clear)

If `NIU_TRANS_COUNT_RTZ_SOURCE & NIU_TRANS_COUNT_RTZ_CFG_INT_ENABLE` is non-zero, the [PIC](../TensixTile/PIC.md)'s NoC NIU IRQ will be raised. See [NIU Interrupts](Interrupts.md) for a step-by-step walkthrough of setting this up.

### `NIU_TRANS_COUNT_RTZ_NUM`

If `NIU_TRANS_COUNT_RTZ_SOURCE & NIU_TRANS_COUNT_RTZ_CFG_INT_ENABLE` is non-zero, reading from `NIU_TRANS_COUNT_RTZ_NUM` will return the index of one of the bits set in that value. Otherwise, reading from `NIU_TRANS_COUNT_RTZ_NUM` will return zero.

Reading from `NIU_TRANS_COUNT_RTZ_NUM` triggers an additional side effect:
* If the `NIU_TRANS_COUNT_RTZ_CFG_RC_DISABLE` bit of [`NIU_TRANS_COUNT_RTZ_CFG`](#niu_trans_count_rtz_cfg) is clear: the bit in [`NIU_TRANS_COUNT_RTZ_SOURCE`](#niu_trans_count_rtz_source) corresponding to the returned value will be cleared.
* If the `NIU_TRANS_COUNT_RTZ_CFG_RC_DISABLE` bit of [`NIU_TRANS_COUNT_RTZ_CFG`](#niu_trans_count_rtz_cfg) is set: the bit in [`NIU_TRANS_COUNT_RTZ_SOURCE`](#niu_trans_count_rtz_source) corresponding to the returned value will be left unchanged, but the next read from `NIU_TRANS_COUNT_RTZ_NUM` might return a different bit index.

Writing to `NIU_TRANS_COUNT_RTZ_NUM` has no effect.
