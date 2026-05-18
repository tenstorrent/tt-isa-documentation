# Floating-point bit patterns

The Tensix coprocessor does not entirely conform to IEEE 754. For the various floating-point formats supported by arithmetic instructions within the coprocessor, this page outlines the IEEE 754 interpretation of various bit patterns, along with the coprocessor interpretation of those bit patterns.

Software running on the host system will generally expect IEEE 754 interpretation of various bit patterns, so to bridge the gap between the interpretations, software may want to perform a pre-processing step before presenting data to the coprocessor, and similarly perform a post-processing step after receiving data back from the coprocessor. This is especially true for FP16 data.

## FP32

<table><thead><tr><th>Sign</th><th>Exp&nbsp;(8b)</th><th>Mant&nbsp;(23b)</th><th>IEEE 754</th><th>Vector Unit (SFPU)</th><th>Matrix Unit (FPU)</th></tr></thead>
<tr><td>0</td><td>255</td><td>Non-zero</td><td colspan="2">+NaN</td><td>(1 + Mant/2<sup>23</sup>) * 2<sup>Exp-127</sup> (†)</td></tr>
<tr><td>0</td><td>255</td><td>0</td><td colspan="2">+Infinity</td><td>(1 + Mant/2<sup>23</sup>) * 2<sup>Exp-127</sup> (‡)</td></tr>
<tr><td>0</td><td>1 - 254</td><td>Any</td><td colspan="3">(1 + Mant/2<sup>23</sup>) * 2<sup>Exp-127</sup></td></tr>
<tr><td>0</td><td>0</td><td>Non-zero</td><td>(0 + Mant/2<sup>23</sup>) * 2<sup>-126</sup></td><td colspan="2">+0 (†)</td></tr>
<tr><td>0</td><td>0</td><td>0</td><td colspan="3">+0</td></tr>
<tr><td>1</td><td>0</td><td>0</td><td>-0</td><td colspan="2">-0 (†)</td></tr>
<tr><td>1</td><td>0</td><td>Non-zero</td><td>-(0 + Mant/2<sup>23</sup>) * 2<sup>-126</sup></td><td colspan="2">-0 (†)</td></tr>
<tr><td>1</td><td>1 - 254</td><td>Any</td><td colspan="3">-(1 + Mant/2<sup>23</sup>) * 2<sup>Exp-127</sup></td></tr>
<tr><td>1</td><td>255</td><td>0</td><td colspan="2">-Infinity</td><td>-(1 + Mant/2<sup>23</sup>) * 2<sup>Exp-127</sup> (‡)</td></tr>
<tr><td>1</td><td>255</td><td>Non-zero</td><td colspan="2">-NaN</td><td>-(1 + Mant/2<sup>23</sup>) * 2<sup>Exp-127</sup> (†)</td></tr></table>

(†) Arithmetic instructions will never produce this bit pattern as an output, but if this bit pattern is presented as an input, it'll be interpreted as shown.

(‡) In some contexts, this bit pattern behaves similarly to ±Infinity, as the Matrix Unit (FPU) will output this bit pattern for values whose magnitude is too large to represent.

When the Vector Unit (SFPU) emits a NaN value, the mantissa will be _some_ non-zero value: the least significant bit of the mantissa will always be set, and the remaining bits may or may not be set.

## TF32

There is no IEEE 754 specification for this type, but one can be reasonably inferred by starting with IEEE 754 FP32 and then truncating the mantissa down to 10 bits.

