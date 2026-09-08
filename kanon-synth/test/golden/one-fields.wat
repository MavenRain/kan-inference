(module
 (type $0 (struct (field (ref i31)) (field (ref eq))))
 (type $1 (struct (field (ref eq)) (field (ref eq))))
 (type $2 (func (param (ref eq)) (result (ref eq))))
 (type $3 (func (param (ref eq)) (result (ref $1))))
 (type $4 (func (result (ref eq))))
 (type $5 (func (result i32)))
 (export "main" (func $4))
 (func $0 (type $2) (param $0 (ref eq)) (result (ref eq))
  (struct.new $0
   (ref.i31
    (i32.const 0)
   )
   (local.get $0)
  )
 )
 (func $1 (type $2) (param $0 (ref eq)) (result (ref eq))
  (local $1 (ref eq))
  (local $2 i32)
  (local $3 (ref eq))
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
    (unreachable)
   )
  )
 )
 (func $2 (type $3) (param $0 (ref eq)) (result (ref $1))
  (struct.new $1
   (local.get $0)
   (ref.i31
    (i32.const 0)
   )
  )
 )
 (func $3 (type $4) (result (ref eq))
  (return_call $1
   (call $0
    (ref.i31
     (i32.const 7)
    )
   )
  )
 )
 (func $4 (type $5) (result i32)
  (i31.get_s
   (ref.cast (ref i31)
    (call $3)
   )
  )
 )
)
