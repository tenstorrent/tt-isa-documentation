# NIU Interrupts

As a new feature in Blackhole, software can opt to use NIU interrupts to respond to NoC transactions completing, rather than having to poll counters. Alternatively, software can choose to poll [`NIU_TRANS_COUNT_RTZ_SOURCE`](MemoryMap.md#niu_trans_count_rtz_source) as a more efficient alternative to polling multiple [`NIU_MST_REQS_OUTSTANDING_ID(i)` counters](Counters.md), without using the follow-on interrupt functionality. Note that `NIU_MST_REQS_OUTSTANDING_ID(i)` are the only counters able to drive interrupts; logic for polling other counters cannot be converted to use interrupts.

To use NIU interrupts, some one-time setup is required:
* Choose a transaction ID `i`, which is some value between `0` and `15` inclusive.
* Write `1u << i` to `NIU_BASE + 0x0060`, to ensure that `NIU_MST_REQS_OUTSTANDING_ID(i)` is zero.
* Write `1u << i` to [`NIU_TRANS_COUNT_RTZ_CLR`](MemoryMap.md#niu_trans_count_rtz_clr), to ensure that bit `i` of [`NIU_TRANS_COUNT_RTZ_SOURCE`](MemoryMap.md#niu_trans_count_rtz_source) is clear.
* Set bit `i` of [`NIU_TRANS_COUNT_RTZ_CFG`](MemoryMap.md#niu_trans_count_rtz_cfg) to `true`, leaving other bits unchanged. This ensures that an IRQ will be raised when bit `i` of [`NIU_TRANS_COUNT_RTZ_SOURCE`](MemoryMap.md#niu_trans_count_rtz_source) is set.
* Write the address of an interrupt handler to [`HW_INT_PC[1]`](../TensixTile/PIC.md#memory-map) (for NoC #0) or [`HW_INT_PC[2]`](../TensixTile/PIC.md#memory-map) (for NoC #1). This could be:
    * A [bulk interrupt handler](#bulk-interrupt-handler)
    * A [non-bulk interrupt handler](#non-bulk-interrupt-handler)
* If using a non-bulk interrupt handler, set bit 28 of [`NIU_TRANS_COUNT_RTZ_CFG`](MemoryMap.md#niu_trans_count_rtz_cfg) to `true`, to ensure that reads from [`NIU_TRANS_COUNT_RTZ_NUM`](MemoryMap.md#niu_trans_count_rtz_num) clear the matching bit in [`NIU_TRANS_COUNT_RTZ_SOURCE`](MemoryMap.md#niu_trans_count_rtz_source).
* Set bit 1 (for NoC #0) or bit 2 (for NoC #1) of [`BRISC_HW_INT_EN`](../TensixTile/PIC.md#memory-map) (for RISCV B) and/or [`NCRISC_HW_INT_EN`](../TensixTile/PIC.md#memory-map) (for RISCV NC), leaving other bits unchanged. This will cause the raised IRQ to interrupt RISCV B and/or RISCV NC.

Then for every initiated NoC request:
* Ensure that the `NOC_PACKET_TRANSACTION_ID` field within [`NOC_PACKET_TAG`](MemoryMap.md#noc_packet_tag) is set to `i` (and that no other unrelated requests have this field set to `i`).
* For write requests and atomic requests, ensure that the `NOC_CMD_RESP_MARKED` flag within [`NOC_CTRL`](MemoryMap.md#noc_ctrl) is set (this flag has no effect for read requests).
* Ensure that the `NOC_CMD_BRCST_PACKET` flag within [`NOC_CTRL`](MemoryMap.md#noc_ctrl) is clear, or that the broadcast has exactly one recipient (noting that the `NIU_MST_REQS_OUTSTANDING_ID` counters do not have useful semantics for broadcasts with more than one recipient, as they increment by one but then eventually decrement by the number of recipients).

If initiating several NoC requests, software can either:
* Use a different transaction ID `i` for each request.
* Use the same transaction ID `i` for all requests. In this case, it is possible for the interrupt to fire before all of the requests have been initiated. To avoid this, software is encouraged to clear the bit(s) within `BRISC_HW_INT_EN` / `NCRISC_HW_INT_EN` prior to initiating any requests, and then set them again once all requests have been initiated. The interrupt handler should also check that `NIU_MST_REQS_OUTSTANDING_ID` is indeed zero.

## Bulk interrupt handler

A bulk interrupt handler is designed to be capable of handling multiple bits per invocation. This pattern should not be used when the same NoC NIU interrupt is enabled for both RISCV B and RISCV NC, as there is a narrow race condition in claiming the interrupts. In all other cases, bulk interrupt handlers are preferred, as they better amortize the cost of taking the interrupt.

The interrupt handler should:
1. Save any RISCV execution state which it intends to modify.
2. Read [`NIU_TRANS_COUNT_RTZ_SOURCE`](MemoryMap.md#niu_trans_count_rtz_source) and [`NIU_TRANS_COUNT_RTZ_CFG`](MemoryMap.md#niu_trans_count_rtz_cfg).
3. Compute `pending = NIU_TRANS_COUNT_RTZ_SOURCE & NIU_TRANS_COUNT_RTZ_CFG`.
4. Write `pending` to [`NIU_TRANS_COUNT_RTZ_CLR`](MemoryMap.md#niu_trans_count_rtz_clr).
5. Iterate over the set bits of `pending` (for example using `ctz` to identify a bit index, and `pending &= pending - 1` to clear that bit), and for each such bit index `j`:
    * Read `NIU_MST_REQS_OUTSTANDING_ID(j)`, and if the value is zero, perform the application-specific logic relating to the NoC transaction(s) with ID `j` being complete.
6. Restore any modified RISCV execution state.
7. Execute an `mret` instruction.

General details about [PIC interrupt handlers](../TensixTile/PIC.md#interrupt-handlers) may also be relevant.

## Non-bulk interrupt handler

A non-bulk interrupt handler is designed to handle exactly one bit per invocation. If the same NoC NIU interrupt is enabled for both RISCV B and RISCV NC, or if logic other than interrupt handlers reads from [`NIU_TRANS_COUNT_RTZ_NUM`](MemoryMap.md#niu_trans_count_rtz_num), then interrupts should not be used for transaction ID zero, as otherwise the meaning is ambiguous when [`NIU_TRANS_COUNT_RTZ_NUM`](MemoryMap.md#niu_trans_count_rtz_num) returns zero.

The interrupt handler should:
1. Save any RISCV execution state which it intends to modify.
2. Read [`NIU_TRANS_COUNT_RTZ_NUM`](MemoryMap.md#niu_trans_count_rtz_num), and call the result `j`.
3. Read `NIU_MST_REQS_OUTSTANDING_ID(j)`, and if the value is zero, perform the application-specific logic relating to the NoC transaction(s) with ID `j` being complete.
4. Restore any modified RISCV execution state.
5. Execute an `mret` instruction.

If multiple bits within `NIU_TRANS_COUNT_RTZ_SOURCE & NIU_TRANS_COUNT_RTZ_CFG` were initially set, then one of those bits will be selected by the read of [`NIU_TRANS_COUNT_RTZ_NUM`](MemoryMap.md#niu_trans_count_rtz_num), and then after `mret` is executed, hardware will shortly invoke the interrupt handler again to handle the next set bit.

General details about [PIC interrupt handlers](../TensixTile/PIC.md#interrupt-handlers) may also be relevant.
