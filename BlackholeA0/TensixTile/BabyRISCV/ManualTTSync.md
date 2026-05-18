# Manual TTSync

The following exists in the RISCV T0 / T1 / T2 address space, starting at address `PC_BUF_BASE`:

```c
uint32_t Padding;
uint32_t CoprocessorDoneCheck; // Not a plain variable; has exotic read/write behaviors (see below).
uint32_t MOPExpanderDoneCheck; // Not a plain variable; has exotic read/write behaviors (see below).
```

Stores to either of `CoprocessorDoneCheck` or `MOPExpanderDoneCheck` will have the stored value discarded within the memory subsystem. Loads from either will return an undefined value, albeit possibly not immediately, and this delay is the whole point of performing the load. Per the usual [RISCV memory ordering](MemoryOrdering.md) rules, the load can (to a limited extent) execute in parallel with subsequent independent instructions; one possible way to ensure that the load has returned before subsequent instructions start is to use an instruction sequence like:
```
sw x0, 0(t0)   # Store to  CoprocessorDoneCheck or MOPExpanderDoneCheck (explained later)
lw t1, 0(t0)   # Load from CoprocessorDoneCheck or MOPExpanderDoneCheck
andi t1, t1, 0 # Actually wait for the load result, and also replace the undefined value with zero
```

Due to a hardware bug, if RISCV T<sub>i</sub> _starts_ executing a load from `CoprocessorDoneCheck` or `MOPExpanderDoneCheck`, it must not _start_ executing another load against the range `PC_BUF_BASE` through `PC_BUF_BASE + 0xFFFF` or the range `TENSIX_MAILBOX0_BASE` through `TENSIX_MAILBOX0_BASE + 0x3FFF` until the original load has _finished_ executing. Failure to comply with this constraint can cause loads against these ranges to return incorrect values, or can cause RISCV T<sub>i</sub> to hang. Compliance is possible by having an ALU instruction after the load (and before the next load) which consumes the result of the load (as in the instruction sequence above), or by executing at least seven other instructions after the load and before the next load.

> [!TIP]
> Manual TTSync in Blackhole is the same as TTSync in Wormhole.

## `CoprocessorDoneCheck`

Loads from this address allow RISCV T<sub>i</sub> to determine when the Tensix coprocessor has finished executing all instructions from Tensix thread T<sub>i</sub>. The logic for determining the result of the read-request is:
```
while (Tensix coprocessor has any in-flight instructions from thread i) {
  if (PCBuf[i].OverrideEn && PCBuf[i].OverrideBusy) {
    break;
  } else {
    wait;
  }
}
return undefined;
```
Note that the `wait` in the above happens _within_ the memory subsystem; it doesn't _by itself_ block execution of subsequent RISCV instructions. Use the instruction sequence at the top of this page to block execution of subsequent RISCV instructions.

Per the usual [RISCV memory ordering](MemoryOrdering.md) rules, a small amount of reordering can occur between loads and stores, which becomes relevant if performing a store to push a Tensix instruction to the coprocessor, followed shortly thereafter by a load from `CoprocessorDoneCheck` to wait for completion of that instruction. To prevent this undesirable reordering, software should store a value to `CoprocessorDoneCheck` prior to loading from `CoprocessorDoneCheck`, as is done in the instruction sequence at the top of this page (the stored value is irrelevant and will be discarded; the only effect of the store is to enforce ordering between earlier stores and the subsequent load).

## `MOPExpanderDoneCheck`

Loads from this address allow RISCV T<sub>i</sub> to determine when it is safe to change the MOP Expander configuration of Tensix thread T<sub>i</sub>. The logic for determining the result of the read-request is:
```
while (Any MOP instruction is queued up in the FIFO before thread i MOP Expander
    || Thread i MOP Expander is actively expanding a MOP instruction) {
  if (PCBuf[i].OverrideEn && PCBuf[i].OverrideBusy) {
    break;
  } else {
    wait;
  }
}
return undefined;
```

Note that the `wait` in the above happens _within_ the memory subsystem; it doesn't _by itself_ block execution of subsequent RISCV instructions. Use the instruction sequence at the top of this page to block execution of subsequent RISCV instructions.

Note that `MOPExpanderDoneCheck` does not tell you whether the instructions resulting from expanding a [`MOP`](../TensixCoprocessor/MOP.md) instruction have finished executing (or even whether they've _started_ executing). For example, the MOP Expander could have finished the expansion process, but the entire expanded sequence (or some tail thereof) could be sitting in the FIFOs before the Replay Expander and the Wait Gate. As such, the utility of `MOPExpanderDoneCheck` is limited to determining when it is safe to change the MOP Expander configuration of Tensix thread T<sub>i</sub>.

Per the usual [RISCV memory ordering](MemoryOrdering.md) rules, a small amount of reordering can occur between loads and stores, which becomes relevant if performing a store to push a [`MOP`](../TensixCoprocessor/MOP.md) instruction, followed shortly thereafter by a load from `MOPExpanderDoneCheck` to wait for that instruction to finish expanding. To prevent this undesirable reordering, software should store a value to `MOPExpanderDoneCheck` prior to loading from `MOPExpanderDoneCheck`, as is done in the instruction sequence at the top of this page (the stored value is irrelevant and will be discarded; the only effect of the store is to enforce ordering between earlier stores and the subsequent load).

## Alternative synchronization mechanisms

Other mechanisms exist for when `CoprocessorDoneCheck` or `MOPExpanderDoneCheck` aren't quite the right tool for the job.

### Auto TTSync

RISCV T0 / T1 / T2 can use [Auto TTSync](AutoTTSync.md) to ensure correct ordering between pushed Tensix instructions and MMIO accesses to Tensix Backend Configuration / Tensix GPRs / TDMA-RISC.

### Tensix semaphores

RISCV T0 / T1 / T2 have [Tensix semaphores](../TensixCoprocessor/SyncUnit.md#semaphores) mapped into their address space. Any Tensix thread can execute a [`STALLWAIT`](../TensixCoprocessor/STALLWAIT.md) instruction (with some wait condition bits, and at least block bit B1), followed by a [`SEMINIT`](../TensixCoprocessor/SEMINIT.md) or [`SEMPOST`](../TensixCoprocessor/SEMPOST.md) or [`SEMGET`](../TensixCoprocessor/SEMGET.md) instruction. Meanwhile, any of RISCV T0 / T1 / T2 can be executing a polling loop reading from the semaphore in question, waiting for its value to change.

### Common address space

If all semaphores have already been used, a less efficient option is to use some other common address space, with the Tensix coprocessor performing a write (e.g. [`STOREREG`](../TensixCoprocessor/STOREREG.md), `STOREIND`, [`PACR_SETREG`](../TensixCoprocessor/PACR_SETREG.md), or `UNPACR_NOP`) and a RISCV core executing a polling loop containing a read. Viable address spaces include [L1](../L1.md) and [Tensix GPRs](../TensixCoprocessor/ScalarUnit.md#gprs), along with any NoC configuration registers or [TDMA-RISC configuration registers](../TDMA-RISC.md) or [Tensix backend configuration registers](../TensixCoprocessor/BackendConfiguration.md) which are not otherwise being used for anything. Compared to using Tensix semaphores, the reads in these cases can potentially cause contention with other cores accessing the same device (whereas RISCV reads from Tensix semaphores never cause contention).

### PCBufs

RISCV B can use [PCBufs](PCBufs.md) to wait for any of T0 or T1 or T2.
