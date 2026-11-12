// Swift calling convention for `static func f()` in a protocol extension:
// x0 = Self metadata, x1 = witness table, x20 = Self metatype (context).
.text
.globl _la_call_static_on_type
.p2align 2
_la_call_static_on_type:
  stp x29, x30, [sp, #-32]!
  stp x20, x21, [sp, #16]
  mov x29, sp
  mov x9, x0
  mov x0, x1
  mov x20, x1
  mov x1, x2
  blr x9
  ldp x20, x21, [sp, #16]
  ldp x29, x30, [sp], #32
  ret
