# FMA

The [`fma.c`](fma.c) file contains three functions:
1. `fma_model_ieee`: A software implementation of FP32 fused multiply-add ("FMA") which is compliant with IEEE754.
2. `fma_model_bh`: A software implementation of FP32 fused multiply-add ("FMA") which matches the behaviour of Blackhole Baby RISCV `fma.s` family of instructions and Blackhole Tensix Vector Unit (SFPU) [`SFPMAD`](../../BlackholeA0/TensixTile/TensixCoprocessor/SFPMAD.md) family of instructions.
3. `fma_model_wh`: A software implementation of FP32 fused multiply-add ("FMA") which matches the behaviour of Wormhole Tensix Vector Unit (SFPU) [`SFPMAD`](../../WormholeB0/TensixTile/TensixCoprocessor/SFPMAD.md) family of instructions.

Note that these functions do not model the Tensix Matrix Unit (FPU) instructions.

The three functions are written in a similar style, with the aim being to make it easier to understand how the three differ from each other. All three take 3x `uint32_t` as input and return 1x `uint32_t`, but in all cases the `uint32_t` is just a container for 32 bits, and those 32 bits are interpreted as FP32 values.

## Differences between `fma_model_bh` and `fma_model_ieee`

The major differences between `fma_model_bh` and `fma_model_ieee` are:
* Denormal inputs are treated as (signed) zero. This avoids a `__builtin_clz` and variable shift at the start.
* Denormal outputs (after rounding) are flushed to signed zero. This allows some places earlier in the implementation to take a few shortcuts.
* If `x * y` on its own would overflow to infinity, the result is infinity, even if the properly fused operation would have a finite result.
* If `x * y` on its own would underflow to zero, the result is as if `x * y` was _exactly_ zero.
* Rather than adding 23 bits of precision to `z` (the addend), 23 bits of precision are removed from `p` (the product). This makes the overall behaviour _somewhat_ similar to a separate multiply and add, but not entirely the same, as:
  * The product has four additional bits of precision (three at the bottom, one at the top) as compared to an FP32 value.
  * The product is not rounded to FP32 (albeit the sticky shift can be seen as a kind of round-to-odd).

## Differences between `fma_model_wh` and `fma_model_bh`

The major differences between `fma_model_wh` and `fma_model_bh` are:
* All zero outputs are always positive zero.
* NaN outputs are _not_ the canonical bit pattern `0x7fc00000`. Instead, they will have _at least_ the bits `0x7f800001` set, and then the computation proceeds and can gain additional bits.
* If `x * y` on its own is finite but would overflow to infinity, and `z` is the opposite sign infinity, the result is NaN rather than infinity.
* If `r_m = (r_m >> n) | (r_m & 1)` ends up doing a shift right by two bits, the higher of those two gets dropped rather than contributing to the sticky bit (this is a hardware bug rather than anything intentional).
* Rounding of denormals isn't quite correct: some intermediate results on the edge of denormal range should round up and become normal, but instead round down, stay denormal, and then get flushed to zero (the overall effect isn't _quite_ the same as flushing denormals to zero before rounding, but is similar).

## Correctness of `fma_model_ieee`

If using `fma_model_ieee` as a baseline for understanding `fma_model_bh` and `fma_model_wh`, it is useful to know _why_ `fma_model_ieee` is correct. The requirements for IEEE754 compliance reduce down to three main areas:
* If any input is NaN or ±infinity, the output will always be NaN or ±infinity. The standard spells out the various cases, though it allows implementations to choose the bit pattern of any output NaNs. The choice made by `fma_model_ieee` is for output NaNs to always be the bit pattern `0x7fc00000` (which happens to match the aarch64 behaviour when `FPCR.DN` is set).
* If the output is zero, the standard strictly specifies the rules for when it should be `-0` and when it should be `+0`.
* For cases not covered by the above, the implementation needs to behave as if the computation was performed on infinite-precision intermediate values with just one rounding/truncation step at the end to convert the infinite-precision value to an FP32 output.

