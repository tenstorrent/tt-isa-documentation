# `SETADC` (Set one ADC counter)

**Summary:**

**Backend execution unit:** [Miscellaneous Unit](MiscellaneousUnit.md)

## Syntax

```c
TT_SETADC(((/* bool */ PK) << 2) +
          ((/* bool */ U1) << 1) +
            /* bool */ U0,
            /* u1 */ Channel,
            /* u2 */ XYZW,
            /* u18 */ NewValue)
```

The high two bits of `NewValue` are `ThreadOverride`. Use of a non-zero `ThreadOverride` is `UnsupportedFunctionality` and is strongly discouraged. On both Wormhole and Blackhole, an override can corrupt the named thread's ADCs if that thread, or another override, reaches them in the same cycle; see [overriding another thread's ADCs](ADCs.md#overriding-another-threads-adcs).

## Encoding

![](../../../Diagrams/Out/Bits32_SETADC.svg)

## Functional model

```c
uint2_t ThreadOverride = NewValue >> 16;
if (ThreadOverride) {
  UnsupportedFunctionality(); // Wormhole and Blackhole hardware behave as below
}
uint2_t WhichThread = ThreadOverride == 0 ? CurrentThread : ThreadOverride - 1;
if (U0) ApplyTo(ADCs[WhichThread].Unpacker[0]);
if (U1) ApplyTo(ADCs[WhichThread].Unpacker[1]);
if (PK) ApplyTo(ADCs[WhichThread].Packers);

void ApplyTo(ADC& ADC_) {
  auto& Ch = ADC_.Channel[Channel];
  switch (XYZW) {
  case 0: Ch.X = NewValue, Ch.X_Cr = NewValue; break;
  case 1: Ch.Y = NewValue, Ch.Y_Cr = NewValue; break;
  case 2: Ch.Z = NewValue, Ch.Z_Cr = NewValue; break;
  case 3: Ch.W = NewValue, Ch.W_Cr = NewValue; break;
  }
}
```
