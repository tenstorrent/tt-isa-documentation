/*
 * SPDX-FileCopyrightText: © 2025 Tenstorrent AI ULC
 *
 * SPDX-License-Identifier: Apache-2.0
 * 
 * Bit-perfect models of:
 * 1) IEEE754 fused FMA (with canonical NaNs, and rounding mode always nearest even)
 * 2) FMA as found in Blackhole Baby RISCVs and Blackhole Tensix Vector Unit (SFPU)
 * 3) FMA as found in Wormhole Tensix Vector Unit (SFPU)
 */

#include <stdint.h>

uint32_t fma_model_ieee(uint32_t x, uint32_t y, uint32_t z) { // Compute x * y + z
  // Unpack inputs
#define fp32_unpack(var) \
    int32_t var##_e = (var >> 23) & 255; /* (biased) exponent */ \
    uint64_t var##_m = (var & 0x7fffff) ^ 0x800000; /* mantissa (including implicit bit) */ \
    if (var##_e == 0) { /* convert denormal to something closer to normal */ \
      var##_m ^= 0x800000; \
      var##_e = 9 - __builtin_clz(var##_m | 1); \
      var##_m <<= 1 - var##_e; \
    }
  fp32_unpack(x)
  fp32_unpack(y)
  fp32_unpack(z)
  uint32_t z_sign = z & 0x80000000;
#undef fp32_unpack

  // p = x * y
  uint32_t p_sign = (x ^ y) & 0x80000000;
  uint64_t p_m = (uint64_t)x_m * (uint64_t)y_m;
  int32_t p_e = x_e + y_e - 23 - 127;

  // Add three extra bits of precision (aka. G, R, S bits)
  p_m <<= 3, z_m <<= 3;

  // Handle NaN or Inf input
  if (x_e == 255 || y_e == 255 || z_e == 255) {
    if ((x_e == 255 && (x_m != 0x800000 || y_m == 0)) // x NaN or x Inf times y zero
    ||  (y_e == 255 && (y_m != 0x800000 || x_m == 0)) // y NaN or y Inf times x zero
    ||  (z_e == 255 && z_m != 0x4000000) // z NaN
    ||  (z_e == 255 && (x_e == 255 || y_e == 255) && (z_sign != p_sign))) { // z Inf and (x * y) Inf and signs differ
      return 0x7fc00000; // NaN output
    } else if (z_e == 255) { // z Inf
      return z; // Inf output
    } else { // (x * y) Inf
      return p_sign | 0x7f800000; // Inf output
    }
  }

  // Realign z_m to match p_m (adding 23 bits)
  z_m <<= 23;
  z_e -= 23;

  // Shortcut if p == 0
  if (p_m == 0) return z_m ? z : z_sign & p_sign;

#define sticky_shift(var, amount) \
    do { \
      int32_t s = amount; \
      if (s >= (int32_t)(sizeof(var)*__CHAR_BIT__)) { \
        var = (var != 0); \
      } else { \
        uint64_t orig = var; \
        var >>= s; \
        var |= ((var << s) != orig); \
      } \
    } while(0)
  // r = z + p
  int32_t r_e = p_e > z_e ? p_e : z_e;
  if (p_e < r_e) sticky_shift(p_m, r_e - p_e); // Discard low bits from p_m
  if (z_e < r_e) sticky_shift(z_m, r_e - z_e); // Discard low bits from z_m
  uint32_t r_sign = p_m >= z_m ? p_sign : z_sign;
  if (z_sign != r_sign) z_m = ~z_m;
  if (p_sign != r_sign) p_m = ~p_m;
  uint64_t r_m = z_m + p_m + (p_sign != z_sign);

  // Shortcut if r == 0
  if (r_m == 0) return z_sign & p_sign;

  // Normalise 64-bit result to 37 zero bits, 1 one bit, 26 fractional bits
  int32_t n = 37 - __builtin_clzll(r_m);
  r_e += n;
  if (r_e >= 255) return r_sign | 0x7f800000; // Inf
  if (r_e <= 0) { // Denorm or zero
    n += 1 - r_e;
    r_e = 0;
  }
  if (n <= 0) r_m <<= -n; else sticky_shift(r_m, n);
#undef sticky_shift

  // Start reassembling result
  uint32_t r = (r_e << 23) | ((r_m >> 3) & 0x7fffff);

  // Round to nearest even
  r += (((r_m & 7) + (r & 1)) > 4);

  return r_sign | r;
}