Infinite-precision sounds scary, but quickly reduces down to finite precision: the FP32 output is finite precision, a few extra bits of precision are required for correct rounding, and the three inputs are themselves finite.

The following sections take apart `fma_model_ieee` piece by piece, and provide commentary on each piece. The commentary uses numbered variables rather than doing in-place mutation of variables.

---
<pre><code>uint32_t fma_model_ieee(uint32_t x, uint32_t y, uint32_t z) { // Compute x * y + z
  // Unpack inputs
#define fp32_unpack(var) \
    int32_t var##<sub>0</sub>_e = (var &gt;&gt; 23) &amp; 255; /* (biased) exponent */ \
    uint64_t var##<sub>0</sub>_m = (var &amp; 0x7fffff) ^ 0x800000; /* mantissa (including implicit bit) */ \
    if (var##<sub>0</sub>_e == 0) { /* convert denormal to something closer to normal */ \
      var##<sub>0</sub>_m ^= 0x800000; \
      var##<sub>0</sub>_e = 9 - __builtin_clz(var##<sub>0</sub>_m | 1); \
      var##<sub>0</sub>_m &lt;&lt;= 1 - var##<sub>0</sub>_e; \
    }
  fp32_unpack(x)
  fp32_unpack(y)
  fp32_unpack(z)
  uint32_t z_sign = z &amp; 0x80000000;
#undef fp32_unpack
</code></pre>

At this point:
* If `z` is finite, <code>z<sub>0</sub>_e</code> is less than 255 and <code>(-1)<sup>z_sign</sup> * z<sub>0</sub>_m * 2<sup>z<sub>0</sub>_e - 23 - 127</sup></code> equals the numerical value of `z`.
* If `z` is finite zero, <code>z<sub>0</sub>_e</code> is -22.
* If `z` is not finite, <code>z<sub>0</sub>_e</code> is 255.
* Either <code>z<sub>0</sub>_m == 0</code> or <code>2<sup>23</sup> ≤ z<sub>0</sub>_m &lt; 2<sup>24</sup></code>.
* The same statements are true for `x` and for `y`, albeit `x_sign` and `y_sign` are not computed.
---
<pre><code>  // p = x * y
  uint32_t p_sign = (x ^ y) &amp; 0x80000000;
  uint64_t p<sub>0</sub>_m = (uint64_t)x<sub>0</sub>_m * (uint64_t)y<sub>0</sub>_m;
  int32_t p<sub>0</sub>_e = x<sub>0</sub>_e + y<sub>0</sub>_e - 23 - 127;</code></pre>
At this point, provided that both `x` and `y` are finite, `p` is the infinite-precision result of `x * y`, and:
* The numerical value of <code>p</code> is <code>(-1)<sup>p_sign</sup> * p<sub>0</sub>_m * 2<sup>p<sub>0</sub>_e - 23 - 127</sup></code>.
* Either <code>p<sub>0</sub>_m == 0</code> or <code>2<sup>46</sup> ≤ p<sub>0</sub>_m &lt; 2<sup>48</sup></code>.

---
<pre><code>  // Add three extra bits of precision (aka. G, R, S bits)
  uint64_t p<sub>1</sub>_m = p<sub>0</sub>_m &lt;&lt; 3;
  uint64_t z<sub>1</sub>_m = z<sub>0</sub>_m &lt;&lt; 3;</code></pre>
The three additional bits are typically called "guard" (G), "round" (R), and "sticky" (S). Only two bits (R and S) are required for correct FMA, as `<< 23` in a subsequent step absolves the need for G, but the exposition uses three as `fma_model_bh` and `fma_model_wh` require three (because they do not have `<< 23`). The additional bit is superfluous in `fma_model_ieee`, but not harmful in any way.

At this point:
* If `z` is finite, <code>z<sub>0</sub>_e</code> is less than 255 and <code>(-1)<sup>z_sign</sup> * z<sub>1</sub>_m * 2<sup>z<sub>0</sub>_e - 23 - 127 - 3</sup></code> equals the numerical value of `z`.
* Either <code>z<sub>1</sub>_m == 0</code> or <code>2<sup>26</sup> ≤ z<sub>1</sub>_m &lt; 2<sup>27</sup></code>.
* The numerical value of <code>p</code> is <code>(-1)<sup>p_sign</sup> * p<sub>1</sub>_m * 2<sup>p<sub>0</sub>_e - 23 - 127 - 3</sup></code>.
* Either <code>p<sub>1</sub>_m == 0</code> or <code>2<sup>49</sup> ≤ p<sub>1</sub>_m &lt; 2<sup>51</sup></code>.
---
<pre><code>  // Handle NaN or Inf input
  if (x<sub>0</sub>_e == 255 || y<sub>0</sub>_e == 255 || z<sub>0</sub>_e == 255) {
    if ((x<sub>0</sub>_e == 255 &amp;&amp; (x<sub>0</sub>_m != 0x800000 || y<sub>0</sub>_m == 0)) // x NaN or x Inf times y zero
    ||  (y<sub>0</sub>_e == 255 &amp;&amp; (y<sub>0</sub>_m != 0x800000 || x<sub>0</sub>_m == 0)) // y NaN or y Inf times x zero
    ||  (z<sub>0</sub>_e == 255 &amp;&amp;  z<sub>0</sub>_m != 0x800000) // z NaN
    ||  (z<sub>0</sub>_e == 255 &amp;&amp; (x<sub>0</sub>_e == 255 || y<sub>0</sub>_e == 255) &amp;&amp; (z_sign != p_sign))) { // z Inf and (x * y) Inf and signs differ
      return 0x7fc00000; // NaN output
    } else if (z<sub>0</sub>_e == 255) { // z Inf
      return z; // Inf output
    } else { // (x * y) Inf
      return p_sign | 0x7f800000; // Inf output
    }
  }</code></pre>
This logic handles all cases of non-finite input. Subsequent logic can assume finite `z` and finite `p`.

---
<pre><code>  // Realign z_m to match p_m (adding 23 bits)
  uint64_t z<sub>2</sub>_m = z<sub>1</sub>_m &lt;&lt; 23;
  int32_t z<sub>2</sub>_e = z<sub>0</sub>_e - 23;</code></pre>
At this point:
* <code>(-1)<sup>z_sign</sup> * z<sub>2</sub>_m * 2<sup>z<sub>2</sub>_e - 23 - 127 - 3</sup></code> equals the numerical value of `z`.
* Either <code>z<sub>2</sub>_m == 0</code> or <code>2<sup>49</sup> ≤ z<sub>2</sub>_m &lt; 2<sup>50</sup></code>.

Note the similarity to previous statements about `p`:
* The numerical value of <code>p</code> is <code>(-1)<sup>p_sign</sup> * p<sub>1</sub>_m * 2<sup>p<sub>0</sub>_e - 23 - 127 - 3</sup></code>.
* Either <code>p<sub>1</sub>_m == 0</code> or <code>2<sup>49</sup> ≤ p<sub>1</sub>_m &lt; 2<sup>51</sup></code>.

---
<pre><code>  // Shortcut if p == 0
  if (p<sub>1</sub>_m == 0) return z<sub>2</sub>_m ? z : z_sign &amp; p_sign;</code></pre>
This logic handles <code>p<sub>1</sub>_m == 0</code>. The <code>z<sub>2</sub>_m == 0</code> case _could_ also be handled here, but it does not need to be special-cased, as it happens to be correctly handled by the subsequent logic. For now, the exposition assumes <code>z<sub>2</sub>_m != 0</code>; the <code>z<sub>2</sub>_m == 0</code> case will be analysed separately later.

---
<pre><code>#define sticky_shift(var, orig, amount) \
    do { \
      int32_t s = amount; \
      if (s >= sizeof(orig)*__CHAR_BIT__) { \
        var = (orig != 0); \
      } else { \
        var = orig &gt;&gt; s; \
        var |= ((var &lt;&lt; s) != orig); \
      } \
    } while(0)
  // r = z + p
  int32_t r<sub>3</sub>_e = p<sub>0</sub>_e &gt; z<sub>2</sub>_e ? p<sub>0</sub>_e : z<sub>2</sub>_e;
  uint64_t p<sub>3</sub>_m = p<sub>1</sub>_m;
  uint64_t z<sub>3</sub>_m = z<sub>2</sub>_m;
  if (p<sub>0</sub>_e &lt; r<sub>3</sub>_e) sticky_shift(p<sub>3</sub>_m, p<sub>1</sub>_m, r<sub>3</sub>_e - p<sub>0</sub>_e); // Discard low bits from p_m
  if (z<sub>2</sub>_e &lt; r<sub>3</sub>_e) sticky_shift(z<sub>3</sub>_m, z<sub>2</sub>_m, r<sub>3</sub>_e - z<sub>2</sub>_e); // Discard low bits from z_m</code></pre>
This is the first really non-trivial chunk of logic. <code>r<sub>3</sub>_e</code> is the maximum of the relevant exponents, and then <code>p<sub>3</sub>_m</code> and <code>z<sub>3</sub>_m</code> are computed. Both of <code>p<sub>3</sub>_m</code> and <code>z<sub>3</sub>_m</code> are "sticky-LSB integers". When viewed numerically, if `i` is a "sticky-LSB integer":
* If `i` is even, `i` represents exactly `i`.
* If `i` is odd, `i` represents _some_ value `i + i_err`, where `-1 < i_err < 1`. Alternatively, depending on context, it can represent _all_ values in the open range `(i - 1, i + 1)`. Note that `i_err` is described for the purpose of exposition, but the code never actually needs to compute it.

When viewed through the bitwise lens rather than the numeric lens, if `i` is a "sticky-LSB integer":
* If the least significant bit of `i` is clear, `i` represents exactly `i`.
* If the least significant bit of `i` is set, `i` was formed by doing `(j >> s) | 1` for some integers `j` and `s`, where at least one (but possibly more) of the low `s + 1` bits of `j` were set, and `i` represents the exact value <code>j * 2<sup>-s</sup></code>.

These two lenses are equivalent. The numerical lens is useful for understanding the effect of arithmetic on "sticky-LSB integers", whereas the bitwise lens is useful for understanding the effect of shifting them right.

At this point:
* <code>(-1)<sup>p_sign</sup> * (p<sub>3</sub>_m + p<sub>3</sub>_m_err) * 2<sup>r<sub>3</sub>_e - 23 - 127 - 3</sup></code> equals the numerical value of `p`.
* <code>(-1)<sup>z_sign</sup> * (z<sub>3</sub>_m + z<sub>3</sub>_m_err) * 2<sup>r<sub>3</sub>_e - 23 - 127 - 3</sup></code> equals the numerical value of `z`.

Crucially, both values now use the same exponent. Some additional facts are known about <code>p<sub>3</sub>_m</code> and <code>z<sub>3</sub>_m</code>, although they vary on a case-by-case basis:
<table><thead><tr><th/><th><code>2<sup>49</sup> ≤ p<sub>1</sub>_m &lt; 2<sup>50</sup></th><th><code>2<sup>50</sup> ≤ p<sub>1</sub>_m &lt; 2<sup>51</sup></th></tr>
<tr><th><code>p<sub>0</sub>_e + 3 ≤ z<sub>2</sub>_e</code></th><td><code>2<sup>49</sup> ≤ z<sub>3</sub>_m</code>, <code>z<sub>3</sub>_m</code> exact, <code>0 &lt; p<sub>3</sub>_m &lt; 2<sup>47</sup></code></td><td><code>2<sup>49</sup> ≤ z<sub>3</sub>_m</code>, <code>z<sub>3</sub>_m</code> exact, <code>0 &lt; p<sub>3</sub>_m &lt; 2<sup>48</sup></code></td></tr>
<tr><th><code>abs(p<sub>0</sub>_e - z<sub>2</sub>_e) ≤ 2</code></th><td><code>z<sub>3</sub>_m</code> and <code>p<sub>3</sub>_m</code> both exact</td><td><code>z<sub>3</sub>_m</code> and <code>p<sub>3</sub>_m</code> both exact</td></tr>
<tr><th><code>z<sub>2</sub>_e + 3 ≤ p<sub>0</sub>_e</code></th><td><code>2<sup>49</sup> ≤ p<sub>3</sub>_m</code>, <code>p<sub>3</sub>_m</code> exact, <code>0 &lt; z<sub>3</sub>_m &lt; 2<sup>47</sup></code></td><td><code>2<sup>50</sup> ≤ p<sub>3</sub>_m</code>, <code>p<sub>3</sub>_m</code> exact, <code>0 &lt; z<sub>3</sub>_m &lt; 2<sup>47</sup></code></td></tr></table>

> In the above table and below prose, "exact" is shorthand for "is even, or has an error term equal to zero".

The rows of the above table are mutally exclusive and cover all possibilities, and ditto for the columns. As such, regardless of the particular case, it can be seen that some things are always true:
* At least one of <code>p<sub>3</sub>_m</code> and <code>z<sub>3</sub>_m</code> is exact.
* If only one of <code>p<sub>3</sub>_m</code> and <code>z<sub>3</sub>_m</code> is exact, <code>2<sup>48</sup> ≤ max(p<sub>3</sub>_m,z<sub>3</sub>_m) - min(p<sub>3</sub>_m,z<sub>3</sub>_m) ≤ max(p<sub>3</sub>_m,z<sub>3</sub>_m) + min(p<sub>3</sub>_m,z<sub>3</sub>_m)</code>.

---
<pre><code>  uint32_t r_sign = p<sub>3</sub>_m &gt;= z<sub>3</sub>_m ? p_sign : z_sign;
  uint64_t z<sub>4</sub>_m = (z_sign != r_sign) ? ~z<sub>3</sub>_m : z<sub>3</sub>_m;
  uint64_t p<sub>4</sub>_m = (p_sign != r_sign) ? ~p<sub>3</sub>_m : p<sub>3</sub>_m;
  uint64_t r<sub>4</sub>_m = z<sub>4</sub>_m + p<sub>4</sub>_m + (p_sign != z_sign);</code></pre>

This logic computes `r_sign` and <code>r<sub>4</sub>_m</code> such that <code>(-1)<sup>r_sign</sup> * r<sub>4</sub>_m == (-1)<sup>z_sign</sup> * z<sub>3</sub>_m + (-1)<sup>p_sign</sup> * p<sub>3</sub>_m</code>. The key insight is that `r_sign` needs to come from whichever term gives <code>max(p<sub>3</sub>_m,z<sub>3</sub>_m)</code>, and then the overall computation becomes either <code>r<sub>4</sub>_m = max(p<sub>3</sub>_m,z<sub>3</sub>_m) + min(p<sub>3</sub>_m,z<sub>3</sub>_m)</code> or <code>r<sub>4</sub>_m = max(p<sub>3</sub>_m,z<sub>3</sub>_m) - min(p<sub>3</sub>_m,z<sub>3</sub>_m)</code>.

<code>r<sub>4</sub>_m</code> is yet another "sticky-LSB integer". If both of <code>p<sub>3</sub>_m</code> and <code>z<sub>3</sub>_m</code> are exact, then so is <code>r<sub>4</sub>_m</code>. Otherwise, <code>r<sub>4</sub>_m_err</code> is equal to whichever of <code>p<sub>3</sub>_m_err</code> or <code>z<sub>3</sub>_m_err</code> exists and is non-zero.

At this point:
* <code>(-1)<sup>r_sign</sup> * (r<sub>4</sub>_m + r<sub>4</sub>_m_err) * 2<sup>r<sub>3</sub>_e - 23 - 127 - 3</sup></code> equals the numerical value of `x * y + z`.
* Either <code>r<sub>4</sub>_m</code> is exact, or <code>2<sup>48</sup> ≤ r<sub>4</sub>_m</code>.

---
<pre><code>  // Shortcut if r == 0
  if (r<sub>4</sub>_m == 0) return z_sign &amp; p_sign;</code></pre>

This logic handles <code>r<sub>4</sub>_m</code> being exactly zero. Recall that <code>r<sub>4</sub>_m</code> is a "sticky-LSB integer", but it being even implies that it is exact. The logic is required because of the special rules about the sign of the FP32 result when the infinite-precision result is exactly zero, and also means that the subsequent `__builtin_clzll` is well defined.

---
<pre><code>  // Normalise 64-bit result to 37 zero bits, 1 one bit, 26 fractional bits
  int32_t n = 37 - __builtin_clzll(r<sub>4</sub>_m);
  int32_t r<sub>5</sub>_e = r<sub>3</sub>_e + n;
  if (r<sub>5</sub>_e &gt;= 255) return r_sign | 0x7f800000; // Inf
  if (r<sub>5</sub>_e &lt;= 0) { // Denorm or zero
    n += 1 - r<sub>5</sub>_e;
    r<sub>5</sub>_e = 0;
  }
  uint64_t r<sub>5</sub>_m;
  if (n &lt;= 0) r<sub>5</sub>_m = r<sub>4</sub>_m &lt;&lt; -n; else sticky_shift(r<sub>5</sub>_m, r<sub>4</sub>_m, n);
#undef sticky_shift</code></pre>

This logic is performing opposite adjustments on `r_e` and `r_m`, ideally to achieve <code>2<sup>26</sup> ≤ r<sub>5</sub>_m &lt; 2<sup>27</sup></code> and <code>0 &lt; r<sub>5</sub>_e &lt; 255</code>, but something weaker if that isn't possible. The potentially concerning part is the `<<` on a "sticky-LSB integer", as `>>` is well defined on "sticky-LSB integer"s but `<<` is only well defined for exact integers. Thankfully, the `<<` requires `n < 0`, which requires <code>__builtin_clzll(r<sub>4</sub>_m) &gt; 37</code>, which requires <code>r<sub>4</sub>_m &lt; 2<sup>26</sup></code>, and we know that <code>r<sub>4</sub>_m &lt; 2<sup>48</sup></code> implies <code>r<sub>4</sub>_m</code> is exact.

At this point, the below table enumerates the possible cases:

<table><tr><th/><th>Numerical value of <code>x * y + z</code></th><th>Known Bounds</th></tr>
<tr><th><code>r<sub>5</sub>_e == 0</code></th><td><code>(-1)<sup>r_sign</sup> * (r<sub>5</sub>_m + r<sub>5</sub>_m_err) * 2<sup>r<sub>5</sub>_e - 23 - 126 - 3</sup></code></td><td align="right"><code>r<sub>5</sub>_m &lt; 2<sup>26</sup></code></td></tr>
<tr><th><code>0 &lt; r<sub>5</sub>_e &lt 255</code></th><td><code>(-1)<sup>r_sign</sup> * (r<sub>5</sub>_m + r<sub>5</sub>_m_err) * 2<sup>r<sub>5</sub>_e - 23 - 127 - 3</sup></code></td><td><code>2<sup>26</sup> ≤ r<sub>5</sub>_m &lt; 2<sup>27</sup></code></td></tr></table>

---
<pre><code>  // Start reassembling result
  uint32_t r<sub>6</sub> = (r<sub>5</sub>_e &lt;&lt; 23) | ((r<sub>5</sub>_m &gt;&gt; 3) &amp; 0x7fffff);</code></pre>

The `>> 3` is discarding the low three bits of <code>r<sub>5</sub>_m</code> (the subsequent rounding step will look at said bits), and then `& 0x7fffff` is keeping the next 23 bits. At this point, the sign bit notwithstanding, either <code>r<sub>6</sub></code> or <code>r<sub>6</sub> + 1</code> is the correctly rounded FP32 result: <code>r<sub>6</sub></code> if rounding down, <code>r<sub>6</sub> + 1</code> if rounding up.

---
<pre><code>  // Round to nearest even
  uint32_t r<sub>7</sub> = r<sub>6</sub> + (((r<sub>5</sub>_m &amp; 7) + (r<sub>6</sub> &amp; 1)) &gt; 4);</code></pre>

This logic looks at the three bits which were just discarded, and uses them to make a rounding decision. <code>r<sub>5</sub>_m &amp; 7</code> is a "sticky-LSB integer", and as if by magic, it _so happens_ that "sticky-LSB integer"s retain _just enough_ information to make the correct rounding decision. The possible cases are:

|Value of <code>r<sub>5</sub>_m &amp; 7</code>|Interpretation|Desired action|
|---|---|---|
|7|Exact value somewhere in open range `(6, 8)`|Round up, as that is nearest|
|6|Exactly 6|Round up, as that is nearest|
|5|Exact value somewhere in open range `(4, 6)`|Round up, as that is nearest|
|4|Exactly 4|Round up if <code>r<sub>6</sub>_m</code> is odd, as ties to even<br/>Round down if <code>r<sub>6</sub>_m</code> is even, as ties to even|
|3|Exact value somewhere in open range `(2, 4)`|Round down, as that is nearest|
|2|Exactly 2|Round down, as that is nearest|
|1|Exact value somewhere in open range `(0, 2)`|Round down, as that is nearest|
|0|Exactly 0|Round down, as that gives the exact value|

Note that adding one (as in <code>r<sub>6</sub> + 1</code>) can cause the mantissa bits to overflow and cause an exponent increase, and similarly can cause a finite value to overflow to infinity. Both of these behaviours are correct. As <code>r<sub>5</sub>_e &lt; 255</code>, the exponent cannot overflow into the sign field.

---
<pre><code>  return r_sign | r<sub>7</sub>;
}</code></pre>

