# Debug Daisychain

The debug daisychain can be used to present various internal signals from the Tensix tile, in groups of 128 bits. Most of these signals relate to internal implementation details of the Wormhole chip and are only meaningful to Tenstorrent engineers, but some of the signals are potentially useful to customers building a low level debugger, and those are described here.

## `RISCV_DEBUG_REG_DBG_BUS_CNTL_REG`

Software writes to this register to control the debug daisychain.

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|16|`SignalSel`|In combination with `DaisySel`, selects which 128 bits of debug data to present on the debug daisychain.|
|16|8|`DaisySel`|In combination with `SignalSel`, selects which 128 bits of debug data to present on the debug daisychain.|
|24|1|Reserved||
|25|2|`Read32Sel`|Selects which 32-bits of the 128-bit debug data are presented in `RISCV_DEBUG_REG_DBG_RD_DATA`: `0` for bits 0 through 31, `1` for bits 32 through 63, `2` for bits 64 through 95, `3` for bits 96 through 127.|
|27|2|Reserved||
|29|1|`Enabled`|Must be set to `true` to use the debug daisychain. Should be set to `false` at all other times to conserve power.|
|30|2|Reserved||

After changing the values in `Enabled` or `DaisySel` or `SignalSel`, software should wait at least five cycles before trying to obtain data from the debug daisychain. Software should also expect that any data obtained from the debug daisychain is at least five cycles stale. Data can be obtained in one of three ways:
* Software can read 32 bits by reading from `RISCV_DEBUG_REG_DBG_RD_DATA`.
* Software can instruct the daisychain to write 128 bits to an aligned address in the low 1 MiB of L1.
* Software can instruct the daisychain to sample 128 bits every N cycles and write the samples out to consecutive aligned addresses in the low 1 MiB of L1.

## `RISCV_DEBUG_REG_DBG_RD_DATA`

Once the `Enabled`, `DaisySel`, and `SignalSel` fields of `RISCV_DEBUG_REG_DBG_BUS_CNTL_REG` have been set to select a group of 128 bits to present on the debug daisychain, and software has waited at least five cycles, that data is continuously available on `RISCV_DEBUG_REG_DBG_RD_DATA` for software to read. As `RISCV_DEBUG_REG_DBG_RD_DATA` is only 32 bits wide, the `Read32Sel` field of `RISCV_DEBUG_REG_DBG_BUS_CNTL_REG` controls which 32 bits of the 128 bits are presented on `RISCV_DEBUG_REG_DBG_RD_DATA`. Software does not need to wait five cycles after changing `Read32Sel`. As the data on the daisychain can be continuously changing, software should not expect to be able to perform a consistent read of 128 bits by cycling through `Read32Sel` - software needs to instruct the daisychain to write out to L1 if it wants all 128 bits to come from the same point in time.

If a RISCV core is writing to `RISCV_DEBUG_REG_DBG_BUS_CNTL_REG` and then reading from `RISCV_DEBUG_REG_DBG_RD_DATA`, then the programmer should be aware of [RISCV memory ordering](BabyRISCV/MemoryOrdering.md), and the programmer needs to ensure that the write-request to `RISCV_DEBUG_REG_DBG_BUS_CNTL_REG` is emitted before the read-request from `RISCV_DEBUG_REG_DBG_RD_DATA`. One possible safe instruction sequence is:
```
sw t1, 0(t0) # Store to RISCV_DEBUG_REG_DBG_BUS_CNTL_REG
sw x0, 0(t2) # Store to RISCV_DEBUG_REG_DBG_RD_DATA (just for ordering, the value will be discarded)
sw x0, 0(t2) # Store to RISCV_DEBUG_REG_DBG_RD_DATA (just for ordering, the value will be discarded)
lw t3, 0(t2) # Load from RISCV_DEBUG_REG_DBG_RD_DATA
```

## `RISCV_DEBUG_REG_DBG_L1_MEM_REG2`

