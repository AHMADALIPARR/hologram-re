-- SPDX-License-Identifier: AGPL-3.0-only
-- Team B model: geometric_window with the real MIN_WINDOW = 64, at 10-bit Int.
-- Analyzed source: hologram-ai @ c9609c0 (MIT OR Apache-2.0), crates/hologram-ai/src/engine.rs:37-52
-- Kept in its own module and split into small asserts: at 10-bit Int each check needs
-- roughly 15-60 s with SAT4J/MiniSat on this box. Alloy checks this model, not the Rust.
module B_window64

fun clampWant[want, mx: Int]: Int { (want < 1) => 1 else ((want > mx) => mx else want) }
fun bucketAtLeast64[c: Int]: Int { (c =< 64) => 64 else ((c =< 128) => 128 else 256) }
fun geo64[want, mx: Int]: Int { let b = bucketAtLeast64[clampWant[want, mx]] | (b < mx) => b else mx }

one sig P { want, mx: Int }
-- max_window in [1, 256] so the bucket list 64,128,256 is complete; want in [1, 300].
pred inRange { P.mx >= 1 and P.mx =< 256 and P.want >= 1 and P.want =< 300 }

-- B-GEN-1a: window <= max_window.
assert geoLeMax_m64 { inRange implies geo64[P.want, P.mx] =< P.mx }
check geoLeMax_m64 for 1 but 10 int expect 0

-- B-GEN-1b: want <= max_window  =>  window >= want.
assert geoCoversWant_m64 { (inRange and P.want =< P.mx) implies geo64[P.want, P.mx] >= P.want }
check geoCoversWant_m64 for 1 but 10 int expect 0

-- B-GEN-1c: want > max_window  =>  window = max_window (silent cap, no error).
assert geoCapsAtMax_m64 { (inRange and P.want > P.mx) implies geo64[P.want, P.mx] = P.mx }
check geoCapsAtMax_m64 for 1 but 10 int expect 0

-- B-GEN-1d: the window is one of 64, 128, 256 or exactly max_window.
assert geoIsBucketOrCap_m64 { inRange implies geo64[P.want, P.mx] in (64 + 128 + 256 + P.mx) }
check geoIsBucketOrCap_m64 for 1 but 10 int expect 0

pred nonVacuous64 { inRange and P.want = 65 and P.mx = 200 and geo64[P.want, P.mx] = 128 }
run nonVacuous64 for 1 but 10 int expect 1
