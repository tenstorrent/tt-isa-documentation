# CSRs

The baby RISCV cores recognize the following CSRs:

|Address|Name|Specification|Notes|
|---|---|---|---|
|`0x003`|`fcsr`|`F` Extension|Hardware ignores rounding mode bits.|
|`0x008`|`vstart`|`V` Extension|Read-only, always zero. Not strictly conformant, as should be writable. Hardware never takes an interrupt in the middle of a vector instruction, so it would be conformant if this was writable but subsequently executing a vector instruction with non-zero `vstart` caused an illegal instruction exception.|
|`0x009`|`vxsat`|`V` Extension||
|`0x00a`|`vxrm`|`V` Extension||
|`0x300`|`mstatus`|Machine-level&nbsp;ISA|Read-only, always `0x80006600` (indicating FP register state and vector register state permanently dirty). Non-conformant, as not writable.|
|`0x301`|`misa`|Machine-level&nbsp;ISA|Read-only, always `0x40201123` (indicating RV32IMABFV). Non-conformant, as each of `A` / `B` / `F` / `V` are at best only partially implemented, and bit 23 should be set to indicate presence of non-standard extensions.|
|`0x320`|`mcountinhibit`|Machine-level&nbsp;ISA|Non-conformant, as cannot be used to inhibit incrementing of `mcycle` or `minstret` counters (but can be used to inhibit other counters).|
|`0x323`|`mhpmevent3`|Machine-level&nbsp;ISA||
|`0x324`|`mhpmevent4`|Machine-level&nbsp;ISA||
|`0x7c0`|`cfg0`|Custom|Various configuration / chicken bits.|
|`0x7c1`|`pmacfg0`|Custom||
|`0x7c2`|`pmacfg1`|Custom||
|`0x7c3`|`cfg1`|Custom|Scratch CSR; software can use for any purpose.|
|`0x7c4`|`hwa_mask`|Custom|Scratch CSR; software can use for any purpose.|
|`0x7c5`|`hwa_cfg`|Custom|Scratch CSR; software can use for any purpose.|
|`0x7c6`|`vgsrc`|Custom|Scratch CSR; software can use for any purpose.|
|`0xb00`|`mcycle`|Machine-level&nbsp;ISA|See `mcycleh` for high bits.|
|`0xb02`|`minstret`|Machine-level&nbsp;ISA|See `minstreth` for high bits.|
|`0xb03`|`mhpmcounter3`|Machine-level&nbsp;ISA|See `mhpmcounter3h` for high bits. See `mhpmevent3` for event selector.|
|`0xb04`|`mhpmcounter4`|Machine-level&nbsp;ISA|See `mhpmcounter4h` for high bits. See `mhpmevent4` for event selector.|
|`0xb80`|`mcycleh`|Machine-level&nbsp;ISA||
|`0xb82`|`minstreth`|Machine-level&nbsp;ISA||
|`0xb83`|`mhpmcounter3h`|Machine-level&nbsp;ISA||
|`0xb84`|`mhpmcounter4h`|Machine-level&nbsp;ISA||
|`0xbc0`|`tt_cfg_qstatus`|Custom|Tensix coprocessor frontend status, and Vector Unit (SFPU) conditional execution status|
|`0xbc1`|`tt_cfg_bstatus`|Custom|Tensix coprocessor busy status|
|`0xbc2`|`tt_cfg_sstatus0`|Custom|RISCV B and RISCV NC: Scratch CSR; software can use for any purpose.<br/>Elsewhere: STREAM_CURR_PHASE_REG_INDEX of some NoC Overlay stream.|
|`0xbc3`|`tt_cfg_sstatus1`|Custom|RISCV B and RISCV NC: Scratch CSR; software can use for any purpose.<br/>Elsewhere: STREAM_CURR_PHASE_REG_INDEX of some NoC Overlay stream.|
|`0xbc4`|`tt_cfg_sstatus2`|Custom|RISCV B and RISCV NC: Scratch CSR; software can use for any purpose.<br/>Elsewhere: STREAM_CURR_PHASE_REG_INDEX of some NoC Overlay stream.|
|`0xbc5`|`tt_cfg_sstatus3`|Custom|RISCV B and RISCV NC: Scratch CSR; software can use for any purpose.<br/>Elsewhere: STREAM_CURR_PHASE_REG_INDEX of some NoC Overlay stream.|
|`0xbc6`|`tt_cfg_sstatus4`|Custom|RISCV B and RISCV NC: Scratch CSR; software can use for any purpose.<br/>Elsewhere: STREAM_NUM_MSGS_RECEIVED_REG_INDEX of some NoC Overlay stream.|
|`0xbc7`|`tt_cfg_sstatus5`|Custom|RISCV B and RISCV NC: Scratch CSR; software can use for any purpose.<br/>Elsewhere: STREAM_NUM_MSGS_RECEIVED_REG_INDEX of some NoC Overlay stream.|
|`0xbc8`|`tt_cfg_sstatus6`|Custom|RISCV B and RISCV NC: Scratch CSR; software can use for any purpose.<br/>Elsewhere: STREAM_NUM_MSGS_RECEIVED_REG_INDEX of some NoC Overlay stream.|
|`0xbc9`|`tt_cfg_sstatus7`|Custom|RISCV B and RISCV NC: Scratch CSR; software can use for any purpose.<br/>Elsewhere: STREAM_NUM_MSGS_RECEIVED_REG_INDEX of some NoC Overlay stream.|
|`0xbca`|`intp_restore_pc`|Custom|Copy of the `pc` to which `mret` will return. As it is just a copy, writing to it does not affect `mret` (and due to a hardware bug, interrupt handlers cannot perform CSR writes, so its writability is a moot point).|
|`0xc00`|`cycle`|Zicntr|Read/write alias of `mcycle`. Not strictly conformant, as should be a read-only alias.|
|`0xc02`|`instret`|Zicntr|Read/write alias of `minstret`. Not strictly conformant, as should be a read-only alias.|
|`0xc20`|`vl`|`V` Extension|Not strictly conformant, as writable using regular CSR instructions in addition to `vset{i}vl{i}` instructions.|
|`0xc21`|`vtype`|`V` Extension|Not strictly conformant, as writable using regular CSR instructions in addition to `vset{i}vl{i}` instructions.|
|`0xc22`|`vlenb`|`V` Extension|Value is initially `16`. Not strictly conformant, as should be read-only (writes have no effect on vector execution; they only affect the value observed by subsequent CSR reads).|
|`0xc80`|`cycleh`|Zicntr|Read/write alias of `mcycleh`. Not strictly conformant, as should be a read-only alias.|
|`0xc82`|`instreth`|Zicntr|Read/write alias of `minstreth`. Not strictly conformant, as should be a read-only alias.|
|`0xf14`|`mhartid`|Machine&#8209;level&nbsp;ISA|Read-only, always zero. Non-conformant, as should be unique per hart.|

