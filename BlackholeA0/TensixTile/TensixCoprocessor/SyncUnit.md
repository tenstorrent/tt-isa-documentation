# Sync Unit

The Sync Unit contains mutexes and semaphores to help coordinate the three Tensix threads. The instructions executed by the Sync Unit are:

<table><thead><tr><th>Instruction(s)</th><th>Latency</th><th>Throughput</th></tr></thead>
<tr><td><code><a href="ATGETM.md">ATGETM</a></code>, <code><a href="ATRELM.md">ATRELM</a></code></td><td>1 cycle</td><td>Issue up to three per cycle, provided they refer to different mutexes</td></tr>
<tr><td><code><a href="SEMINIT.md">SEMINIT</a></code>, <code><a href="SEMPOST.md">SEMPOST</a></code>, <code><a href="SEMGET.md">SEMGET</a></code></td><td>1 cycle</td><td rowspan="3">Issue at most one of these per cycle</td></tr>
<tr><td><code><a href="STALLWAIT.md">STALLWAIT</a></code>, <code><a href="SEMWAIT.md">SEMWAIT</a>, <code><a href="STREAMWAIT.md">STREAMWAIT</a></code></td><td>1 cycle</td></tr>
<tr><td>RISCV semaphore write-request</td><td>1 cycle</td></tr>
<tr><td>RISCV semaphore read-request</td><td>1 cycle</td><td>Issue one per RISCV per cycle</td></tr>
</table>

Multiple instructions can be accepted per cycle, subject to the limitations in the "Throughput" column above. RISCV read-requests and write-requests against Tensix semaphores end up at the Sync Unit: reads are effectively free, whereas writes contest for throughput with Tensix semaphore instructions.

The `STALLWAIT` / `SEMWAIT` / `STREAMWAIT` instructions technically execute in the Sync Unit, though their execution consists purely of passing them over to the Wait Gate (of whichever thread issued the instruction), where they sit as the Wait Gate's latched wait instruction. The Wait Gate will then re-evaluate the instruction's wait condition every cycle until it is met.

The `ATGETM` instruction executes in a single cycle, but it cannot pass through the Wait Gate if some other thread is holding the mutex in question.

> [!TIP]
> Compared to Wormhole, the Sync Unit in Blackhole gains a new `STREAMWAIT` instruction, changes the encoding of `STALLWAIT`'s condition mask, and reduces the number of mutexes from seven to four.

## Mutexes

There are four mutexes (index 0, and then indices 2 through 4). Each mutex can be in one of four states:
* Not held by any thread
* Held by Tensix T0
* Held by Tensix T1
* Held by Tensix T2

The [`ATGETM`](ATGETM.md) and [`ATRELM`](ATRELM.md) instructions manipulate these mutexes: `ATGETM` is a combined wait and acquire of a single mutex, whereas `ATRELM` releases a mutex.

## Semaphores

Instruction descriptions assume the presence of the following global variable:
```c
struct {
  uint4_t Value;
  uint4_t Max;
} Semaphores[8];
```

The [`SEMINIT`](SEMINIT.md), [`SEMPOST`](SEMPOST.md), and [`SEMGET`](SEMGET.md) instructions atomically manipulate the `Value` and `Max` fields of these semaphores, and then the [`SEMWAIT`](SEMWAIT.md) instruction can be used to wait based on either `Value == 0` or `Value >= Max`. Note that there are no combined wait-then-manipulate instructions. In addition to the Tensix instructions, RISCV T0 / T1 / T2 can query the value of any semaphore by using `lw` instructions against particular addresses, and can atomically increment or decrement any semaphore by using `sw` instructions against particular addresses. This provides a mechanism to synchronize Tensix execution with RISCV execution:
* Tensix thread can issue `SEMWAIT`, which will prevent further execution of that Tensix thread until some RISCV performs an `sw` to atomically increment or decrement the semaphore being waited upon (or until some other Tensix thread performs an appropriate `SEMINIT`, `SEMPOST`, or `SEMGET` to modify the semaphore).
* RISCV core can perform `lw` instructions in a polling loop, waiting for some Tensix thread to execute an appropriate `SEMINIT`, `SEMPOST`, or `SEMGET`. Note that in many cases, that Tensix thread will want to use a `STALLWAIT` instruction prior to `SEMINIT` / `SEMPOST` / `SEMGET`, in order to ensure that the semaphore manipulation only happens once the conditions specified by the `STALLWAIT` have been met.

## RISCV access to semaphores

The following exists in the RISCV T0 / T1 / T2 address space, starting at address `PC_BUF_BASE`:
```c
uint32_t Padding[PC_BUF_SEMAPHORE_BASE];
uint32_t SemaphoreAccess[8]; // Not a plain variable; has exotic read/write behaviors (see below).
```

Reads from `SemaphoreAccess[i]` behave as:
```c
return Semaphores[i].Value;
```

Writes to `SemaphoreAccess[i] = new_val` behave as:
```c
atomic {
  if (new_val & 1) {
    // This is like a SEMGET instruction.
    if (Semaphores[i].Value > 0) {
      Semaphores[i].Value -= 1;
    }
  } else {
    // This is like a SEMPOST instruction.
    if (Semaphores[i].Value < 15) {
      Semaphores[i].Value += 1;
    }
  }
}
```

If a RISCV core is incrementing or decrementing semaphores through this memory-mapped interface, the [RISCV memory ordering](../BabyRISCV/MemoryOrdering.md) rules should be consulted to ensure correct ordering of the semaphore store relative to any other nearby loads and stores.