Once the `Enabled`, `DaisySel`, and `SignalSel` fields of `RISCV_DEBUG_REG_DBG_BUS_CNTL_REG` have been set to select a group of 128 bits to present on the debug daisychain, and software has waited at least five cycles, software can instruct the daisychain to write 128 bits out to an aligned address in the low 1 MiB of L1. This is controlled using `RISCV_DEBUG_REG_DBG_L1_MEM_REG2`:

|First&nbsp;bit|#&nbsp;Bits|Name|
|--:|--:|---|
|0|4|`WriteMode`|
|4|8|`SamplingInterval`|
|12|1|`WriteTrigger`|
|13|19|Reserved|

To prepare the daisychain for writing 128 bits out to L1, software should:
1. Write to `RISCV_DEBUG_REG_DBG_L1_MEM_REG2` with `WriteMode == 0xf` and other fields zero.
2. Write `x >> 4` to `RISCV_DEBUG_REG_DBG_L1_MEM_REG0`, where `x` is the byte-address in L1 it wishes the daisychain to write to.
3. Write to `RISCV_DEBUG_REG_DBG_L1_MEM_REG2` with `WriteMode == 0` or `WriteMode == 1`, and other fields zero.

Once prepared, to instruct the daisychain to write 128 bits to L1, software should:
1. Write to `RISCV_DEBUG_REG_DBG_L1_MEM_REG2`, changing `WriteTrigger` from `false` to `true`, leaving all other fields constant. This transition will trigger a write event. The write event will normally happen instantly, but in the case of extreme contention on L1, it could take up to 200 cycles.
2. Write to `RISCV_DEBUG_REG_DBG_L1_MEM_REG2`, changing `WriteTrigger` from `true` to `false`, leaving all other fields constant. This is in preparation for next write. If `WriteMode == 0`, then the next write will be to same address `x`, whereas if `WriteMode == 1`, then the next write will be to 16 bytes after the previous write.

To get a series of regular samples of 128 bits written out to L1, software should:
1. Write to `RISCV_DEBUG_REG_DBG_L1_MEM_REG2` with `WriteMode == 0xf` and other fields zero.
2. Write `x >> 4` to `RISCV_DEBUG_REG_DBG_L1_MEM_REG0`, where `x` is the byte-address in L1 it wishes the daisychain to start writing to.
3. Write `(x >> 4) + c` to `RISCV_DEBUG_REG_DBG_L1_MEM_REG1`, where `c` is the number of samples software wishes to take.
4. Write to `RISCV_DEBUG_REG_DBG_L1_MEM_REG2` with `WriteMode == 4`, `SamplingInterval` set to `N - 1` to get a sample every `N` cycles, and `WriteTrigger == true`. Due to a hardware bug, if `N == 1`, hardware _might_ take one more sample than requested, so software is advised to use `N ≥ 2`. This bug notwithstanding, hardware will take `c` samples total. It will try to take a sample every `N` cycles: if the L1 write interface is available when it wants to take a sample, then a sample will be taken at that time, and if not, it'll try again in `N` cycles time. If L1 is busy when it wants to take a sample, it'll still take `c` samples total, but the samples will not be from equally-spaced points in time.

# Available data

## RISCV execution state

Set `DaisySel == 7` and set `SignalSel` according to the desired RISCV and desired group of bits:

|`SignalSel`|Group A|Group B|Group C|Group D|
|---|--:|--:|--:|--:|
|**RISCV B**|`10`|`11`|`1`|N/A|
|**RISCV T0**|`12`|`13`|`18`|`19`|
|**RISCV T1**|`14`|`15`|`20`|`21`|
|**RISCV T2**|`16`|`17`|`22`|`23`|
|**RISCV NC**|`24`|`25`|N/A|N/A|
|**RISCV E**|`18`|`19`|N/A|N/A|