uint32_t fma_model_bh(uint32_t x, uint32_t y, uint32_t z) { // Compute x * y + z
  // Unpack inputs
#define fp32_unpack_no_denorms(var) \
    int32_t var##_e = (var >> 23) & 255; /* (biased) exponent */ \
    uint32_t var##_m = (var & 0x7fffff) ^ 0x800000; /* mantissa (including implicit bit) */ \
    if (var##_e == 0) { /* flush denormals */ \
      var##_m = 0; \
    }
  fp32_unpack_no_denorms(x)
  fp32_unpack_no_denorms(y)
  fp32_unpack_no_denorms(z)
  uint32_t z_sign = z & 0x80000000;
#undef fp32_unpack_no_denorms

  // p = x * y
  uint32_t p_sign = (x ^ y) & 0x80000000;
  uint64_t p_m = (uint64_t)x_m * (uint64_t)y_m;
  int32_t p_e = x_e + y_e - 23 - 127;

  // Add three extra bits of precision (aka. G, R, S bits)
  p_m <<= 3, z_m <<= 3;

  // Realign p_m to match z_m (removing 23 bits)
  p_m = (p_m >> 23) | ((p_m & 0x7fffff) != 0);
  p_e += 23;

  // Handle NaN or Inf input or (x * y) Inf
  if (x_e == 255 || y_e == 255 || p_e >= 255 || z_e == 255) {
    if ((x_e == 255 && (x_m != 0x800000 || y_m == 0)) // x NaN or x Inf times y zero
    ||  (y_e == 255 && (y_m != 0x800000 || x_m == 0)) // y NaN or y Inf times x zero
    ||  (z_e == 255 && z_m != 0x4000000) // z NaN
    ||  (z_e == 255 && (x_e == 255 || y_e == 255) && (z_sign != p_sign))) { // z Inf and (x * y) Inf and signs differ
      return 0x7fc00000; // NaN output
    } else if (z_e == 255) { // z Inf
      return z; // Inf output
    } else { // (x * y) Inf
      return p_sign | 0x7f800000; // Inf output
    }
  }

  // Shortcut if p == 0, or if the multiply on its own would underflow
  if (p_m == 0 || p_e < 0) return z_m ? z : z_sign & p_sign;

#define semi_sticky_shift(var, amount) \
    do { \
      int32_t s = amount; \
      if (s >= (int32_t)(sizeof(var)*__CHAR_BIT__)) { \
        var = 0; \
      } else { \
        uint64_t orig = var; \
        var >>= s; \
        if (var) var |= ((var << s) != orig); \
      } \
    } while(0)
  // r = z + p
  int32_t r_e = p_e > z_e ? p_e : z_e;
  if (p_e < r_e) semi_sticky_shift(p_m, r_e - p_e); // Discard low bits from p_m
  if (z_e < r_e) semi_sticky_shift(z_m, r_e - z_e); // Discard low bits from z_m
  uint32_t r_sign = p_m >= z_m ? p_sign : z_sign;
  if (z_sign != r_sign) z_m = ~z_m;
  if (p_sign != r_sign) p_m = ~p_m;
  uint32_t r_m = z_m + p_m + (p_sign != z_sign);

  // Shortcut if r == 0
  if (r_m == 0) return z_sign & p_sign;

  // Normalise 32-bit result to 5 zero bits, 1 one bit, 26 fractional bits
  int32_t n = 5 - __builtin_clz(r_m);
  r_e += n;
  if (r_e >= 255) return r_sign | 0x7f800000; // Inf
  if (r_e <= 0) { // Denorm or zero
    n += 1;
    r_e = 0;
  }
  if (n <= 0) r_m <<= -n; else r_m = (r_m >> n) | ((r_m & (n | 1)) != 0);
#undef semi_sticky_shift

  // Start reassembling result
  uint32_t r = (r_e << 23) + ((r_m >> 3) & 0x7fffff);

  // Round to nearest even
  r += (((r_m & 7) + (r & 1)) > 4);

  // Flush denormals (after rounding, preserving sign)
  if (!(r >> 23)) r = 0;

  return r_sign | r;
}

