;; Copyright (c) 2026 SNAPKITTYAGENT9NOVA
;; SPDX-License-Identifier: AGPL-3.0-only
;;
;; Clean hand-written WebAssembly for the hologram-parametric quant kernels.
;; Mirrors crates/hologram-ai-quant/src/{q4_0,q8_0}.rs exactly:
;;   Q8_0 block = 34 bytes: [u16 LE f16 scale][32 x i8], weight = q * scale
;;   Q4_0 block = 18 bytes: [u16 LE f16 scale][16 bytes, low nibble first],
;;                weight = (nibble - 8) * scale
;;
;; All functions operate on the exported linear memory. Callers write the
;; block bytes at $block and read 32 f32 values (128 bytes) at $out.

(module
  (memory (export "memory") 1)

  ;; f16 -> f32, full IEEE 754 semantics:
  ;; signed zero, subnormals (mant * 2^-24), infinities, NaN.
  ;; $b carries the 16 bits in its low half.
  (func (export "f16_to_f32") (param $b i32) (result f32)
    (local $sign i32)
    (local $exp i32)
    (local $mant i32)
    (local.set $sign
      (i32.and (i32.shr_u (local.get $b) (i32.const 15)) (i32.const 1)))
    (local.set $exp
      (i32.and (i32.shr_u (local.get $b) (i32.const 10)) (i32.const 31)))
    (local.set $mant (i32.and (local.get $b) (i32.const 1023)))
    (if (result f32) (i32.eqz (local.get $exp))
      (then
        ;; exp == 0: zero or subnormal. value = mant * 2^-24, signed.
        ;; (mant == 0 falls out naturally: 0.0, negated to -0.0 when signed.)
        (if (result f32) (i32.eqz (local.get $sign))
          (then (f32.mul
                  (f32.convert_i32_s (local.get $mant))
                  (f32.const 0x1p-24)))
          (else (f32.neg (f32.mul
                  (f32.convert_i32_s (local.get $mant))
                  (f32.const 0x1p-24))))))
      (else
        (if (result f32) (i32.eq (local.get $exp) (i32.const 31))
          (then
            ;; exp == 31: infinity (mant == 0) or NaN.
            (f32.reinterpret_i32
              (i32.or
                (i32.shl (local.get $sign) (i32.const 31))
                (if (result i32) (i32.eqz (local.get $mant))
                  (then (i32.const 0x7F800000))
                  (else (i32.or
                          (i32.const 0x7FC00000)
                          (i32.shl (local.get $mant) (i32.const 13))))))))
          (else
            ;; Normal: rebias exponent (exp - 15 + 127 = exp + 112),
            ;; shift 10-bit mantissa into the top of the 23-bit field.
            (f32.reinterpret_i32
              (i32.or
                (i32.shl (local.get $sign) (i32.const 31))
                (i32.or
                  (i32.shl
                    (i32.add (local.get $exp) (i32.const 112))
                    (i32.const 23))
                  (i32.shl (local.get $mant) (i32.const 13))))))))))

  ;; Dequantize one Q8_0 block.
  ;; $block: 34 input bytes. $out: 128 output bytes (32 x f32, little-endian).
  (func (export "dequant_q8_0_block")
    (param $block i32) (param $out i32)
    (local $scale f32)
    (local $i i32)
    (local $q i32)
    (local.set $scale
      (call 0 (i32.load16_u (local.get $block))))
    (local.set $i (i32.const 0))
    (loop $l
      (local.set $q
        (i32.load8_s (i32.add (local.get $block)
                             (i32.add (i32.const 2) (local.get $i)))))
      (f32.store
        (i32.add (local.get $out)
                 (i32.shl (local.get $i) (i32.const 2)))
        (f32.mul (f32.convert_i32_s (local.get $q)) (local.get $scale)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (i32.const 32)))))

  ;; Dequantize one Q4_0 block.
  ;; $block: 18 input bytes. $out: 128 output bytes (32 x f32, little-endian).
  (func (export "dequant_q4_0_block")
    (param $block i32) (param $out i32)
    (local $scale f32)
    (local $i i32)
    (local $byte i32)
    (local $lo i32)
    (local $hi i32)
    (local.set $scale
      (call 0 (i32.load16_u (local.get $block))))
    (local.set $i (i32.const 0))
    (loop $l
      (local.set $byte
        (i32.load8_u (i32.add (local.get $block)
                              (i32.add (i32.const 2) (local.get $i)))))
      (local.set $lo
        (i32.sub (i32.and (local.get $byte) (i32.const 15)) (i32.const 8)))
      (local.set $hi
        (i32.sub
          (i32.and (i32.shr_u (local.get $byte) (i32.const 4)) (i32.const 15))
          (i32.const 8)))
      ;; out[2*i] = lo * scale ; out[2*i+1] = hi * scale
      (f32.store
        (i32.add (local.get $out) (i32.shl (local.get $i) (i32.const 3)))
        (f32.mul (f32.convert_i32_s (local.get $lo)) (local.get $scale)))
      (f32.store
        (i32.add
          (i32.add (local.get $out) (i32.shl (local.get $i) (i32.const 3)))
          (i32.const 4))
        (f32.mul (f32.convert_i32_s (local.get $hi)) (local.get $scale)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (i32.const 16)))))
)
