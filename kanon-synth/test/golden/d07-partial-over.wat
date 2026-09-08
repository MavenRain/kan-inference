(module
 (type $0 (array (mut i32)))
 (type $1 (struct (field i32) (field (ref func)) (field (ref eq))))
 (type $2 (func (param (ref eq) (ref eq)) (result (ref eq))))
 (type $3 (struct (field (ref eq)) (field (ref eq))))
 (type $4 (struct (field i32) (field (ref $0))))
 (type $5 (func (param (ref eq) (ref eq) (ref eq)) (result (ref eq))))
 (type $6 (func (param (ref eq) (ref eq) (ref $0) i32 i32 i32) (result (ref eq))))
 (type $7 (func (param (ref eq)) (result (ref eq))))
 (type $8 (func (param (ref $1) (ref eq) (ref eq)) (result (ref eq))))
 (type $9 (func (result (ref eq))))
 (type $10 (func (param (ref eq)) (result i32)))
 (type $11 (func (param (ref eq) i32) (result i32)))
 (type $12 (func (param (ref $0) (ref $0) i32 i32) (result (ref $0))))
 (type $13 (func (param (ref $0) i32) (result (ref eq))))
 (type $14 (func (param (ref eq) (ref eq) i32) (result i32)))
 (type $15 (func (param (ref eq) (ref eq)) (result i32)))
 (type $16 (func (result i32)))
 (elem declare func $5 $6 $8)
 (export "main" (func $26))
 (func $0 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (call $21
   (call $21
    (local.get $0)
    (local.get $1)
   )
   (ref.i31
    (i32.const 3)
   )
  )
 )
 (func $1 (type $8) (param $0 (ref $1)) (param $1 (ref eq)) (param $2 (ref eq)) (result (ref eq))
  (local $3 (ref $1))
  (local.set $3
   (ref.cast (ref $1)
    (call $7
     (local.get $0)
     (local.get $1)
    )
   )
  )
  (return_call_ref $2
   (struct.get $1 2
    (local.get $3)
   )
   (local.get $2)
   (ref.cast (ref $2)
    (struct.get $1 1
     (local.get $3)
    )
   )
  )
 )
 (func $2 (type $7) (param $0 (ref eq)) (result (ref eq))
  (local $1 (ref $1))
  (local.set $1
   (ref.cast (ref $1)
    (call $7
     (struct.new $1
      (i32.const 2)
      (ref.func $5)
      (ref.i31
       (i32.const 0)
      )
     )
     (ref.i31
      (i32.const 4)
     )
    )
   )
  )
  (return_call_ref $2
   (struct.get $1 2
    (local.get $1)
   )
   (local.get $0)
   (ref.cast (ref $2)
    (struct.get $1 1
     (local.get $1)
    )
   )
  )
 )
 (func $3 (type $7) (param $0 (ref eq)) (result (ref eq))
  (local $1 (ref $1))
  (local.set $1
   (ref.cast (ref $1)
    (call $7
     (struct.new $1
      (i32.const 2)
      (ref.func $6)
      (ref.i31
       (i32.const 0)
      )
     )
     (ref.i31
      (i32.const 1)
     )
    )
   )
  )
  (return_call_ref $2
   (struct.get $1 2
    (local.get $1)
   )
   (local.get $0)
   (ref.cast (ref $2)
    (struct.get $1 1
     (local.get $1)
    )
   )
  )
 )
 (func $4 (type $9) (result (ref eq))
  (call $21
   (call $21
    (call $2
     (ref.i31
      (i32.const 5)
     )
    )
    (call $3
     (ref.i31
      (i32.const 2)
     )
    )
   )
   (call $1
    (struct.new $1
     (i32.const 2)
     (ref.func $6)
     (ref.i31
      (i32.const 0)
     )
    )
    (ref.i31
     (i32.const 4)
    )
    (ref.i31
     (i32.const 6)
    )
   )
  )
 )
 (func $5 (type $5) (param $0 (ref eq)) (param $1 (ref eq)) (param $2 (ref eq)) (result (ref eq))
  (return_call $0
   (local.get $1)
   (local.get $2)
  )
 )
 (func $6 (type $5) (param $0 (ref eq)) (param $1 (ref eq)) (param $2 (ref eq)) (result (ref eq))
  (return_call $21
   (local.get $1)
   (local.get $2)
  )
 )
 (func $7 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (local $2 (ref $1))
  (local $3 i32)
  (local.set $2
   (ref.cast (ref $1)
    (local.get $0)
   )
  )
  (local.set $3
   (struct.get $1 0
    (local.get $2)
   )
  )
  (if (result (ref eq))
   (i32.eq
    (local.get $3)
    (i32.const 2)
   )
   (then
    (struct.new $1
     (i32.const 1)
     (ref.func $8)
     (struct.new $3
      (local.get $0)
      (local.get $1)
     )
    )
   )
   (else
    (if
     (i32.eq
      (local.get $3)
      (i32.const 1)
     )
     (then
      (return_call_ref $2
       (struct.get $1 2
        (local.get $2)
       )
       (local.get $1)
       (ref.cast (ref $2)
        (struct.get $1 1
         (local.get $2)
        )
       )
      )
     )
     (else
      (unreachable)
     )
    )
   )
  )
 )
 (func $8 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (local $2 (ref $3))
  (local $3 (ref $1))
  (local.set $2
   (ref.cast (ref $3)
    (local.get $0)
   )
  )
  (local.set $3
   (ref.cast (ref $1)
    (struct.get $3 0
     (local.get $2)
    )
   )
  )
  (return_call_ref $5
   (struct.get $1 2
    (local.get $3)
   )
   (struct.get $3 1
    (local.get $2)
   )
   (local.get $1)
   (ref.cast (ref $5)
    (struct.get $1 1
     (local.get $3)
    )
   )
  )
 )
 (func $9 (type $10) (param $0 (ref eq)) (result i32)
  (local $1 i32)
  (local.set $1
   (i31.get_u
    (block $block (result (ref i31))
     (return
      (array.len
       (struct.get $4 1
        (ref.cast (ref $4)
         (br_on_cast $block (ref eq) (ref i31)
          (local.get $0)
         )
        )
       )
      )
     )
    )
   )
  )
  (if (result i32)
   (i32.eq
    (local.get $1)
    (i32.const 0)
   )
   (then
    (i32.const 0)
   )
   (else
    (if (result i32)
     (i32.lt_u
      (local.get $1)
      (i32.const 32768)
     )
     (then
      (i32.const 1)
     )
     (else
      (i32.const 2)
     )
    )
   )
  )
 )
 (func $10 (type $11) (param $0 (ref eq)) (param $1 i32) (result i32)
  (local $2 (ref $0))
  (local $3 i32)
  (local.set $3
   (i31.get_u
    (block $block (result (ref i31))
     (local.set $2
      (struct.get $4 1
       (ref.cast (ref $4)
        (br_on_cast $block (ref eq) (ref i31)
         (local.get $0)
        )
       )
      )
     )
     (return
      (if (result i32)
       (i32.lt_u
        (local.get $1)
        (array.len
         (local.get $2)
        )
       )
       (then
        (array.get $0
         (local.get $2)
         (local.get $1)
        )
       )
       (else
        (i32.const 0)
       )
      )
     )
    )
   )
  )
  (if (result i32)
   (i32.eq
    (local.get $1)
    (i32.const 0)
   )
   (then
    (i32.sub
     (local.get $3)
     (i32.mul
      (i32.div_u
       (local.get $3)
       (i32.const 32768)
      )
      (i32.const 32768)
     )
    )
   )
   (else
    (if (result i32)
     (i32.eq
      (local.get $1)
      (i32.const 1)
     )
     (then
      (i32.div_u
       (local.get $3)
       (i32.const 32768)
      )
     )
     (else
      (i32.const 0)
     )
    )
   )
  )
 )
 (func $11 (type $12) (param $0 (ref $0)) (param $1 (ref $0)) (param $2 i32) (param $3 i32) (result (ref $0))
  (if (result (ref $0))
   (i32.lt_u
    (local.get $2)
    (local.get $3)
   )
   (then
    (array.set $0
     (local.get $1)
     (local.get $2)
     (array.get $0
      (local.get $0)
      (local.get $2)
     )
    )
    (return_call $11
     (local.get $0)
     (local.get $1)
     (i32.add
      (local.get $2)
      (i32.const 1)
     )
     (local.get $3)
    )
   )
   (else
    (local.get $1)
   )
  )
 )
 (func $12 (type $13) (param $0 (ref $0)) (param $1 i32) (result (ref eq))
  (if (result (ref eq))
   (i32.eq
    (local.get $1)
    (i32.const 0)
   )
   (then
    (ref.i31
     (i32.const 0)
    )
   )
   (else
    (if (result (ref eq))
     (i32.eq
      (array.get $0
       (local.get $0)
       (i32.sub
        (local.get $1)
        (i32.const 1)
       )
      )
      (i32.const 0)
     )
     (then
      (return_call $12
       (local.get $0)
       (i32.sub
        (local.get $1)
        (i32.const 1)
       )
      )
     )
     (else
      (if (result (ref eq))
       (i32.lt_u
        (local.get $1)
        (i32.const 3)
       )
       (then
        (ref.i31
         (i32.add
          (array.get $0
           (local.get $0)
           (i32.const 0)
          )
          (if (result i32)
           (i32.eq
            (local.get $1)
            (i32.const 2)
           )
           (then
            (i32.mul
             (array.get $0
              (local.get $0)
              (i32.const 1)
             )
             (i32.const 32768)
            )
           )
           (else
            (i32.const 0)
           )
          )
         )
        )
       )
       (else
        (struct.new $4
         (i32.const 1)
         (call $11
          (local.get $0)
          (array.new $0
           (i32.const 0)
           (local.get $1)
          )
          (i32.const 0)
          (local.get $1)
         )
        )
       )
      )
     )
    )
   )
  )
 )
 (func $13 (type $14) (param $0 (ref eq)) (param $1 (ref eq)) (param $2 i32) (result i32)
  (local $3 i32)
  (local $4 i32)
  (if (result i32)
   (i32.eq
    (local.get $2)
    (i32.const 0)
   )
   (then
    (i32.const 0)
   )
   (else
    (local.set $2
     (i32.sub
      (local.get $2)
      (i32.const 1)
     )
    )
    (local.set $3
     (call $10
      (local.get $0)
      (local.get $2)
     )
    )
    (local.set $4
     (call $10
      (local.get $1)
      (local.get $2)
     )
    )
    (if (result i32)
     (i32.eq
      (local.get $3)
      (local.get $4)
     )
     (then
      (return_call $13
       (local.get $0)
       (local.get $1)
       (local.get $2)
      )
     )
     (else
      (if (result i32)
       (i32.lt_u
        (local.get $3)
        (local.get $4)
       )
       (then
        (i32.const 1)
       )
       (else
        (i32.const 2)
       )
      )
     )
    )
   )
  )
 )
 (func $14 (type $15) (param $0 (ref eq)) (param $1 (ref eq)) (result i32)
  (local $2 i32)
  (local $3 i32)
  (local.set $2
   (call $9
    (local.get $0)
   )
  )
  (local.set $3
   (call $9
    (local.get $1)
   )
  )
  (if (result i32)
   (i32.eq
    (local.get $2)
    (local.get $3)
   )
   (then
    (return_call $13
     (local.get $0)
     (local.get $1)
     (local.get $2)
    )
   )
   (else
    (if (result i32)
     (i32.lt_u
      (local.get $2)
      (local.get $3)
     )
     (then
      (i32.const 1)
     )
     (else
      (i32.const 2)
     )
    )
   )
  )
 )
 (func $15 (type $6) (param $0 (ref eq)) (param $1 (ref eq)) (param $2 (ref $0)) (param $3 i32) (param $4 i32) (param $5 i32) (result (ref eq))
  (local $6 i32)
  (if (result (ref eq))
   (i32.eq
    (local.get $3)
    (local.get $4)
   )
   (then
    (array.set $0
     (local.get $2)
     (local.get $3)
     (local.get $5)
    )
    (return_call $12
     (local.get $2)
     (i32.add
      (local.get $4)
      (i32.const 1)
     )
    )
   )
   (else
    (local.set $6
     (i32.add
      (i32.add
       (call $10
        (local.get $0)
        (local.get $3)
       )
       (call $10
        (local.get $1)
        (local.get $3)
       )
      )
      (local.get $5)
     )
    )
    (array.set $0
     (local.get $2)
     (local.get $3)
     (i32.sub
      (local.get $6)
      (i32.mul
       (i32.div_u
        (local.get $6)
        (i32.const 32768)
       )
       (i32.const 32768)
      )
     )
    )
    (return_call $15
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (i32.add
      (local.get $3)
      (i32.const 1)
     )
     (local.get $4)
     (i32.div_u
      (local.get $6)
      (i32.const 32768)
     )
    )
   )
  )
 )
 (func $16 (type $6) (param $0 (ref eq)) (param $1 (ref eq)) (param $2 (ref $0)) (param $3 i32) (param $4 i32) (param $5 i32) (result (ref eq))
  (local $6 i32)
  (local $7 i32)
  (local $8 i32)
  (if (result (ref eq))
   (i32.eq
    (local.get $3)
    (local.get $4)
   )
   (then
    (return_call $12
     (local.get $2)
     (local.get $4)
    )
   )
   (else
    (local.set $6
     (call $10
      (local.get $0)
      (local.get $3)
     )
    )
    (local.set $7
     (i32.add
      (call $10
       (local.get $1)
       (local.get $3)
      )
      (local.get $5)
     )
    )
    (local.set $5
     (i32.lt_u
      (local.get $6)
      (local.get $7)
     )
    )
    (local.set $8
     (if (result i32)
      (local.get $5)
      (then
       (i32.sub
        (i32.add
         (local.get $6)
         (i32.const 32768)
        )
        (local.get $7)
       )
      )
      (else
       (i32.sub
        (local.get $6)
        (local.get $7)
       )
      )
     )
    )
    (array.set $0
     (local.get $2)
     (local.get $3)
     (local.get $8)
    )
    (return_call $16
     (local.get $0)
     (local.get $1)
     (local.get $2)
     (i32.add
      (local.get $3)
      (i32.const 1)
     )
     (local.get $4)
     (local.get $5)
    )
   )
  )
 )
 (func $17 (type $6) (param $0 (ref eq)) (param $1 (ref eq)) (param $2 (ref $0)) (param $3 i32) (param $4 i32) (param $5 i32) (result (ref eq))
  (local $6 i32)
  (local $7 i32)
  (local $8 i32)
  (local.set $7
   (call $9
    (local.get $0)
   )
  )
  (local.set $8
   (call $9
    (local.get $1)
   )
  )
  (if (result (ref eq))
   (i32.eq
    (local.get $3)
    (local.get $7)
   )
   (then
    (return_call $12
     (local.get $2)
     (array.len
      (local.get $2)
     )
    )
   )
   (else
    (if (result (ref eq))
     (i32.eq
      (local.get $4)
      (local.get $8)
     )
     (then
      (array.set $0
       (local.get $2)
       (i32.add
        (local.get $3)
        (local.get $4)
       )
       (local.get $5)
      )
      (return_call $17
       (local.get $0)
       (local.get $1)
       (local.get $2)
       (i32.add
        (local.get $3)
        (i32.const 1)
       )
       (i32.const 0)
       (i32.const 0)
      )
     )
     (else
      (local.set $6
       (i32.add
        (i32.add
         (i32.mul
          (call $10
           (local.get $0)
           (local.get $3)
          )
          (call $10
           (local.get $1)
           (local.get $4)
          )
         )
         (array.get $0
          (local.get $2)
          (i32.add
           (local.get $3)
           (local.get $4)
          )
         )
        )
        (local.get $5)
       )
      )
      (array.set $0
       (local.get $2)
       (i32.add
        (local.get $3)
        (local.get $4)
       )
       (i32.sub
        (local.get $6)
        (i32.mul
         (i32.div_u
          (local.get $6)
          (i32.const 32768)
         )
         (i32.const 32768)
        )
       )
      )
      (return_call $17
       (local.get $0)
       (local.get $1)
       (local.get $2)
       (local.get $3)
       (i32.add
        (local.get $4)
        (i32.const 1)
       )
       (i32.div_u
        (local.get $6)
        (i32.const 32768)
       )
      )
     )
    )
   )
  )
 )
 (func $18 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (local $2 i32)
  (local $3 i32)
  (local.set $2
   (call $9
    (local.get $0)
   )
  )
  (local.set $3
   (call $9
    (local.get $1)
   )
  )
  (if
   (i32.lt_u
    (local.get $2)
    (local.get $3)
   )
   (then
    (local.set $2
     (local.get $3)
    )
   )
   (else
   )
  )
  (return_call $15
   (local.get $0)
   (local.get $1)
   (array.new $0
    (i32.const 0)
    (i32.add
     (local.get $2)
     (i32.const 1)
    )
   )
   (i32.const 0)
   (local.get $2)
   (i32.const 0)
  )
 )
 (func $19 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (if (result (ref eq))
   (i32.eq
    (call $14
     (local.get $0)
     (local.get $1)
    )
    (i32.const 1)
   )
   (then
    (ref.i31
     (i32.const 0)
    )
   )
   (else
    (return_call $16
     (local.get $0)
     (local.get $1)
     (array.new $0
      (i32.const 0)
      (call $9
       (local.get $0)
      )
     )
     (i32.const 0)
     (call $9
      (local.get $0)
     )
     (i32.const 0)
    )
   )
  )
 )
 (func $20 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (return_call $17
   (local.get $0)
   (local.get $1)
   (array.new $0
    (i32.const 0)
    (i32.add
     (call $9
      (local.get $0)
     )
     (call $9
      (local.get $1)
     )
    )
   )
   (i32.const 0)
   (i32.const 0)
   (i32.const 0)
  )
 )
 (func $21 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
  (local.set $2
   (i31.get_u
    (block $block (result (ref i31))
     (local.set $0
      (br_on_cast $block (ref eq) (ref i31)
       (local.get $0)
      )
     )
     (return_call $18
      (local.get $0)
      (local.get $1)
     )
    )
   )
  )
  (local.set $3
   (i31.get_u
    (block $block1 (result (ref i31))
     (local.set $1
      (br_on_cast $block1 (ref eq) (ref i31)
       (local.get $1)
      )
     )
     (return_call $18
      (local.get $0)
      (local.get $1)
     )
    )
   )
  )
  (local.set $4
   (i32.add
    (local.get $2)
    (local.get $3)
   )
  )
  (if (result (ref eq))
   (i32.gt_u
    (local.get $4)
    (i32.const 1073741823)
   )
   (then
    (return_call $18
     (local.get $0)
     (local.get $1)
    )
   )
   (else
    (ref.i31
     (local.get $4)
    )
   )
  )
 )
 (func $22 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
  (local.set $2
   (i31.get_u
    (block $block (result (ref i31))
     (local.set $0
      (br_on_cast $block (ref eq) (ref i31)
       (local.get $0)
      )
     )
     (return_call $19
      (local.get $0)
      (local.get $1)
     )
    )
   )
  )
  (local.set $3
   (i31.get_u
    (block $block1 (result (ref i31))
     (local.set $1
      (br_on_cast $block1 (ref eq) (ref i31)
       (local.get $1)
      )
     )
     (return_call $19
      (local.get $0)
      (local.get $1)
     )
    )
   )
  )
  (ref.i31
   (if (result i32)
    (i32.lt_u
     (local.get $2)
     (local.get $3)
    )
    (then
     (i32.const 0)
    )
    (else
     (i32.sub
      (local.get $2)
      (local.get $3)
     )
    )
   )
  )
 )
 (func $23 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
  (local.set $2
   (i31.get_u
    (block $block (result (ref i31))
     (local.set $0
      (br_on_cast $block (ref eq) (ref i31)
       (local.get $0)
      )
     )
     (return_call $20
      (local.get $0)
      (local.get $1)
     )
    )
   )
  )
  (local.set $3
   (i31.get_u
    (block $block1 (result (ref i31))
     (local.set $1
      (br_on_cast $block1 (ref eq) (ref i31)
       (local.get $1)
      )
     )
     (return_call $20
      (local.get $0)
      (local.get $1)
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
    (ref.i31
     (i32.const 0)
    )
   )
   (else
    (if (result (ref eq))
     (i32.gt_u
      (local.get $3)
      (i32.div_u
       (i32.const 1073741823)
       (local.get $2)
      )
     )
     (then
      (return_call $20
       (local.get $0)
       (local.get $1)
      )
     )
     (else
      (ref.i31
       (i32.mul
        (local.get $2)
        (local.get $3)
       )
      )
     )
    )
   )
  )
 )
 (func $24 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
  (local.set $2
   (i31.get_u
    (block $block (result (ref i31))
     (local.set $0
      (br_on_cast $block (ref eq) (ref i31)
       (local.get $0)
      )
     )
     (return
      (ref.i31
       (i32.eq
        (call $14
         (local.get $0)
         (local.get $1)
        )
        (i32.const 0)
       )
      )
     )
    )
   )
  )
  (local.set $3
   (i31.get_u
    (block $block1 (result (ref i31))
     (local.set $1
      (br_on_cast $block1 (ref eq) (ref i31)
       (local.get $1)
      )
     )
     (return
      (ref.i31
       (i32.eq
        (call $14
         (local.get $0)
         (local.get $1)
        )
        (i32.const 0)
       )
      )
     )
    )
   )
  )
  (ref.i31
   (i32.eq
    (local.get $2)
    (local.get $3)
   )
  )
 )
 (func $25 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
  (local.set $2
   (i31.get_u
    (block $block (result (ref i31))
     (local.set $0
      (br_on_cast $block (ref eq) (ref i31)
       (local.get $0)
      )
     )
     (return
      (ref.i31
       (i32.eq
        (call $14
         (local.get $0)
         (local.get $1)
        )
        (i32.const 1)
       )
      )
     )
    )
   )
  )
  (local.set $3
   (i31.get_u
    (block $block1 (result (ref i31))
     (local.set $1
      (br_on_cast $block1 (ref eq) (ref i31)
       (local.get $1)
      )
     )
     (return
      (ref.i31
       (i32.eq
        (call $14
         (local.get $0)
         (local.get $1)
        )
        (i32.const 1)
       )
      )
     )
    )
   )
  )
  (ref.i31
   (i32.lt_u
    (local.get $2)
    (local.get $3)
   )
  )
 )
 (func $26 (type $16) (result i32)
  (i31.get_s
   (ref.cast (ref i31)
    (call $4)
   )
  )
 )
)