uint32_t fma_model_wh(uint32_t x, uint32_t y, uint32_t z) { // Compute x * y + z
  // Unpack inputs
#define fp32_unpack_no_denorms(var) \
    int32_t var##_e = (var >> 23) & 255; /* (biased) exponent */ \
    uint32_t var##_m = (var & 0x7fffff) ^ 0x800000; /* mantissa (including implicit bit) */ \
    if (var##_e == 0) { /* flush denormals */ \
      var##_m = 0; \
    }
  fp32_unpack_no_denorms(x)
  fp32_unpack_no_denorms(y)
  fp32_unpack_no_denorms(z)
  uint32_t z_sign = z & 0x80000000;
#undef fp32_unpack_no_denorms

  // p = x * y
  uint32_t p_sign = (x ^ y) & 0x80000000;
  uint64_t p_m = (uint64_t)x_m * (uint64_t)y_m;
  int32_t p_e = x_e + y_e - 23 - 127;

  // Add three extra bits of precision (aka. G, R, S bits)
  p_m <<= 3, z_m <<= 3;

  // Realign p_m to match z_m (removing 23 bits)
  p_m = (p_m >> 23) | ((p_m & 0x7fffff) != 0);
  p_e += 23;

  // Handle NaN or Inf input or (x * y) Inf
  // Note that NaN results aren't returned immediately; some mantissa bits can subsequently leak in
  uint32_t nan_result = 0;
  if (x_e == 255 || y_e == 255 || p_e >= 255 || z_e == 255) {
    if ((x_e == 255 && (x_m != 0x800000 || y_m == 0)) // x NaN or x Inf times y zero
    ||  (y_e == 255 && (y_m != 0x800000 || x_m == 0)) // y NaN or y Inf times x zero
    ||  (z_e == 255 && z_m == 0x4000000 && (x_e == 255 || y_e == 255 || p_e >= 255) && (z_sign != p_sign))) { // z Inf and (x * y) Inf and signs differ
      nan_result = p_sign | 0x7f800001;
    } else if (z_e == 255 && z_m != 0x4000000) { // z NaN
      nan_result = z_sign | 0x7f800001;
    } else if (z_e == 255) { // z Inf
      return z; // Inf output
    } else { // (x * y) Inf
      return p_sign | 0x7f800000; // Inf output
    }
    if (p_e > 255) p_e = 255;
  }

  // Shortcut if p == 0, or if the multiply on its own would underflow
  if (p_m == 0 || p_e < 0) {
    if (nan_result) {
      p_m = 0, p_e = 0;
    } else {
      return z_m ? z : 0;
    }
  }

#define semi_sticky_shift(var, amount) \
    do { \
      int32_t s = amount; \
      if (s >= (int32_t)(sizeof(var)*__CHAR_BIT__)) { \
        var = 0; \
      } else { \
        uint64_t orig = var; \
        var >>= s; \
        if (var) var |= ((var << s) != orig); \
      } \
    } while(0)
  // r = z + p
  int32_t r_e = p_e > z_e ? p_e : z_e;
  if (p_e < r_e) semi_sticky_shift(p_m, r_e - p_e); // Discard low bits from p_m
  if (z_e < r_e) semi_sticky_shift(z_m, r_e - z_e); // Discard low bits from z_m
  uint32_t r_sign = p_m >= z_m ? p_sign : z_sign;
  if (z_sign != r_sign) z_m = ~z_m;
  if (p_sign != r_sign) p_m = ~p_m;
  uint32_t r_m = z_m + p_m + (p_sign != z_sign);

  // Shortcut if r == 0
  if (r_m == 0) return nan_result;

  // Normalise 32-bit result to 5 zero bits, 1 one bit, 26 fractional bits
  int32_t n = 5 - __builtin_clz(r_m);
  r_e += n;
  if (r_e >= 255) return nan_result ? nan_result : (r_sign | 0x7f800000); // Inf
  if (r_e < 0) { // Flush blatant denormals (before rounding, discarding sign)
    return nan_result;
  }
  if (n <= 0) r_m <<= -n; else r_m = (r_m >> n) | (r_m & 1);
#undef semi_sticky_shift

  // Start reassembling result
  uint32_t r = (r_e << 23) + ((r_m >> 3) & 0x7fffff);

  // Round to nearest even
  r += (((r_m & 7) + (r & 1)) > 4);

  // Flush denormals (after rounding, discarding sign)
  if (!(r >> 23)) return nan_result;

  return (nan_result ? nan_result : r_sign) | r;
}
