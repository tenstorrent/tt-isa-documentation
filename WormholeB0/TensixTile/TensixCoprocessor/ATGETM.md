# `ATGETM` (Acquire a Tensix mutex)

**Summary:** Atomically acquire a Tensix mutex for the current thread. The thread will be blocked from issuing subsequent Tensix instructions until the mutex has been acquired. Once the thread no longer needs the mutex, it should use [`ATRELM`](ATRELM.md) to release it, which will allow other threads to acquire it.

**Backend execution unit:** [Sync Unit](SyncUnit.md)

## Syntax

```c
TT_ATGETM(/* u16 */ Index)
```

## Encoding

![](../../../Diagrams/Out/Bits32_ATGETM.svg)

## Functional model

This instruction will, if necessary, spend time waiting at the Wait Gate for the mutex to become available:

```c
if (Index == 1 || Index > 7) {
  // No mutex has this index, so the instruction never leaves the Wait Gate and the thread hangs.
  UndefinedBehavior();
}

if (Mutex[Index].HeldBy == CurrentThread) {
  NonContractualBehavior {
    // Current silicon lets the thread through, still holding the mutex, after maybe
    // waiting for a cycle or two if other threads are also trying to either acquire
    // or release the mutex in question (not architecturally guaranteed)
    if (maybe) wait;
    if (maybe) wait;
  }
} else {
  // Wait for mutex to become available if it is held
  // by some other thread.
  while (Mutex[Index].HeldBy != Nobody) {
    wait;
  }
}
```

Once the wait is complete, if the current thread already holds the mutex, or is the only thread trying to acquire the mutex, it proceeds to acquire it:

```c
Mutex[Index].HeldBy = CurrentThread;
```

If multiple threads are trying to acquire a mutex not held by anyone, then one thread is chosen to acquire the mutex, and the other threads continue waiting. Once the acquirer subsequently uses [`ATRELM`](ATRELM.md) to release the mutex, the behavior of `ATRELM` ensures fairness.