### Group A:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|31|If the Load/Store Unit's retire-order queue contains at least one instruction, the low 31 bits of the `pc` of the instruction that will retire next. Guaranteed to be valid when bit 31 is set, and might be valid at other times too. If the queue is empty, these bits instead come from _some_ recent `pc`.|
|31|1|`true` if the Load/Store Unit's retire-order queue contains at least one instruction, and the instruction that will retire next [meets the requirements for leaving the Load/Store Unit](BabyRISCV/MemoryOrdering.md#mechanical-description), `false` otherwise.|
|32|30|If the Load/Store Unit is currently trying to emit a memory read-request or write-request, the low 30 bits of the address in the request about to be emitted. Guaranteed to be valid when bit 62 or 63 is set. Note that this tells you nothing about any requests already in-flight within the memory subsystem.|
|62|1|`true` if the Load/Store Unit is currently trying to emit a memory read-request, `false` otherwise|
|63|1|`true` if the Load/Store Unit is currently trying to emit a memory write-request, `false` otherwise|
|64|30|The low 30 bits of the `pc` that the frontend wants to fetch next|
|94|2|Reserved|
|96|31|If an instruction has just been fetched, the low 31 bits of that instruction. Guaranteed to be valid when bit 127 is set.|
|127|1|`true` if an instruction has just been fetched, `false` otherwise|

