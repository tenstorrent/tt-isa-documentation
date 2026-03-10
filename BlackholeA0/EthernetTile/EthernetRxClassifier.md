# Ethernet RX Classifier

All incoming frames are subjected to the same seven-stage pipeline:
1. [Buffer an entire incoming frame](#1-buffer-an-entire-incoming-frame), so that its length can be determined and its Ethernet CRC checked.
2. [Optionally drop malformed frames](#2-optionally-drop-malformed-frames).
3. [Extract some headers from the frame, and augment them slightly](#3-extract-some-headers-from-the-frame-and-augment-them-slightly).
4. [Use a TCAM to match against the augmented headers, the result of which is a flow table index](#4-use-a-tcam-to-match-against-the-augmented-headers-the-result-of-which-is-a-flow-table-index).
5. [Load the appropriate row from the flow table](#5-load-the-appropriate-row-from-the-flow-table).
6. [Based on the contents of the flow table row, either](#6-based-on-the-contents-of-the-flow-table-row-either-): drop the frame, remove VLAN tags and IP/UDP headers from the frame, prepend some metadata at the start of the frame, or pass the frame through unchanged.
7. [Decide which RX queue to deliver the frame to](#7-decide-which-rx-queue-to-deliver-the-frame-to).

Frames which survive all seven stages will be delivered to the RX queue chosen by stage seven. If that queue is operating in TT-link mode, then stage 6 should have removed VLAN tags and IP/UDP headers, and the queue will interpret the remainder as a TT-link packet. If instead that queue is operating in raw mode, then it can optionally remove some bytes from the start of the frame before appending it to the configured buffer.

## 1. Buffer an entire incoming frame

Software has no control over this stage; it always happens.

## 2. Optionally drop malformed frames

All frames are assigned one of the following EOP codes:

|EOP Code|Default|Meaning|
|--:|---|---|
|0|Keep|No error, data packet|
|1|Keep|No error, 802.3x flow control packet|
|2|Keep|No error, 802.1Qbb priority flow control packet|
|3|Keep|No error, 802.3br verify packet|
|4|Keep|No error, 802.3br respond packet|
|5|Drop|Unsupported MAC control|
|6|Drop|Reserved|
|7|Drop|Reserved|
|8|Drop|Error, incorrect CRC|
|9|Drop|Error, fragment|
|10|Drop|Error, undersize|
|11|Drop|Error, jabber|
|12|Drop|Error, oversize|
|13|Drop|Error, SMD-C no context|
|14|Drop|Error, SMD-S sequence|
|15|Drop|Error, SMD-C sequence|
|16|Drop|Error, fragment count|
|17|Drop|Error, preamble size|
|18|Drop|Error, PCS decode|
|≥&nbsp;19|Drop|Reserved|

The `EOP_STATUS_GOOD_LO` register contains a bitmask, with one bit per EOP code. A value of `true` corresponds to "Keep", whereas a value of `false` corresponds to "Drop". The default value of `EOP_STATUS_GOOD_LO` is `0x1f`, corresponding to the "Default" column in the above table.

### `EOP_STATUS_GOOD_LO`

**Address:** `0xFFB9_8120`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|32|Bitmask|

## 3. Extract some headers from the frame, and augment them slightly

This stage starts by looking at the EtherType, and is able to recognise any of:

* IEEE 802.1ad VLAN tag, followed by IEEE 802.1Q VLAN tag, followed by arbitrary EtherType or length
* IEEE 802.1Q VLAN tag, followed by IEEE 802.1AE EtherType
* IEEE 802.1Q VLAN tag, followed by arbitrary EtherType (other than one of the cases above) or length
* IEEE 802.1AE EtherType
* Arbitrary EtherType (other than one of the cases above) or length

If an arbitrary EtherType or length is matched, then a tiny remapping step is performed:
* If the EtherType or length exactly equals the low 16 bits of `USER_DEFINED_ETHERTYPE[0]`, replace it with the high 16 bits of `USER_DEFINED_ETHERTYPE[0]`.
* Otherwise, if the EtherType or length exactly equals the low 16 bits of `USER_DEFINED_ETHERTYPE[1]`, replace it with the high 16 bits of `USER_DEFINED_ETHERTYPE[1]`.

The next part of the stage is extracting an S-Tag and a C-Tag:
* If the EtherType or length exactly equals the low 16 bits of `USER_DEFINED_VLAN_TAG[0]`, and that register specifies to perform tag replacement, the S-Tag comes from `USER_DEFINED_STAG[0]` and the C-Tag comes from `USER_DEFINED_CTAG[0]`.
* Otherwise, if the EtherType or length exactly equals the low 16 bits of `USER_DEFINED_VLAN_TAG[1]`, and that register specifies to perform tag replacement, the S-Tag comes from `USER_DEFINED_STAG[1]` and the C-Tag comes from `USER_DEFINED_CTAG[1]`.
* Otherwise, the S-Tag is the recognised IEEE 802.1ad VLAN tag (if any) and the C-Tag is the recognised IEEE 802.1Q VLAN tag (if any).

> [!IMPORTANT]
> The EtherType and S-Tag / C-Tag remapping only affects the subsequent decisions made by the classifier; it doesn't change the frame contents as eventually delivered to an RX queue.

The next part of the stage is extracting an L3 header:
* If the EtherType or length exactly equals the low 16 bits of `USER_DEFINED_L3_HDR[0]`, then the L3 header comes from: `USER_DEFINED_SRC_IP_ADDR[0]`, `USER_DEFINED_DST_IP_ADDR[0]`, and the high bits of `USER_DEFINED_L3_HDR[0]`.
* Otherwise, if the EtherType or length exactly equals the low 16 bits of `USER_DEFINED_L3_HDR[1]`, then the L3 header comes from: `USER_DEFINED_SRC_IP_ADDR[1]`, `USER_DEFINED_DST_IP_ADDR[1]`, and the high bits of `USER_DEFINED_L3_HDR[1]`.
* Otherwise, if the EtherType is IPv4, then the L3 header is an IPv4 header extracted from the Ethernet frame. Hardware only looks at the protocol, IHL, source address, and destination address fields - all other fields of the IPv4 header are ignored.
* Otherwise, if the EtherType is IPv6, then the L3 header is an IPv6 header extracted from the Ethernet frame. Hardware only looks at the next header, source address, and destination address fields - all other fields of the IPv6 header are ignored.
* Otherwise, the L3 header is considered absent.

The stage then diverges based on the three cases:
* L3 header present, and is IPv4.
* L3 header present, and is IPv6.
* L3 header absent (or present but neither of IPv4 or IPv6).

The simple case is the L3 header absent (or present but neither of IPv4 or IPv6). This will cause stage 4 to consider all the enabled "Not IP" rows of the TCAM, so all that remains for stage 3 to do is provide an augmented EtherType and augmented destination MAC address. In both cases, the augmentation comes from the first matching row in the following tables:

|EtherType or length|→|Augmentation for EtherType comes from|
|---|---|---|
|`USER_ETHERTYPE[0]`|→|`USER_REDUCED_ETHERTYPE[0]`|
|`USER_ETHERTYPE[1]`|→|`USER_REDUCED_ETHERTYPE[1]`|
|Less than `0x0600` (i.e. length)|→|`REDUCED_ETHERTYPE[0]`|
|`0x0800` (IPv4)|→|`REDUCED_ETHERTYPE[1]`|
|`0x86DD` (IPv6)|→|`REDUCED_ETHERTYPE[2]`|
|`0x0806` (ARP)|→|`REDUCED_ETHERTYPE[3]`|
|`0x8035` (RARP)|→|`REDUCED_ETHERTYPE[4]`|
|`0x0842` (IEEE 802 Wake-on-LAN)|→|`REDUCED_ETHERTYPE[5]`|
|`0x8902` (IEEE 802.1Q CFM PDU)|→|`REDUCED_ETHERTYPE[6]`|
|`0x22E7` (IEEE 802.1Q CNM)|→|`REDUCED_ETHERTYPE[7]`|
|`0x22E9` (IEEE 802.1Q CN-TAG)|→|`REDUCED_ETHERTYPE[8]`|
|`0x8940` (IEEE 802.1Q ECP)|→|`REDUCED_ETHERTYPE[9]`|
|`0x88F7` (PTP)|→|`REDUCED_ETHERTYPE[10]`|
|`0x888E` (IEEE 802.1X EAP over LAN)|→|`REDUCED_ETHERTYPE[11]`|
|`0x88CC` (LLDP)|→|`REDUCED_ETHERTYPE[12]`|
|`0x8915` (RoCE)|→|`REDUCED_ETHERTYPE[13]`|
|`0x88B7` (IEEE 802 OUI Extended EtherType)|→|`REDUCED_ETHERTYPE[14]`|
|Other|→|Zero|

|Destination MAC|→|Augmentation for destination MAC comes from|
|---|---|---|
|`USER_MAC_DA[0]`|→|`USER_REDUCED_DA[0]`|
|`USER_MAC_DA[1]`|→|`USER_REDUCED_DA[1]`|
|`01:80:C2:00:00:0E`|→|`REDUCED_DA[0]`|
|`01:80:C2:00:00:0?`|→|`REDUCED_DA[1]`|
|`01:80:C2:00:00:1?`|→|`REDUCED_DA[2]`|
|`01:80:C2:00:00:2?`|→|`REDUCED_DA[3]`|
|`01:80:C2:00:00:30`|→|`REDUCED_DA[4]`|
|`01:80:C2:??:??:??`|→|`REDUCED_DA[5]`|
|`01:1B:19:00:00:00`|→|`REDUCED_DA[6]`|
|Other|→|Zero|

If the L3 header is present and is IPv4, then stage 4 will consider all the enabled "IPv4" rows of the TCAM. Stage 3 therefore needs to provide the augmented protocol number, extract the source and destination ports, and provide the augmented source and destination ports. The augmentation for the protocol number comes from the first matching row in the following table:

|Protocol number|→|Augmentation for protocol number comes from|
|---|---|---|
|`USER_PROTOCOL[0]`|→|`USER_REDUCED_PROTOCOL[0]`|
|`USER_PROTOCOL[1]`|→|`USER_REDUCED_PROTOCOL[1]`|
|`0x01` (ICMP)|→|`REDUCED_PROTOCOL[0]`|
|`0x02` (IGMP)|→|`REDUCED_PROTOCOL[1]`|
|`0x06` (TCP)|→|`REDUCED_PROTOCOL[2]`|
|`0x11` (UDP)|→|`REDUCED_PROTOCOL[3]`|
|`0x3A` (IPv6-ICMP)|→|`REDUCED_PROTOCOL[4]`|
|Other|→|Zero|

Port numbers are more complex, as they require an L4 header. The logic for extracting an L4 header is:
* If the protocol number exactly equals the low 8 bits of `USER_DEFINED_L4_HDR_FIELDS[0]`, then the L4 header comes from: `USER_DEFINED_L4_HDR_PORT[0]` and some bits of `USER_DEFINED_L4_HDR_FIELDS[0]`.
* Otherwise, if the protocol number exactly equals the low 8 bits of `USER_DEFINED_L4_HDR_FIELDS[1]`, then the L4 header comes from: `USER_DEFINED_L4_HDR_PORT[1]` and some bits of `USER_DEFINED_L4_HDR_FIELDS[1]`.
* Otherwise, if the protocol number is UDP, then the L4 header is a UDP header extracted from the Ethernet frame. Hardware only looks at the source port and destination port fields - all other fields of the UDP header are ignored.
* Otherwise, if the protocol number is TCP, then the L4 header is a TCP header extracted from the Ethernet frame. Hardware only looks at the data offset, flags, source port, and destination port fields - all other fields of the TCP header are ignored.
* Otherwise, the L4 header is considered absent.

For the augmentation of port numbers, software can configure a table of 16 entries (`USER_PORT_REDUCTION_RULE[0]` and `USER_PORT_REDUCTION_PORT[0]` through `USER_PORT_REDUCTION_RULE[15]` and `USER_PORT_REDUCTION_PORT[15]`). Each entry applies to exactly one of UDP source port or UDP destination port or TCP source port or TCP destination port. The augmentation comes from the first matching table entry, or a value of zero if no entries match.

If the L3 header is present and is IPv6, then stage 4 will consider all the enabled "IPv6" rows of the TCAM. Stage 3 therefore needs to provide the augmented next header field, extract the source and destination ports, and provide the augmented source and destination ports. The augmentation for the next header field follows the augmentation logic for IPv4 protocol number, and the logic around port numbers is the same as for IPv4.

### `USER_DEFINED_ETHERTYPE[i]`

**Address:** `0xFFB9_C000 + i * 4` (for `0 ≤ i < 2`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|16|Input EtherType to recognise|
|16|16|Replacement EtherType|

### `USER_DEFINED_VLAN_TAG[i]`

**Address:** `0xFFB9_C400 + i * 4` (for `0 ≤ i < 2`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|16|Input EtherType to recognise|
|16|2|<ul><li><code>0</code>: Disable</li><li><code>1</code>: If EtherType matches, replace the C-Tag with `USER_DEFINED_CTAG[i]`</li><li><code>2</code>: Reserved</li><li><code>3</code>: If EtherType matches, replace the S-Tag with `USER_DEFINED_STAG[i]` and the C-Tag with `USER_DEFINED_CTAG[i]`</li></ul>|
|18|14|Reserved|

### `USER_DEFINED_STAG[i]`

**Address:** `0xFFB9_C408 + i * 4` (for `0 ≤ i < 2`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|32|Replacement S-Tag (this is 32 bits, i.e. the 802.1ad header, rather than just the 12 bits of VLAN ID)|

### `USER_DEFINED_CTAG[i]`

**Address:** `0xFFB9_C410 + i * 4` (for `0 ≤ i < 2`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|32|Replacement C-Tag (this is 32 bits, i.e. the complete 802.1Q header, rather than just the 12 bits of VLAN ID)|

### `USER_DEFINED_L3_HDR[i]`

**Address:** `0xFFB9_C418 + i * 4` (for `0 ≤ i < 2`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|16|Input EtherType to recognise|
|16|8|Replacement protocol or next header field (depending on the value in bits 24 through 26)|
|24|3|<ul><li><code>0</code>, <code>1</code>, <code>2</code>, <code>3</code>: Consider the L3 header to be absent</li><li><code>4</code>: Reserved</li><li><code>5</code>: Consider the L3 header to be present, treating it as an IPv4 header with protocol coming from bits 16 through 23 of this register, and source and destination addresses coming from `USER_DEFINED_SRC_IP_ADDR[i]` and `USER_DEFINED_DST_IP_ADDR[i]`</li><li><code>6</code>: Reserved</li><li><code>7</code>: Consider the L3 header to be present, treating it as an IPv6 header with next header field coming from bits 16 through 23 of this register, and source and destination addresses coming from `USER_DEFINED_SRC_IP_ADDR[i]` and `USER_DEFINED_DST_IP_ADDR[i]`</li></ul>|
|27|5|Reserved|

### `USER_DEFINED_SRC_IP_ADDR[i]`

**Address:** `0xFFB9_C420 + i * 4 + (3 - j) * 8` (for `0 ≤ i < 2` and `0 ≤ j < 4`)

IPv4 uses just `j == 0` to specify a 32-bit address, whereas IPv6 uses all four `j` values to specify a 128-bit address.

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|32|32 bits of IPv4 address, or 32 bits within an IPv6 address|

### `USER_DEFINED_DST_IP_ADDR[i]`

**Address:** `0xFFB9_C440 + i * 4 + (3 - j) * 8` (for `0 ≤ i < 2` and `0 ≤ j < 4`)

IPv4 uses just `j == 0` to specify a 32-bit address, whereas IPv6 uses all four `j` values to specify a 128-bit address.

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|32|32 bits of IPv4 address, or 32 bits within an IPv6 address|

### `USER_ETHERTYPE[i]`

**Address:** `0xFFB9_C840 + i * 4` (for `0 ≤ i < 2`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|16|Input EtherType to recognise|
|16|16|Reserved|

### `USER_REDUCED_ETHERTYPE[i]`

**Address:** `0xFFB9_C848 + i * 4` (for `0 ≤ i < 2`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|4|Augmentation value for EtherType (used when `USER_ETHERTYPE[i]` matches)|
|4|28|Reserved|

### `REDUCED_ETHERTYPE[i]`

**Address:** `0xFFB9_C850 + i * 4` (for `0 ≤ i < 15`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|4|Augmentation value for EtherType|
|4|28|Reserved|

### `USER_MAC_DA[i]`

**Address:** `0xFFB9_C800 + i * 8 + j * 4` (for `0 ≤ i < 2` and `0 ≤ j < 2`)

A 48-bit MAC address is specified using `j == 0` and the low 16 bits of `j == 1`.

### `USER_REDUCED_DA[i]`

**Address:** `0xFFB9_C810 + i * 4` (for `0 ≤ i < 2`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|4|Augmentation value for destination MAC address (used when `USER_MAC_DA[i]` matches)|
|4|28|Reserved|

### `REDUCED_DA[i]`

**Address:** `0xFFB9_C818 + i * 4` (for `0 ≤ i < 7`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|4|Augmentation value for destination MAC address|
|4|28|Reserved|

### `USER_PROTOCOL[i]`

**Address:** `0xFFB9_C8A0 + i * 4` (for `0 ≤ i < 2`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|8|Input protocol number (IPv4) or next header value (IPv6) to recognise|
|8|24|Reserved|

### `USER_REDUCED_PROTOCOL[i]`

**Address:** `0xFFB9_C8A8 + i * 4` (for `0 ≤ i < 2`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|4|Augmentation value for protocol number or next header value (used when `USER_PROTOCOL[i]` matches)|
|4|28|Reserved|

### `REDUCED_PROTOCOL[i]`

**Address:** `0xFFB9_C8B0 + i * 4` (for `0 ≤ i < 5`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|4|Augmentation value for protocol number or next header value|
|4|28|Reserved|

### `USER_DEFINED_L4_HDR_FIELDS[i]`

**Address:** `0xFFB9_C460 + i * 4` (for `0 ≤ i < 2`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|8|Input protocol number (IPv4) or next header value (IPv6) to recognise|
|8|1|If `true`, `USER_PORT_REDUCTION_RULE` entries for TCP will be applied|
|9|3|Reserved|
|12|1|If `true`, `USER_PORT_REDUCTION_RULE` entries for UDP will be applied|
|13|19|Reserved|

### `USER_DEFINED_L4_HDR_PORT[i]`

**Address:** `0xFFB9_C468 + i * 4` (for `0 ≤ i < 2`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|16|Destination port number|
|16|16|Source port number|

### `USER_PORT_REDUCTION_RULE[i]`

**Address:** `0xFFB9_C940 + i * 4` (for `0 ≤ i < 16`)

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|4|Augmentation value (to be used if rule applies and matches)|
|4|1|<ul><li><code>0</code>: Rule matches if <code>USER_PORT_REDUCTION_PORT[i].lo&nbsp;==&nbsp;port</code> or <code>port&nbsp;==&nbsp;USER_PORT_REDUCTION_PORT[i].hi</code></li><li><code>1</code>: Rule matches if <code>USER_PORT_REDUCTION_PORT[i].lo&nbsp;&lt;=&nbsp;port</code> and <code>port&nbsp;&lt;=&nbsp;USER_PORT_REDUCTION_PORT[i].hi</code></li></ul>|
|5|3|Reserved|
|8|1|<ul><li><code>0</code>: Rule applies to source port numbers</li><li><code>1</code>: Rule applies to destination port numbers</li></ul>|
|9|3|Reserved|
|12|1|<ul><li><code>0</code>: Rule applies to UDP</li><li><code>1</code>: Rule applies to TCP</li></ul>|
|13|19|Reserved|

### `USER_PORT_REDUCTION_PORT[i]`

**Address:** `0xFFB9_C900 + i * 4` (for `0 ≤ i < 16`)

|First&nbsp;bit|#&nbsp;Bits|Name|
|--:|--:|---|
|0|16|`lo`|
|16|16|`hi`|

## 4. Use a TCAM to match against the augmented headers, the result of which is a flow table index

The TCAM contains 64 rows, with each row capable of being one of the following kinds:
* **IPv4:** Can match on any/all of protocol number, augmented protocol number, IPv4 source address, IPv4 destination address, source port, augmented source port, destination port, augmented destination port.
* **IPv6:** Can match on any/all of next header field, augmented next header field, IPv6 source address, IPv6 destination address, source port, augmented source port, destination port, augmented destination port.
* **Not IP:** Can match on any/all of EtherType, augmented EtherType, source MAC address, destination MAC address, augmented destination MAC address, L2 priority (this being the PCP field from the outermost VLAN tag, or `0` if no VLAN tags present).

Each matchable field is specified as a combination of a mask and value; an incoming value from an Ethernet frame matches if `incoming_value | mask == value | mask`. In other words, whenever a bit within `mask` is set, that bit position becomes a "don't care" bit. This gives the "ternary" part of the TCAM, due to the three possible states per bit position:

|`mask`|`value`|Meaning|
|--:|--:|---|
|`0`|`0`|Bit of incoming value must be `0`|
|`0`|`1`|Bit of incoming value must be `1`|
|`1`|Any|Don't care about bit of incoming value|

In addition to the pattern to match on, all kinds of TCAM row have:
* Enable/disable (1 bit)
* Match priority (3 bits)
* Flow table index (6 bits)

A disabled TCAM row never matches anything. If multiple enabled TCAM rows match, then the match priority bits are used to resolve ties, with highest priority winning. If there are still ties, then the TCAM row index is used to resolve ties, with the lowest row index winning. If no enabled TCAM rows match, then the flow table index `64` is used (whereas if there is a match, the 6-bit index will be between `0` and `63` inclusive).

Different parts of the TCAM row are updated in different ways:
* The `TCAM_ROW_UPDATE` register is used to read or write "Enable/disable".
* The array of `TCAM_ROW_MAPPING[i]` registers are used to read or write "Match priority" and "Flow table index".
* The `TCAM_UPDATE` register is used to read or write the pattern match parts.
* The `TCAM_FLUSH` register is used to bulk write "Enable/disable" and the pattern match parts of all TCAM rows.

### `TCAM_ROW_UPDATE`

**Address:** `0xFFB9_CD40`

|First&nbsp;bit|#&nbsp;Bits|Name|
|--:|--:|---|
|0|6|`tcam_row_number`|
|6|2|Reserved|
|8|1|`enable`|
|9|7|Reserved|
|16|1|`write`|
|17|14|Reserved|
|31|1|`go`|

To enable or disable a TCAM row, software should perform a write to `TCAM_ROW_UPDATE` with `tcam_row_number` set to the desired row, `enable` set based on whether to enable that row, `write` set to `true`, and `go` set to `true`.

To query whether a TCAM row is enabled, software should perform a write to `TCAM_ROW_UPDATE` with `tcam_row_number` set to the desired row, `write` set to `false`, and `go` set to `true`. Hardware will populate `TCAM_ROW_STATUS` with the result.

### `TCAM_ROW_STATUS`

**Address:** `0xFFB9_CD44`

This register can only be changed by hardware, which can happen in response to software using `TCAM_ROW_UPDATE`.

|First&nbsp;bit|#&nbsp;Bits|Name|
|--:|--:|---|
|0|6|`tcam_row_number`|
|6|2|Reserved, always zero|
|8|1|`enable`|
|9|23|Reserved, always zero|

### `TCAM_ROW_MAPPING[i]`

**Address:** `0xFFB9_CC00 + i * 4` (for `0 ≤ i < 64`)

There is one 32-bit register per TCAM row, with simple read/write semantics.

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|3|Match priority (larger values win)|
|3|13|Reserved|
|16|6|Flow table index|
|22|10|Reserved|

### `TCAM_UPDATE`

**Address:** `0xFFB9_CDF0`

|First&nbsp;bit|#&nbsp;Bits|Name|
|--:|--:|---|
|0|6|`tcam_row_number`|
|6|2|Reserved|
|8|1|`mask`|
|9|1|`write`|
|10|1|`write_is_not_ip`|
|11|5|Reserved|
|16|1|`write_update_protocol`|
|17|1|`write_update_dst_port`|
|18|1|`write_update_src_port`|
|19|1|`write_update_destination_address`|
|20|1|`write_update_source_address`|
|21|1|`write_update_row_kind`|
|22|1|`write_update_ethertype`|
|23|1|`write_update_l2_priority`|
|24|7|Reserved|
|31|1|`go`|

To read the pattern match part of a TCAM row, software should perform a write to `TCAM_UPDATE` with:
* `tcam_row_number` set to the desired row
* `mask` to `true` if reading the mask bits, or to `false` if reading the value bits
* `write` set to `false`
* `go` set to `true`

In response, hardware will populate `TCAM_TUPLE_TYPE_READ` with the kind of the row, and then depending on the kind also populate:
* **IPv4:** `TCAM_PROTOCOL_READ`, `TCAM_SA_READ`, `TCAM_DA_READ`, `TCAM_SRC_PORT_READ`, `TCAM_DST_PORT_READ`
* **IPv6:** `TCAM_PROTOCOL_READ`, `TCAM_SA_READ`, `TCAM_DA_READ`, `TCAM_SRC_PORT_READ`, `TCAM_DST_PORT_READ`
* **Not IP:** `TCAM_ETHERTYPE_READ`, `TCAM_SA_READ`, `TCAM_DA_READ`, `TCAM_NON_IP_ADDR_FLAGS_READ`, `TCAM_PRIORITY_READ`

To write the pattern part of an IPv4 or IPv6 TCAM row, software should write to `TCAM_TUPLE_TYPE_WRITE`, `TCAM_PROTOCOL_WRITE`, `TCAM_SA_WRITE`, `TCAM_DA_WRITE`, `TCAM_SRC_PORT_WRITE`, and `TCAM_DST_PORT_WRITE`, and then perform a write to `TCAM_UPDATE` with:
* `tcam_row_number` set to the desired row
* `mask` to `true` if writing the mask bits, or to `false` if writing the value bits
* `write` set to `true`
* `write_is_not_ip` set to `false`
* `write_update_row_kind` set to `true` (c.f. `TCAM_TUPLE_TYPE_WRITE`)
* `write_update_protocol` set to `true` (c.f. `TCAM_PROTOCOL_WRITE`)
* `write_update_source_address` set to `true` (c.f. `TCAM_SA_WRITE`)
* `write_update_destination_address` set to `true` (c.f. `TCAM_DA_WRITE`)
* `write_update_src_port` set to `true` (c.f. `TCAM_SRC_PORT_WRITE`)
* `write_update_dst_port` set to `true` (c.f. `TCAM_DST_PORT_WRITE`)
* `go` set to `true`

To write the pattern part of a Not IP TCAM row, software should write to `TCAM_TUPLE_TYPE_WRITE`, `TCAM_ETHERTYPE_WRITE`, `TCAM_SA_WRITE`, `TCAM_DA_WRITE`, `TCAM_NON_IP_ADDR_FLAGS_WRITE`, and `TCAM_PRIORITY_WRITE`, and then perform a write to `TCAM_UPDATE` with:
* `tcam_row_number` set to the desired row
* `mask` to `true` if writing the mask bits, or to `false` if writing the value bits
* `write` set to `true`
* `write_is_not_ip` set to `true`
* `write_update_row_kind` set to `true` (c.f. `TCAM_TUPLE_TYPE_WRITE`)
* `write_update_ethertype` set to `true` (c.f. `TCAM_ETHERTYPE_WRITE`)
* `write_update_source_address` set to `true` (c.f. `TCAM_SA_WRITE` and `TCAM_NON_IP_ADDR_FLAGS_WRITE`)
* `write_update_destination_address` set to `true` (c.f. `TCAM_DA_WRITE` and `TCAM_NON_IP_ADDR_FLAGS_WRITE`)
* `write_update_l2_priority` set to `true` (c.f. `TCAM_PRIORITY_WRITE`)
* `go` set to `true`

Partial writes are also supported: if one of the various `write_update_X` fields is instead set to `false`, then that part of the TCAM row is left unchanged, rather than having its value set to the contents of `TCAM_X_WRITE`.

### `TCAM_TUPLE_TYPE_READ`

**Address:** `0xFFB9_CE00`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|2|<ul><li><code>0</code>: Not IP</li><li><code>1</code>: IPv4</li><li><code>2</code>: Reserved</li><li><code>3</code>: IPv6</li></ul>|
|2|30|Reserved|

### `TCAM_TUPLE_TYPE_WRITE`

**Address:** `0xFFB9_CD80`

The bit layout of this register is the same as `TCAM_TUPLE_TYPE_READ`.

### `TCAM_PROTOCOL_READ`

**Address:** `0xFFB9_CE4C`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|8|IPv4 protocol value or IPv6 next header value|
|8|8|Reserved|
|16|4|Augmented protocol value|
|20|12|Reserved|

### `TCAM_PROTOCOL_WRITE`

**Address:** `0xFFB9_CDBC`

The bit layout of this register is the same as `TCAM_PROTOCOL_READ`.

### `TCAM_ETHERTYPE_READ`

**Address:** `0xFFB9_CE50`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|16|EtherType value|
|16|4|Augmented EtherType value|
|20|12|Reserved|

### `TCAM_ETHERTYPE_WRITE`

**Address:** `0xFFB9_CDC0`

The bit layout of this register is the same as `TCAM_ETHERTYPE_READ`.

### `TCAM_SA_READ`

**Addresses:** `0xFFB9_CE10`, `0xFFB9_CE14`, `0xFFB9_CE18`, `0xFFB9_CE1C`

IPv4 rows use the first four bytes for an IPv4 source address. Not IP rows use the first six bytes for a source MAC address. IPv6 rows use all sixteen bytes for an IPv6 source address.

### `TCAM_SA_WRITE`

**Addresses:** `0xFFB9_CD90`, `0xFFB9_CD94`, `0xFFB9_CD98`, `0xFFB9_CD9C`

The bit layouts of these registers are the same as `TCAM_SA_READ`.

### `TCAM_DA_READ`

**Addresses:** `0xFFB9_CE20`, `0xFFB9_CE24`, `0xFFB9_CE28`, `0xFFB9_CE2C`

IPv4 rows use the first four bytes for an IPv4 destination address. Not IP rows use the first six bytes for a destination MAC address. IPv6 rows use all sixteen bytes for an IPv6 destination address.

### `TCAM_DA_WRITE`

**Addresses:** `0xFFB9_CDA0`, `0xFFB9_CDA4`, `0xFFB9_CDA8`, `0xFFB9_CDAC`

The bit layouts of these registers are the same as `TCAM_DA_READ`.

### `TCAM_NON_IP_ADDR_FLAGS_READ`

**Address:** `0xFFB9_CE30`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|4|Augmented destination MAC address value|
|4|12|Reserved|
|16|4|In theory, augmented source MAC address value, but the source MAC address is never augmented, so this should always be zero or "don't care"|
|20|12|Reserved|

### `TCAM_NON_IP_ADDR_FLAGS_WRITE`

**Address:** `0xFFB9_CDB0`

The bit layout of this register is the same as `TCAM_NON_IP_ADDR_FLAGS_READ`.

### `TCAM_SRC_PORT_READ`

**Address:** `0xFFB9_CE34`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|16|Source port value|
|16|4|Augmented source port value|
|20|12|Reserved|

### `TCAM_SRC_PORT_WRITE`

**Address:** `0xFFB9_CDB4`

The bit layout of this register is the same as `TCAM_SRC_PORT_READ`.

### `TCAM_DST_PORT_READ`

**Address:** `0xFFB9_CE48`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|16|Destination port value|
|16|4|Augmented destination port value|
|20|12|Reserved|

### `TCAM_DST_PORT_WRITE`

**Address:** `0xFFB9_CDB8`

The bit layout of this register is the same as `TCAM_DST_PORT_READ`.

### `TCAM_PRIORITY_READ`

**Address:** `0xFFB9_CE54`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|3|VLAN tag PCP value|
|3|29|Reserved|

### `TCAM_PRIORITY_WRITE`

**Address:** `0xFFB9_CDC4`

The bit layout of this register is the same as `TCAM_PRIORITY_READ`.

### `TCAM_FLUSH`

**Address:** `0xFFB9_CD60`

Writing `1` to this register causes all TCAM rows to become disabled, and all pattern match mask and value bits to be set to `1` (the meaning of which is "don't care").

## 5. Load the appropriate row from the flow table

The flow table contains 65 rows, with each row consisting of:
* `ACTIONS`: Specifies whether to drop the frame, remove VLAN tags and IP/UDP headers from the frame, prepend some metadata at the start of the frame, or pass the frame through unchanged. Also specifies an RX queue number, and whether to record the frame's RX timestamp in a separate small FIFO.
* `VLAN`: Optionally require that frames have particular S-TAG or C-TAG VLAN tags, dropping them upon mismatch.
* `LABELS`: Optionally specify a set of counters / statistics to consult as part of the drop decision, and to update based on the incoming frame regardless of drop decision.
* `SW_METADATA`: Arbitrary 32-bit "software metadata" value which can optionally be prepended to the frame.

The `FTABLE_UPDATE` register is used to read/write rows `0` through `63`, and then row `64` is accessed separately through the `NO_MATCH_ACTIONS`, `NO_MATCH_VLAN`, `NO_MATCH_LABELS`, and `NO_MATCH_SW_METADATA` registers.

### `NO_MATCH_ACTIONS`

**Address:** `0xFFB9_CD04`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|2|RX queue number (used when [`MAC_RX_ROUTING`](#mac_rx_routing) is `2`, no effect on choice of RX queue otherwise)|
|2|1|Whether to drop the frame|
|3|1|Whether to remove VLAN tags and IP/UDP headers from the frame (this is intended for RX queues operating in TT-link mode)|
|4|1|Whether to record the frame's RX timestamp in a separate small FIFO (use of this FIFO is not yet documented, so software should set this field to `false` to disable the functionality)|
|5|1|Whether to byte-swap `SW_METADATA` and then prepend it to the frame (this is intended for RX queues operating in raw mode)|
|6|1|Whether to byte-swap 32 bits of hardware metadata and then prepend it to the frame (this is intended for RX queues operating in raw mode)|
|7|25|Reserved|

Removal of VLAN tags and IP/UDP headers cannot be combined with metadata prepending: _either_ removal can be done, _or_ prepending can be done, but not both. If prepending _both_ `SW_METADATA` and hardware metadata, then `SW_METADATA` comes first: the frame as delivered to the RX queue will consist of `SW_METADATA` (32 bits), followed by the hardware metadata (another 32 bits), followed by the MAC addresses, followed by the remainder of the Ethernet frame.

If prepending hardware metadata, the prepended 32 bits come from the following table. The table describes things as if the byte order was little endian, but it is actually prepended in big endian byte order, so software needs to perform a byte-swap to restore it to the described order:

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|14|Frame length, in bytes (does not include the length of any prepended metadata)|
|14|5|[EOP code](#2-optionally-drop-malformed-frames), as computed in stage 2|
|19|1|Reserved, always zero|
|20|2|Copy of "RX queue number" bits from flow table `ACTIONS` (even if [`MAC_RX_ROUTING`](#7-decide-which-rx-queue-to-deliver-the-frame-to) subsequently causes delivery to a different RX queue)|
|22|1|Copy of "Whether to record the frame's RX timestamp in a separate small FIFO" bit from flow table `ACTIONS`|
|23|1|Reserved, always zero|
|24|5|Copy of low five bits from flow table `LABELS`|
|29|3|Reserved, always zero|

### `NO_MATCH_VLAN`

**Address:** `0xFFB9_CD08`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|12|C-Tag value|
|12|3|Reserved|
|15|1|If `true`, frames must have an IEEE 802.1Q VLAN tag whose VLAN identifier equals the given C-Tag value, and will be dropped if such a VLAN tag is not present or if the VLAN identifier therein differs from the given C-Tag value|
|16|12|S-Tag value|
|28|3|Reserved|
|31|1|If `true`, frames must have an IEEE 802.1ad VLAN tag whose VLAN identifier equals the given S-Tag value, and will be dropped if such a VLAN tag is not present or if the VLAN identifier therein differs from the given S-Tag value|

### `NO_MATCH_LABELS`

**Address:** `0xFFB9_CD00`

This is not yet documented; software should set the value to zero to disable the relevant functionality.

### `NO_MATCH_SW_METADATA`

**Address:** `0xFFB9_CD0C`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|32|Arbitrary value provided by software|

### `FTABLE_UPDATE`

**Address:** `0xFFB9_CEA0`

|First&nbsp;bit|#&nbsp;Bits|Name|
|--:|--:|---|
|0|6|`flow_table_row_number`|
|6|2|Reserved|
|8|1|`write`|
|9|22|Reserved|
|31|1|`go`|

To write a flow table row, software should write to all of `FTABLE_ACTIONS`, `FTABLE_VLAN`, `FTABLE_LABELS`, and `FTABLE_SW_METADATA`, and then perform a write to `FTABLE_UPDATE` with `flow_table_row_number` set to the desired row, `write` set to `true`, and `go` set to `true`.

To read a flow table row, software should perform a write to `FTABLE_UPDATE` with `flow_table_row_number` set to the desired row, `write` set to `false`, and `go` set to `true`. Hardware will populate `FTABLE_ACTIONS`, `FTABLE_VLAN`, `FTABLE_LABELS`, and `FTABLE_SW_METADATA` with the result.

### `FTABLE_ACTIONS`

**Address:** `0xFFB9_CE84`

The bit layout of this register is the same as [`NO_MATCH_ACTIONS`](#no_match_actions). Hardware reads from or writes to this register when software writes to [`FTABLE_UPDATE`](#ftable_update) with `go` set to `true`.

### `FTABLE_VLAN`

**Address:** `0xFFB9_CE88`

The bit layout of this register is the same as [`NO_MATCH_VLAN`](#no_match_vlan). Hardware reads from or writes to this register when software writes to [`FTABLE_UPDATE`](#ftable_update) with `go` set to `true`.

### `FTABLE_LABELS`

**Address:** `0xFFB9_CE80`

The bit layout of this register is the same as [`NO_MATCH_LABELS`](#no_match_labels). Hardware reads from or writes to this register when software writes to [`FTABLE_UPDATE`](#ftable_update) with `go` set to `true`.

### `FTABLE_SW_METADATA`

**Address:** `0xFFB9_CE8C`

The bit layout of this register is the same as [`NO_MATCH_SW_METADATA`](#no_match_sw_metadata). Hardware reads from or writes to this register when software writes to [`FTABLE_UPDATE`](#ftable_update) with `go` set to `true`.

## 6. Based on the contents of the flow table row, either ...

If the [header extraction phase](#3-extract-some-headers-from-the-frame-and-augment-them-slightly) encountered an unsupported kind of IPv4 or IPv6 or TCP header, `HEADER_ERROR_CONTROL` is used to make the keep/drop decision. In this case, if keeping the frame, some of flow table `ACTIONS` is ignored: removal of VLAN tags and IP/UDP headers is never done, nor is prepending of metadata ever done.

Otherwise, if `OVERRIDE_DECISION == 0`, the frame will be kept.

Otherwise, the frame will be dropped if any of:
* `OVERRIDE_DECISION == 1`.
* Flow table `ACTIONS` indicates drop.
* Flow table `VLAN` indicates that certain VLAN tags are required, and those tags are not present.
* Flow table `LABELS` identifies a set of counters / statistics, and those counters have tripped past their drop threshold.

### `HEADER_ERROR_CONTROL`

**Address:** `0xFFB9_D004`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|1|Whether to keep IPv4 frames with `IHL != 5`|
|1|1|Whether to keep IPv6 frames with `next_header in {0, 43, 44, 50, 51, 60, 135, 139, 140, 253, 254}`|
|2|1|Whether to keep TCP frames with `data_offset != 5`|
|3|29|Reserved|

By default, all bits in `HEADER_ERROR_CONTROL` are cleared, meaning that these problematic cases will be dropped.

### `OVERRIDE_DECISION`

**Address:** `0xFFB9_D000`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|2|<ul><li><code>0</code>: Do not drop any frames due to flow table semantics (flow table `ACTIONS` still provides the decision of whether to remove VLAN tags and IP/UDP headers, whether to prepend any metadata, and whether to keep a timestamp, and flow table `LABELS` can still reference a set of counters / statistics to _update_)</li><li><code>1</code>: Drop all incoming frames</li><li><code>2</code>: Use normal flow table semantics to decide whether to drop frames</li><li><code>3</code>: Reserved</li></ul>|
|2|30|Reserved|

The default value of this register is `0`; software should set it to `2` if it wants to use the flow table to drop frames.

## 7. Decide which RX queue to deliver the frame to

The `MAC_RX_ROUTING` register controls how to make the decision.

### `MAC_RX_ROUTING`

**Address:** `0xFFB9_8150`

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|2|<ul><li><code>0</code>: Use the `MAC_RX_ADDR_ROUTING` register to decide the RX queue number</li><li><code>1</code>: Reserved</li><li><code>2</code>: Use flow table `ACTIONS` to decide the RX queue number</li><li><code>3</code>: Reserved</li></ul>|
|2|30|Reserved|

### `MAC_RX_ADDR_ROUTING`

**Address:** `0xFFB9_8154`

When `MAC_RX_ADDR_ROUTING` is used, the first six bytes of the frame are treated as a MAC address, which is then classified as one of:
* Broadcast (`FF:FF:FF:FF:FF:FF`)
* Multicast (not broadcast, but least significant bit of first octet is set)
* Unicast (anything else)

Provided that the RX classifier did not prepend any metadata, the first six bytes of the frame will be the destination MAC address.

In addition, bit #216 of the frame is consulted: the frame is considered MMIO-style if the bit is set, or data-style if it is clear. Provided that the frame is a TT-link frame, this bit identifies TT-link MMIO write packets.

These two pieces of information then control which bits within `MAC_RX_ADDR_ROUTING` provide the RX queue number:

|First&nbsp;bit|#&nbsp;Bits|Purpose|
|--:|--:|---|
|0|2|RX queue number for broadcast, data-style|
|2|2|RX queue number for broadcast, MMIO-style|
|4|2|RX queue number for multicast, data-style|
|6|2|RX queue number for multicast, MMIO-style|
|8|2|RX queue number for unicast, data-style|
|10|2|RX queue number for unicast, MMIO-style|
|12|24|Reserved|