<table><thead><tr><th>Sign</th><th>Exp&nbsp;(8b)</th><th>Mant&nbsp;(10b)</th><th>Truncated IEEE 754 FP32</th><th>Matrix Unit (FPU)</th></tr></thead>
<tr><td>0</td><td>255</td><td>Non-zero</td><td>+NaN</td><td>(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-127</sup> (†)</td></tr>
<tr><td>0</td><td>255</td><td>0</td><td>+Infinity</td><td>(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-127</sup> (‡)</td></tr>
<tr><td>0</td><td>1 - 254</td><td>Any</td><td colspan="2">(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-127</sup></td></tr>
<tr><td>0</td><td>0</td><td>Non-zero</td><td>(0 + Mant/2<sup>10</sup>) * 2<sup>-126</sup></td><td>+0 (†)</td></tr>
<tr><td>0</td><td>0</td><td>0</td><td colspan="2">+0</td></tr>
<tr><td>1</td><td>0</td><td>0</td><td>-0</td><td>-0 (†)</td></tr>
<tr><td>1</td><td>0</td><td>Non-zero</td><td>-(0 + Mant/2<sup>10</sup>) * 2<sup>-126</sup></td><td>-0 (†)</td></tr>
<tr><td>1</td><td>1 - 254</td><td>Any</td><td colspan="2">-(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-127</sup></td></tr>
<tr><td>1</td><td>255</td><td>0</td><td>-Infinity</td><td>-(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-127</sup> (‡)</td></tr>
<tr><td>1</td><td>255</td><td>Non-zero</td><td>-NaN</td><td>-(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-127</sup> (†)</td></tr></table>

(†) Arithmetic instructions will never produce this bit pattern as an output, but if this bit pattern is presented as an input, it'll be interpreted as shown.

(‡) In some contexts, this bit pattern behaves similarly to ±Infinity, as the Matrix Unit (FPU) will output this bit pattern for values whose magnitude is too large to represent.

## BF16

There is no IEEE 754 specification for this type, but one can be reasonably inferred by starting with IEEE 754 FP32 and then truncating the mantissa down to 7 bits.

<table><thead><tr><th>Sign</th><th>Exp&nbsp;(8b)</th><th>Mant&nbsp;(7b)</th><th>Truncated IEEE 754 FP32</th><th>Vector Unit (SFPU)</th><th>Matrix Unit (FPU)</th></tr></thead>
<tr><td>0</td><td>255</td><td>Non-zero</td><td colspan="2">+NaN</td><td>(1 + Mant/2<sup>7</sup>) * 2<sup>Exp-127</sup> (†)</td></tr>
<tr><td>0</td><td>255</td><td>0</td><td colspan="2">+Infinity</td><td>(1 + Mant/2<sup>7</sup>) * 2<sup>Exp-127</sup> (‡)</td></tr>
<tr><td>0</td><td>1 - 254</td><td>Any</td><td colspan="3">(1 + Mant/2<sup>7</sup>) * 2<sup>Exp-127</sup></td></tr>
<tr><td>0</td><td>0</td><td>Non-zero</td><td>(0 + Mant/2<sup>7</sup>) * 2<sup>-126</sup></td><td colspan="2">+0 (†)</td></tr>
<tr><td>0</td><td>0</td><td>0</td><td colspan="3">+0</td></tr>
<tr><td>1</td><td>0</td><td>0</td><td>-0</td><td colspan="2">-0 (†)</td></tr>
<tr><td>1</td><td>0</td><td>Non-zero</td><td>-(0 + Mant/2<sup>7</sup>) * 2<sup>-126</sup></td><td colspan="2">-0 (†)</td></tr>
<tr><td>1</td><td>1 - 254</td><td>Any</td><td colspan="3">-(1 + Mant/2<sup>7</sup>) * 2<sup>Exp-127</sup></td></tr>
<tr><td>1</td><td>255</td><td>0</td><td colspan="2">-Infinity</td><td>-(1 + Mant/2<sup>7</sup>) * 2<sup>Exp-127</sup> (‡)</td></tr>
<tr><td>1</td><td>255</td><td>Non-zero</td><td colspan="2">-NaN</td><td>-(1 + Mant/2<sup>7</sup>) * 2<sup>Exp-127</sup> (†)</td></tr></table>

(†) Arithmetic instructions will never produce this bit pattern as an output, but if this bit pattern is presented as an input, it'll be interpreted as shown.

(‡) In some contexts, this bit pattern behaves similarly to ±Infinity, as the Matrix Unit (FPU) will output this bit pattern for values whose magnitude is too large to represent.

## FP16

<table><thead><tr><th>Sign</th><th>Exp&nbsp;(5b)</th><th>Mant&nbsp;(10b)</th><th>IEEE 754</th><th>Vector Unit (SFPU)</th><th>Matrix Unit (FPU)</th></tr></thead>
<tr><td>0</td><td>31</td><td>1023</td><td>+NaN</td><td>(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup> or +Infinity</td><td>(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup> (‡)</td></tr>
<tr><td>0</td><td>31</td><td>1 - 1022</td><td>+NaN</td><td colspan="2">(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup></td></tr>
<tr><td>0</td><td>31</td><td>0</td><td>+Infinity</td><td colspan="2">(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup></td></tr>
<tr><td>0</td><td>1 - 30</td><td>Any</td><td colspan="3">(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup></td></tr>
<tr><td>0</td><td>0</td><td>Non-zero</td><td>(0 + Mant/2<sup>10</sup>) * 2<sup>-14</sup></td><td><a href="SFPLOADI.md"><code>SFPLOADI</code></a>: (1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup><br/><a href="SFPLOAD.md"><code>SFPLOAD</code></a>: (0 + Mant/2<sup>10</sup>) * 2<sup>-126</sup> (*)</td><td>+0 (†)</td></tr>
<tr><td>0</td><td>0</td><td>0</td><td>+0</td><td><a href="SFPLOADI.md"><code>SFPLOADI</code></a>: (1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup><br/><a href="SFPLOAD.md"><code>SFPLOAD</code></a> and <a href="SFPSTORE.md"><code>SFPSTORE</code></a>: +0</td><td>+0</td></tr>
<tr><td>1</td><td>0</td><td>0</td><td>-0</td><td><a href="SFPLOAD.md"><code>SFPLOAD</code></a> and <a href="SFPSTORE.md"><code>SFPSTORE</code></a>: -0<br/><a href="SFPLOADI.md"><code>SFPLOADI</code></a>: -(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup></td><td>-0 (†)</td></tr>
<tr><td>1</td><td>0</td><td>Non-zero</td><td>-(0 + Mant/2<sup>10</sup>) * 2<sup>-14</sup></td><td><a href="SFPLOAD.md"><code>SFPLOAD</code></a>: -(0 + Mant/2<sup>10</sup>) * 2<sup>-126</sup> (*)<br/><a href="SFPLOADI.md"><code>SFPLOADI</code></a>: -(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup></td><td>-0 (†)</td></tr>
<tr><td>1</td><td>1 - 30</td><td>Any</td><td colspan="3">-(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup></td></tr>
<tr><td>1</td><td>31</td><td>0</td><td>-Infinity</td><td colspan="2">-(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup></td></tr>
<tr><td>1</td><td>31</td><td>1 - 1022</td><td>-NaN</td><td colspan="2">-(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup></td></tr>
<tr><td>1</td><td>31</td><td>1023</td><td>-NaN</td><td>-(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup> or -Infinity</td><td>-(1 + Mant/2<sup>10</sup>) * 2<sup>Exp-15</sup> (‡)</td></tr></table>

(†) Arithmetic instructions will never produce this bit pattern as an output, but if this bit pattern is presented as an input, it'll be interpreted as shown.

(‡) In some contexts, this bit pattern behaves similarly to ±Infinity, as the Matrix Unit (FPU) will output this bit pattern for values whose magnitude is too large to represent (as will [`SFPSTORE`](SFPSTORE.md)), and [`SFPLOAD`](SFPLOAD.md) can optionally be configured to interpret this bit pattern as ±Infinity.

(*) This will become an FP32 denormal, which subsequent arithmetic instructions within the Vector Unit (SFPU) will interpret as zero.

## BFP

The coprocessor's packers and unpackers support a variety of block float formats, which are collectively called BFP formats. These consist of either 8 or 4 or 2 bits per datum, where the most significant bit is a sign bit and the remaining bits are a magnitude. Exponents are separate, with each group of 16 datums sharing a common 8-bit exponent (though BFP8a/BFP4a/BFP2a only use the low five bits of the exponent and expect the high three bits to be zero).

### BFP8 and BFP8a

<table><thead><tr><th>Sign</th><th>Exp</th><th>Mag&nbsp;(7b)</th><th>BFP8 Meaning</th><th>BFP8a Meaning</th></tr></thead>
<tr><td>0</td><td>Any</td><td>1 - 127</td><td>Mag/2<sup>6</sup> * 2<sup>Exp-127</sup></td><td>Mag/2<sup>6</sup> * 2<sup>Exp-15</sup></td></tr>
<tr><td>0</td><td>Any</td><td>0</td><td>+0</td><td>+0</td></tr>
<tr><td>1</td><td>Any</td><td>1 - 127</td><td>-Mag/2<sup>6</sup> * 2<sup>Exp-127</sup></td><td>-Mag/2<sup>6</sup> * 2<sup>Exp-15</sup></td></tr>
<tr><td>1</td><td>Any</td><td>0</td><td>-2<sup>128</sup> or -Infinity</td><td>-2<sup>16</sup></td></tr></table>

### BFP4 and BFP4a

<table><thead><tr><th>Sign</th><th>Exp</th><th>Mag&nbsp;(3b)</th><th>BFP4 Meaning</th><th>BFP4a Meaning</th></tr></thead>
<tr><td>0</td><td>Any</td><td>1 - 7</td><td>Mag/2<sup>2</sup> * 2<sup>Exp-127</sup></td><td>Mag/2<sup>2</sup> * 2<sup>Exp-15</sup></td></tr>
<tr><td>0</td><td>Any</td><td>0</td><td>+0</td><td>+0</td></tr>
<tr><td>1</td><td>Any</td><td>1 - 7</td><td>-Mag/2<sup>2</sup> * 2<sup>Exp-127</sup></td><td>-Mag/2<sup>2</sup> * 2<sup>Exp-15</sup></td></tr>
<tr><td>1</td><td>Any</td><td>0</td><td>-2<sup>128</sup> or -Infinity</td><td>-2<sup>16</sup></td></tr></table>

### BFP2 and BFP2a

<table><thead><tr><th>Sign</th><th>Exp</th><th>Mag&nbsp;(1b)</th><th>BFP2 Meaning</th><th>BFP2a Meaning</th></tr></thead>
<tr><td>0</td><td>Any</td><td>1</td><td>2<sup>Exp-127</sup></td><td>2<sup>Exp-15</sup></td></tr>
<tr><td>0</td><td>Any</td><td>0</td><td>+0</td><td>+0</td></tr>
<tr><td>1</td><td>Any</td><td>1</td><td>-2<sup>Exp-127</sup></td><td>-2<sup>Exp-15</sup></td></tr>
<tr><td>1</td><td>Any</td><td>0</td><td>-2<sup>128</sup> or -Infinity</td><td>-2<sup>16</sup></td></tr></table>

### Conversion routines

Hardware will convert BFP8 / BFP4 / BFP2 to BF16 using the following logic:

```c
uint16_t BFP8ToBF16(uint8_t DatumBits, uint8_t ExpBits) {
  uint8_t Sign = DatumBits >> 7;
  uint8_t Mag  = DatumBits << 1;
  if (Mag == 0) {
    return Sign ? 0xff80 : 0;
  } else {
    unsigned LZ = stdc_leading_zeros_uc(Mag);
    Mag <<= LZ;
    ExpBits -= LZ;
    return (Sign << 15) | (ExpBits << 7) | (Mag & 0x7e);
  }
}

uint16_t BFP4ToBF16(uint4_t DatumBits, uint8_t ExpBits) {
  return BFP8ToBF16(DatumBits << 4, ExpBits);
}

uint16_t BFP2ToBF16(uint2_t DatumBits, uint8_t ExpBits) {
  return BFP8ToBF16(DatumBits << 6, ExpBits);
}
```

Hardware will convert BFP8a / BFP4a / BFP2a to FP16 using the following logic:

```c
uint16_t BFP8aToFP16(uint8_t DatumBits, uint8_t ExpBits) {
  uint8_t Sign = DatumBits >> 7;
  uint8_t Mag  = DatumBits << 1;
  if (Mag == 0) {
    return Sign ? 0xfc00 : 0;
  } else {
    unsigned LZ = stdc_leading_zeros_uc(Mag);
    Mag <<= LZ;
    ExpBits -= LZ;
    if (ExpBits & 0xe0) UndefinedBehavior();
    return (Sign << 15) | (ExpBits << 10) | ((Mag & 0x7e) << 3);
  }
}

uint16_t BFP4aToFP16(uint4_t DatumBits, uint8_t ExpBits) {
  return BFP8aToFP16(DatumBits << 4, ExpBits);
}

uint16_t BFP2aToFP16(uint2_t DatumBits, uint8_t ExpBits) {
  return BFP8aToFP16(DatumBits << 6, ExpBits);
}
```