### Group B:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|32|Reserved|
|32|30|If an instruction is entering instruction decode (the final stage of the frontend), the low 30 bits of the `pc` of that instruction. Guaranteed to be valid when bit 63 or 103 is set. If bit 103 is not set, these bits instead come from _some_ recent `pc`.|
|62|1|Reserved|
|63|1|`true` if an instruction is entering instruction decode (the final stage of the frontend) and that instruction [meets the requirements for entering the Integer Unit](BabyRISCV/MemoryOrdering.md#mechanical-description), `false` otherwise.|
|64|39|Reserved|
|103|1|`true` if an instruction is entering instruction decode (the final stage of the frontend), `false` otherwise|
|104|24|Reserved|

### Group C, RISCV B bit positions:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|94|Reserved|
|94|17|The low 17 bits of the most recent response of a read-request against the mailbox from RISCV B to RISCV B|
|111|4|Reserved|
|115|1|`false` if RISCV B is trying to read from the mailbox from RISCV B to RISCV B and the mailbox is empty, `true` otherwise|
|116|1|`false` if RISCV T0 is trying to read from the mailbox from RISCV B to RISCV T0 and said mailbox is empty, `true` otherwise|
|117|1|`false` if RISCV T1 is trying to read from the mailbox from RISCV B to RISCV T1 and said mailbox is empty, `true` otherwise|
|118|1|`false` if RISCV T2 is trying to read from the mailbox from RISCV B to RISCV T2 and said mailbox is empty, `true` otherwise|
|119|9|Reserved|

### Group C, RISCV T<sub>i</sub> bit positions:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|70|Reserved|
|70|32|The most recent response of a read-request against the mailbox from RISCV T<sub>i</sub> to RISCV B|
|102|4|Reserved|
|106|1|`false` if RISCV B is trying to read from the mailbox from RISCV T<sub>i</sub> to RISCV B and the mailbox is empty, `true` otherwise|
|107|1|`false` if RISCV T0 is trying to read from the mailbox from RISCV T<sub>i</sub> to RISCV T0 and said mailbox is empty, `true` otherwise|
|108|1|`false` if RISCV T1 is trying to read from the mailbox from RISCV T<sub>i</sub> to RISCV T1 and said mailbox is empty, `true` otherwise|
|109|1|`false` if RISCV T2 is trying to read from the mailbox from RISCV T<sub>i</sub> to RISCV T2 and said mailbox is empty, `true` otherwise|
|110|9|Reserved|
|119|9|If `!PCBuf[i].FIFO.empty`, the low 9 bits of `PCBuf[i].FIFO.peek()`. If the FIFO is empty, these bits instead come from _some_ recent FIFO contents. See group D for the remainder of this.|

### Group D (RISCV T<sub>i</sub> only):

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|23|If `!PCBuf[i].FIFO.empty`, the high 23 bits of `PCBuf[i].FIFO.peek()`. If the FIFO is empty, these bits instead come from _some_ recent FIFO contents. Guaranteed to be valid when bit 23 is unset or bit 24 is set.|
|23|1|`PCBuf[i].FIFO.empty` (see [PCBufs](BabyRISCV/PCBufs.md))|
|24|1|`PCBuf[i].FIFO.full` (see [PCBufs](BabyRISCV/PCBufs.md))|
|25|1|`true` if any MOP instruction is queued up in the FIFO before the T<sub>i</sub> MOP Expander, or the T<sub>i</sub> MOP Expander is actively expanding a MOP instruction (this is the same control signal as used by [TTSync `MOPExpanderDoneCheck`](BabyRISCV/TTSync.md#mopexpanderdonecheck))|
|26|1|`true` if the Tensix coprocessor has any in-flight instructions from thread i (this is the same control signal as used by [TTSync `CoprocessorDoneCheck`](BabyRISCV/TTSync.md#coprocessordonecheck))|
|27|1|Reserved|
|28|1|`true` if RISCV B is waiting on a read from [`PCBuf[i]`](BabyRISCV/PCBufs.md)|
|29|1|Reserved|
|30|1|`true` if RISCV T<sub>i</sub> is waiting on a [TTSync](BabyRISCV/TTSync.md) read|
|31|1|`true` if RISCV T<sub>i</sub> is waiting on a read from [`PCBuf[i]`](BabyRISCV/PCBufs.md)|
|32|19|Reserved|
|51|32|If an instruction is leaving the T<sub>i</sub> MOP Expander, the 32 bits of that instruction. Guaranteed to be valid when bit 83 is set.|
|83|1|`true` if an instruction is leaving the T<sub>i</sub> MOP Expander, `false` otherwise|
|84|1|`true` if the T<sub>i</sub> MOP Expander is currently expanding a [template 0 `MOP` instruction](TensixCoprocessor/MOPExpander.md#functional-model)|
|85|1|`true` if the T<sub>i</sub> MOP Expander is currently expanding a [template 1 `MOP` instruction](TensixCoprocessor/MOPExpander.md#functional-model)|
|86|32|If the T<sub>i</sub> MOP Expander is currently processing a `MOP` or `MOP_CFG` instruction, the 32 bits of that instruction. Otherwise, the instruction at the front of the FIFO before the T<sub>i</sub> MOP Expander. Guaranteed to be valid when bit 118 is set or bit 125 is set or bit 126 is unset.|
|118|1|`true` if the T<sub>i</sub> MOP Expander is currently processing a `MOP` or `MOP_CFG` instruction or if the FIFO before the T<sub>i</sub> MOP Expander has at least one instruction in it, `false` otherwise|
|119|6|Reserved|
|125|1|`true` if the FIFO before the T<sub>i</sub> MOP Expander is full, `false` otherwise|
|126|2|Reserved|

## Tensix Frontend

Set `DaisySel == 1` and set `SignalSel` according to the desired Tensix thread:

|`SignalSel`|Contents of 128 bits comes from|
|--:|---|
|**`12`**|Tensix thread T0|
|**`8`**|Tensix thread T1|
|**`4`**|Tensix thread T2|

The layout of the 128 bits is then:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|55|Reserved|
|55|32|If the FIFO between the T<sub>i</sub> Replay Expander and the T<sub>i</sub> Wait Gate contains any instructions, the instruction that is waiting to proceed through the Wait Gate. Guaranteed to be valid when bit 87 is unset. If bit 87 is set, these bits always contain zero.|
|87|1|`true` if the FIFO between the T<sub>i</sub> Replay Expander and the T<sub>i</sub> Wait Gate is empty, `false` otherwise|
|88|1|Reserved|
|89|1|`true` if the FIFO before the T<sub>i</sub> Replay Expander is full, `false` otherwise|
|90|1|`true` if the FIFO before the T<sub>i</sub> Replay Expander is empty, `false` otherwise|
|91|37|Reserved|

## ADCs

Some [ADC values](TensixCoprocessor/ADCs.md) can be presented on the debug daisychain when `DaisySel == 6`:

|`SignalSel`|Contents of 128 bits comes from|
|--:|---|
|**`0`**|`ADCs[0].Unpacker[0].Channel[0]`|
|**`1`**|`ADCs[0].Unpacker[0].Channel[1]`|
|**`2`**|`ADCs[0].Unpacker[1].Channel[0]`|
|**`3`**|`ADCs[0].Unpacker[1].Channel[1]`|
|**`4`**|`ADCs[2].Packers.Channel[0]`|
|**`5`**|`ADCs[2].Packers.Channel[1]`|

The layout of the 128 bits is then:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|18|`X`|
|18|18|`X_Cr`|
|36|28|Reserved|
|64|13|`Y`|
|77|3|Reserved|
|80|13|`Y_Cr`|
|93|3|Reserved|
|96|8|`Z`|
|104|8|`Z_Cr`|
|112|8|`W`|
|120|8|`W_Cr`|

## RWCs

Some [RWC values](TensixCoprocessor/RWCs.md) can be presented on the debug daisychain.

When `DaisySel == 3` and `SignalSel == 2`:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|6|`RWCs[0].SrcA`|
|6|2|Reserved|
|8|6|`RWCs[0].SrcA_Cr`|
|14|2|Reserved|
|16|6|`RWCs[1].SrcA`|
|22|2|Reserved|
|24|6|`RWCs[1].SrcA_Cr`|
|30|2|Reserved|
|32|6|`RWCs[2].SrcA`|
|38|2|Reserved|
|40|6|`RWCs[2].SrcA_Cr`|
|46|2|Reserved|
|48|6|`RWCs[0].SrcB`|
|54|2|Reserved|
|56|6|`RWCs[0].SrcB_Cr`|
|62|2|Reserved|
|64|6|`RWCs[1].SrcB`|
|70|2|Reserved|
|72|6|`RWCs[1].SrcB_Cr`|
|78|2|Reserved|
|80|6|`RWCs[2].SrcB`|
|86|2|Reserved|
|88|6|`RWCs[2].SrcB_Cr`|
|94|2|Reserved|
|96|10|`RWCs[0].Dst`|
|106|6|Reserved|
|112|10|`RWCs[0].Dst_Cr`|
|122|6|Reserved|

When `DaisySel == 3` and `SignalSel == 3`:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|10|`RWCs[1].Dst`|
|10|6|Reserved|
|16|10|`RWCs[1].Dst_Cr`|
|26|6|Reserved|
|32|10|`RWCs[2].Dst`|
|42|6|Reserved|
|48|10|`RWCs[2].Dst_Cr`|
|58|70|Reserved|

When `DaisySel == 3` and `SignalSel == 4`:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|62|Reserved|
|62|2|`RWCs[0].FidelityPhase`|
|64|2|`RWCs[1].FidelityPhase`|
|66|2|`RWCs[2].FidelityPhase`|
|68|60|Reserved|

## `SrcA` and `SrcB` access control

State relating to [`SrcA` and `SrcB` access control](TensixCoprocessor/SrcASrcB.md) can be presented on the debug daisychain when `DaisySel == 6` and `SignalSel == 9`:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|84|Reserved|
|84|1|`SrcA[Unpackers[0].SrcBank].AllowedClient == SrcClient::Unpackers`|
|85|1|`SrcA[MatrixUnit.SrcABank].AllowedClient == SrcClient::MatrixUnit`|
|86|4|Reserved|
|90|1|`SrcA[1].AllowedClient == SrcClient::MatrixUnit`|
|91|1|`SrcA[0].AllowedClient == SrcClient::MatrixUnit`|
|92|1|`MatrixUnit.SrcABank`|
|93|1|Reserved|
|94|1|`Unpackers[0].SrcBank`|
|95|5|Reserved|
|100|1|`SrcB[Unpackers[1].SrcBank].AllowedClient == SrcClient::Unpackers`|
|101|1|`SrcB[MatrixUnit.SrcBBank].AllowedClient == SrcClient::MatrixUnit`|
|102|4|Reserved|
|106|1|`SrcB[1].AllowedClient == SrcClient::MatrixUnit`|
|107|1|`SrcB[0].AllowedClient == SrcClient::MatrixUnit`|
|108|1|`MatrixUnit.SrcBBank`|
|109|1|Reserved|
|110|1|`Unpackers[1].SrcBank`|
|111|17|Reserved|

## Vector Unit (SFPU) `LaneEnabled`

The `LaneEnabled` state of the Vector Unit (SFPU) can be presented on the debug daisychain when `DaisySel == 7` and `SignalSel == 28`, although a 4x8 transpose is applied between the bit number and the lane number:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|1|`LaneEnabled[0]`|
|1|1|`LaneEnabled[8]`|
|2|1|`LaneEnabled[16]`|
|3|1|`LaneEnabled[24]`|
|4|1|`LaneEnabled[1]`|
|5|1|`LaneEnabled[9]`|
|6|1|`LaneEnabled[17]`|
|7|1|`LaneEnabled[25]`|
|8|1|`LaneEnabled[2]`|
|9|1|`LaneEnabled[10]`|
|10|1|`LaneEnabled[18]`|
|11|1|`LaneEnabled[26]`|
|12|1|`LaneEnabled[3]`|
|13|1|`LaneEnabled[11]`|
|14|1|`LaneEnabled[19]`|
|15|1|`LaneEnabled[27]`|
|16|1|`LaneEnabled[4]`|
|17|1|`LaneEnabled[12]`|
|18|1|`LaneEnabled[20]`|
|19|1|`LaneEnabled[28]`|
|20|1|`LaneEnabled[5]`|
|21|1|`LaneEnabled[13]`|
|22|1|`LaneEnabled[21]`|
|23|1|`LaneEnabled[29]`|
|24|1|`LaneEnabled[6]`|
|25|1|`LaneEnabled[14]`|
|26|1|`LaneEnabled[22]`|
|27|1|`LaneEnabled[30]`|
|28|1|`LaneEnabled[7]`|
|29|1|`LaneEnabled[15]`|
|30|1|`LaneEnabled[23]`|
|31|1|`LaneEnabled[31]`|
|32|96|Reserved|

> [!CAUTION]
> The `RISCV_DEBUG_REG_DBG_BUS_CNTL_REG.Enabled` control signal only flows into the Vector Unit (SFPU) when the Matrix Unit (FPU) clock is active. If software wishes to use the debug daisychain to observe `LaneEnabled`, then **after** setting `RISCV_DEBUG_REG_DBG_BUS_CNTL_REG.Enabled` to `true`, it needs to activate the Matrix Unit (FPU) clock for at least one cycle. This can be done by disabling the clock gater, or by executing any Vector Unit (SFPU) instruction (for example `SFPNOP`).

## L1 access ports

Some information from the [L1 access ports](L1.md#port-assignments) can be presented on the debug daisychain.

When `DaisySel == 8` and `SignalSel == 2`:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|17|If a request is arriving at port #0, address bits 4 through 20 of that request|
|17|17|If a request is arriving at port #1, address bits 4 through 20 of that request|
|34|17|If a request is arriving at port #2, address bits 4 through 20 of that request|
|51|17|If a request is arriving at port #3, address bits 4 through 20 of that request|
|68|17|If a request is arriving at port #4, address bits 4 through 20 of that request|
|85|17|If a request is arriving at port #5, address bits 4 through 20 of that request|
|102|17|If a request is arriving at port #6, address bits 4 through 20 of that request|
|119|9|If a request is arriving at port #7, address bits 4 through 12 of that request|

When `DaisySel == 8` and `SignalSel == 3`:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|8|If a request is arriving at port #7, address bits 13 through 20 of that request|
|8|17|If a request is arriving at port #8, address bits 4 through 20 of that request|
|25|17|If a request is arriving at port #9, address bits 4 through 20 of that request|
|42|17|If a request is arriving at port #10, address bits 4 through 20 of that request|
|59|17|If a request is arriving at port #11, address bits 4 through 20 of that request|
|76|1|`true` if a write-request is arriving at port #0, `false` otherwise|
|77|1|`true` if a write-request is arriving at port #1, `false` otherwise|
|78|1|`true` if a write-request is arriving at port #2, `false` otherwise|
|79|1|`true` if a write-request is arriving at port #3, `false` otherwise|
|80|1|`true` if a write-request is arriving at port #4, `false` otherwise|
|81|1|`true` if a write-request is arriving at port #5, `false` otherwise|
|82|1|`true` if a write-request is arriving at port #6, `false` otherwise|
|83|1|`true` if a write-request is arriving at port #7, `false` otherwise|
|84|1|`true` if a write-request is arriving at port #8, `false` otherwise|
|85|1|`true` if a write-request is arriving at port #9, `false` otherwise|
|86|1|`true` if a write-request is arriving at port #10, `false` otherwise|
|87|1|`true` if a write-request is arriving at port #11, `false` otherwise|
|88|1|`true` if a write-request is arriving at port #12, `false` otherwise|
|89|1|`true` if a write-request is arriving at port #13, `false` otherwise|
|90|1|`true` if a write-request is arriving at port #14, `false` otherwise|
|91|1|`true` if a write-request is arriving at port #15, `false` otherwise|
|92|1|`true` if a read-request is arriving at port #0, `false` otherwise|
|93|1|`true` if a read-request is arriving at port #1, `false` otherwise|
|94|1|`true` if a read-request is arriving at port #2, `false` otherwise|
|95|1|`true` if a read-request is arriving at port #3, `false` otherwise|
|96|1|`true` if a read-request is arriving at port #4, `false` otherwise|
|97|1|`true` if a read-request is arriving at port #5, `false` otherwise|
|98|1|`true` if a read-request is arriving at port #6, `false` otherwise|
|99|1|`true` if a read-request is arriving at port #7, `false` otherwise|
|100|1|`true` if a read-request is arriving at port #8, `false` otherwise|
|101|1|`true` if a read-request is arriving at port #9, `false` otherwise|
|102|1|`true` if a read-request is arriving at port #10, `false` otherwise|
|103|1|`true` if a read-request is arriving at port #11, `false` otherwise|
|104|1|`true` if a read-request is arriving at port #12, `false` otherwise|
|105|1|`true` if a read-request is arriving at port #13, `false` otherwise|
|106|1|`true` if a read-request is arriving at port #14, `false` otherwise|
|107|1|`true` if a read-request is arriving at port #15, `false` otherwise|
|108|20|Reserved|

When `DaisySel == 8` and `SignalSel == 5`:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|17|If a request is arriving at port #12, address bits 4 through 20 of that request|
|17|17|If a request is arriving at port #13, address bits 4 through 20 of that request|
|34|17|If a request is arriving at port #14, address bits 4 through 20 of that request|
|51|17|If a request is arriving at port #15, address bits 4 through 20 of that request|
|68|60|Reserved|

## Self-test

When `DaisySel` is valid, and `SignalSel == 255`:

|First&nbsp;bit|#&nbsp;Bits|Contents|
|--:|--:|---|
|0|32|`DaisySel`|
|32|32|`0xA5A5A5A5`|
|64|32|`0x5A5A5A5A`|
|96|32|`0xA5A5A5A5`|