All that remains is to attach the sign bit, and we're done.

---

... except that the <code>z<sub>2</sub>_m == 0</code> case remains unexplored. If that was the case, then <code>z<sub>2</sub>_e == -45</code>. Various sub-cases can then be explored:
* <code>p<sub>0</sub>_e &gt;= -45</code>: It is easy to confirm that <code>r<sub>4</sub>_m</code> will end up equal to <code>p<sub>1</sub>_m</code> and is exact, and therefore everything still works.
* <code>-45 &gt; p<sub>0</sub>_e &gt;= -48</code>: The `sticky_shift` might shift <code>p<sub>1</sub>_m</code> right by up to three bits, but nevertheless <code>r<sub>4</sub>_m</code> is exact, and it remains the case that `r == p`, and so everything still works.
* <code>p<sub>0</sub>_e == -48 - i</code> for `i ≥ 1`: the low `i` bits of <code>p<sub>1</sub>_m</code> will be pushed into the sticky bit by `sticky_shift`, then the subsequent <code>__builtin_clzll(r<sub>4</sub>_m)</code> will be at least `17 + i`, so `n` will be less than 20, so <code>r<sub>3</sub>_e + n</code> will be less than -25, so it'll take the <code>r<sub>5</sub>_e &lt;= 0</code> path, and end up doing a `sticky_shift` by 46 bits. This 2<sup>nd</sup> `sticky_shift` completely absorbs any error introduced by the 1<sup>st</sup> `sticky_shift`, and then everything can proceed as per normal.
