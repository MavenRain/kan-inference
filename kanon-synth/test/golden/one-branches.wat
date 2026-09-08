(module
 (type $0 (struct (field (ref i31)) (field (ref eq))))
 (type $1 (func (param (ref eq) (ref eq)) (result (ref eq))))
 (type $2 (func (param (ref eq)) (result (ref eq))))
 (type $3 (func (result (ref eq))))
 (type $4 (func (result i32)))
 (export "main" (func $4))
 (func $0 (type $1) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (local $2 (ref eq))
  (local $3 i32)
  (local.set $2
   (local.get $1)
  )
  (local.set $3
   (block (result i32)
    (i31.get_u
     (block $block (result (ref i31))
      (drop
       (br_on_cast $block (ref eq) (ref i31)
        (local.get $2)
       )
      )
      (unreachable)
     )
    )
   )
  )
  (if (result (ref eq))
   (i32.eq
    (local.get $3)
    (i32.const 0)
   )
   (then
    (local.get $0)
   )
   (else
    (if (result (ref eq))
     (i32.eq
      (local.get $3)
      (i32.const 1)
     )
     (then
      (local.get $0)
     )
     (else
      (unreachable)
     )
    )
   )
  )
 )
 (func $1 (type $1) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (local $2 (ref eq))
  (local $3 i32)
  (local $4 (ref eq))
  (local $5 i32)
  (local.set $2
   (local.get $1)
  )
  (local.set $3
   (block (result i32)
    (i31.get_u
     (block $block (result (ref i31))
      (drop
       (br_on_cast $block (ref eq) (ref i31)
        (local.get $2)
       )
      )
      (unreachable)
     )
    )
   )
  )
  (if (result (ref eq))
   (i32.eq
    (local.get $3)
    (i32.const 0)
   )
   (then
    (local.set $4
     (local.get $1)
    )
    (local.set $5
     (block (result i32)
      (i31.get_u
       (block $block1 (result (ref i31))
        (drop
         (br_on_cast $block1 (ref eq) (ref i31)
          (local.get $4)
         )
        )
        (unreachable)
       )
      )
     )
    )
    (if (result (ref eq))
     (i32.eq
      (local.get $5)
      (i32.const 0)
     )
     (then
      (local.get $0)
     )
     (else
      (if (result (ref eq))
       (i32.eq
        (local.get $5)
        (i32.const 1)
       )
       (then
        (local.get $0)
       )
       (else
        (unreachable)
       )
      )
     )
    )
   )
   (else
    (if (result (ref eq))
     (i32.eq
      (local.get $3)
      (i32.const 1)
     )
     (then
      (local.get $0)
     )
     (else
      (unreachable)
     )
    )
   )
  )
 )
 (func $2 (type $2) (param $0 (ref eq)) (result (ref eq))
  (local $1 (ref eq))
  (local $2 i32)
  (local $3 (ref eq))
  (local $4 (ref eq))
  (local.set $1
   (local.get $0)
  )
  (local.set $2
   (block $block2 (result i32)
    (i31.get_u
     (struct.get $0 0
      (block $block1 (result (ref $0))
       (br $block2
        (i31.get_u
         (block $block (result (ref i31))
          (drop
           (br_on_cast $block1 (ref eq) (ref $0)
            (br_on_cast $block (ref eq) (ref i31)
             (local.get $1)
            )
           )
          )
          (unreachable)
         )
        )
       )
      )
     )
    )
   )
  )
  (if (result (ref eq))
   (i32.eq
    (local.get $2)
    (i32.const 0)
   )
   (then
    (local.set $3
     (struct.get $0 1
      (ref.cast (ref $0)
       (local.get $1)
      )
     )
    )
    (local.get $3)
   )
   (else
    (if (result (ref eq))
     (i32.eq
      (local.get $2)
      (i32.const 1)
     )
     (then
      (local.set $4
       (struct.get $0 1
        (ref.cast (ref $0)
         (local.get $1)
        )
       )
      )
      (local.get $4)
     )
     (else
      (unreachable)
     )
    )
   )
  )
 )
 (func $3 (type $3) (result (ref eq))
  (return_call $0
   (ref.i31
    (i32.const 7)
   )
   (ref.i31
    (i32.const 0)
   )
  )
 )
 (func $4 (type $4) (result i32)
  (i31.get_s
   (ref.cast (ref i31)
    (call $3)
   )
  )
 )
)