## `cfg0`

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|1|`DisLdBufByp`|If set, load instructions will wait (in EX1) for the store queue to be empty before entering the Load/Store Unit (if the tail of the store queue is a store to L1, the duration of this wait can depend on `StMergeTimer`)|
|1|1|`DisBp`|If set, the branch predictor is disabled|
|2|1|`DisIcPrefetch`|If set, the instruction cache prefetchers are disabled|
|3|1|`DisLowCash`|If set, the L0 data cache is disabled|
|4|1|`DisableDataEcc`||
|5|2|Reserved|Mutable, but no effect on execution|
|7|1|`DisPmcWrapArnd`|If set, HPM counters will stop counting once their value is ≥ 2<sup>64</sup>|
|8|1|`PmcClrOnRd`|If set, reading any of `mhpmcounter3` or `mhpmcounter4` or `mhpmcounter3h` or `mhpmcounter4h` will also write zero to whichever CSR was read, and write zero to the 65<sup>th</sup> bit of the containing counter|
|9|1|`SyncAllOps`|If set, once any RISCV instruction leaves the frontend, the next instruction will not leave the frontend until the previous instruction has retired|
|10|1|`DisCsrSync`|If clear, once an `csrrw` / `csrrs` / `csrrc` / `csrrwi` / `csrrsi` / `csrrci` / `vsetvl` / `vsetvli` / `vsetivli` / `fence` / `ecall` / `ebreak` instruction leaves the frontend, the next instruction will not leave the frontend until the previous instruction has retired|
|11|1|`DisVec128b`||
|12|1|`DisStMerge`|If clear, the store queue can coalesce temporally adjacent stores, provided that they target the same 16-byte aligned region of L1, and the starting byte addresses of the two stores are within ±4 of each other|
|13|5|`StMergeTimer`|Provided that `DisStMerge` is clear, the number of cycles to wait after an L1 store instruction to see whether it can coalesce with the next store instruction|
|18|1|`DisTriscCache`|If clear, adjacent `.ttinsn` instructions can be macro-fused to form an instruction which pushes up to four Tensix instructions in a single RISCV clock cycle|
|19|1|`DisMultiMemLdOps`||
|20|1|`DisRegForwarding`|If set, the operand forwarding network is disabled, meaning that instructions can only leave the frontend once their dependencies have retired|
|21|3|Reserved|Mutable, but no effect on execution|
|24|1|`DisLowCachePeriodicFlush`|If clear, every request which goes through the L0 data cache has approximately a 0.8% chance of causing the entire L0 data cache to be flushed|
|25|1|Reserved|Mutable, but no effect on execution|
|26|2|`BpHistSel`||
|28|1|`EnRespOrderFifo`||
|29|1|`DisTTStatusReg`|If set, the values in the various `tt_cfg_*status*` CSRs are frozen: their values can be changed using CSR instructions, but hardware will not otherwise change them|
|30|1|`EnBFloat`|If set, "Zfh" instructions (such as `fadd.h`) operate on BF16 values rather than FP16 values|
|31|1|`EnBFloatRTNE`|Provided that `EnBFloat` is set, provides a static rounding mode for BF16 instructions: RTZ when clear, RTNE when set|

