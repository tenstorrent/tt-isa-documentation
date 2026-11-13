# `INCADCZW` (Increment some ADC Z and W counters)

**Summary:**

**Backend execution unit:** [Miscellaneous Unit](MiscellaneousUnit.md)

## Syntax

```c
TT_INCADCZW(((/* bool */ PK) << 2) +
            ((/* bool */ U1) << 1) +
              /* bool */ U0,
              /* u3 */ W1Inc,
              /* u3 */ Z1Inc,
              /* u3 */ W0Inc,
              /* u3 */ Z0Inc)
```

There is no syntax to specify `/* u2 */ ThreadOverride`; if a non-zero value is desired for this field, the raw encoding must be used. Use of `ThreadOverride` is `UnsupportedFunctionality` and is strongly discouraged. In practice, on both Wormhole and Blackhole, a non-zero `ThreadOverride` applies the instruction to the counters of thread `ThreadOverride - 1` instead of the issuing thread's, as the functional model below describes. An override can corrupt the named thread's ADCs if that thread, or another override, reaches them in the same cycle; see [overriding another thread's ADCs](ADCs.md#overriding-another-threads-adcs).

## Encoding

![](../../../Diagrams/Out/Bits32_INCADCZW.svg)

## Functional model

```c
if (ThreadOverride) {
  UnsupportedFunctionality(); // Wormhole and Blackhole hardware behave as below
}
uint2_t WhichThread = ThreadOverride == 0 ? CurrentThread : ThreadOverride - 1;
if (U0) ApplyTo(ADCs[WhichThread].Unpacker[0]);
if (U1) ApplyTo(ADCs[WhichThread].Unpacker[1]);
if (PK) ApplyTo(ADCs[WhichThread].Packers);

void ApplyTo(ADC& ADC_) {
  ADC_.Channel[0].Z += Z0Inc;
  ADC_.Channel[0].W += W0Inc;
  ADC_.Channel[1].Z += Z1Inc;
  ADC_.Channel[1].W += W1Inc;
}
```