At reset, all fields are initialized to zero/clear, except for `StMergeTimer`, which is initialized to `16`.

## `pmacfg0` and `pmacfg1`

Both of these CSRs are 32 bits wide, but only the low bit of each is meaningful. If the low bit of _either_ (or both) is set, then all load and store instructions become strongly ordered, and behave as if a `fence` instruction was inserted immediately before them.

The high 31 bits of these CSRs were _intended_ to be used to specify an aligned address space range, but due to a hardware bug, the range selection always selects the entire address space. As such, the utility of these CSRs is significantly reduced.

## `tt_cfg_qstatus`

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|11|`tensix_issue_queue_status`|RISCV T<sub>i</sub>: Thread-specific bitmask of instruction types, bit set if at least one instruction of that type has been pushed by RISCV T<sub>i</sub> and is still occupying queue space somewhere in the Tensix frontend<br/>Elsewhere: Copy of `or_reduced_tensix_issue_queue_status`|
|11|1|`sfpu_cc`|`true` if at least one Vector Unit (SFPU) lane is currently enabled. If making use of this bit, software is responsible for ensuring sufficient synchronization: it needs to ensure that all relevant Vector Unit (SFPU) instructions have finished executing, and that the lane enable state has been given enough time to propagate to this CSR|
|12|1|Reserved||
|13|11|`or_reduced_tensix_issue_queue_status`|Bitmask of instruction types, bit set if at least one instruction of that type has been pushed by any RISCV T<sub>i</sub> and is still occupying queue space somewhere in the Tensix frontend||
|24|1|`sfpu_cc`|Copy of bit 11|
|25|7|Reserved||

The 11-bit bitmasks consist of:
|Bit&nbsp;index|Instruction type|
|--:|---|
|0|`REPLAY` (provided that `Exec` is `true`, or `Load` is `false`)|
|1|`MOP` (does not include `MOP_CFG`)|
|2|Scalar Unit (ThCon)|
|3|Mover|
|4|Unpacker|
|5|Packer|
|6|Configuration Unit|
|7|Sync Unit|
|8|Miscellaneous Unit, Mover, Scalar Unit (ThCon), Packer, or Unpacker|
|9|Vector Unit (SFPU)|
|10|Matrix Unit (FPU)|

## `tt_cfg_bstatus`

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|11|`tensix_busy_status`|RISCV T<sub>i</sub>: Thread-specific bitmask of instruction types, bit set if at least one instruction of that type has been pushed by RISCV T<sub>i</sub> and is still occupying queue space somewhere in the Tensix frontend, or at least one instruction of that type was generated by RISCV T<sub>i</sub> and is executing in the backend<br/>Elsewhere: Copy of `or_reduced_tensix_busy_status`|
|11|11|`or_reduced_tensix_busy_status`|Bitmask of instruction types, bit set if at least one instruction of that type has been pushed by any RISCV T<sub>i</sub> and is still occupying queue space somewhere in the Tensix frontend, or at least one instruction of that type was generated by any RISCV T<sub>i</sub> and is executing in the backend|
|22|10|Reserved||

The 11-bit bitmasks have the same layout as for `tt_cfg_qstatus` above.
