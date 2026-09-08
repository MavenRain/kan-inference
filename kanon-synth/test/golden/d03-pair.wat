(module
 (type $0 (array (mut i32)))
 (type $1 (struct (field (ref eq)) (field (ref eq))))
 (type $2 (func (param (ref eq) (ref eq)) (result (ref eq))))
 (type $3 (struct (field i32) (field (ref $0))))
 (type $4 (func (param (ref eq) (ref eq) (ref $0) i32 i32 i32) (result (ref eq))))
 (type $5 (func (result (ref $1))))
 (type $6 (func (param (ref eq)) (result (ref $1))))
 (type $7 (func (result (ref eq))))
 (type $8 (func (param (ref eq)) (result i32)))
 (type $9 (func (param (ref eq) i32) (result i32)))
 (type $10 (func (param (ref $0) (ref $0) i32 i32) (result (ref $0))))
 (type $11 (func (param (ref $0) i32) (result (ref eq))))
 (type $12 (func (param (ref eq) (ref eq) i32) (result i32)))
 (type $13 (func (param (ref eq) (ref eq)) (result i32)))
 (type $14 (func (result i32)))
 (export "main" (func $21))
 (func $0 (type $5) (result (ref $1))
  (struct.new $1
   (ref.i31
    (i32.const 11)
   )
   (ref.i31
    (i32.const 6)
   )
  )
 )
 (func $1 (type $6) (param $0 (ref eq)) (result (ref $1))
  (struct.new $1
   (local.get $0)
   (call $16
    (local.get $0)
    (ref.i31
     (i32.const 1)
    )
   )
  )
 )
 (func $2 (type $5) (result (ref $1))
  (return_call $1
   (ref.i31
    (i32.const 4)
   )
  )
 )
 (func $3 (type $7) (result (ref eq))
  (local $0 (ref $1))
  (local $1 (ref eq))
  (local $2 (ref eq))
  (local $3 (ref $1))
  (local $4 (ref eq))
  (local $5 (ref eq))
  (local $6 (ref $1))
  (local $7 (ref eq))
  (local $8 (ref eq))
  (local $9 (ref $1))
  (local $10 (ref eq))
  (local $11 (ref eq))
  (local.set $0
   (call $0)
  )
  (local.set $1
   (struct.get $1 0
    (local.get $0)
   )
  )
  (local.set $2
   (struct.get $1 1
    (local.get $0)
   )
  )
  (call $16
   (call $16
    (local.get $1)
    (block (result (ref eq))
     (local.set $3
      (call $0)
     )
     (local.set $4
      (struct.get $1 0
       (local.get $3)
      )
     )
     (local.set $5
      (struct.get $1 1
       (local.get $3)
      )
     )
     (local.get $5)
    )
   )
   (block (result (ref eq))
    (local.set $6
     (call $2)
    )
    (local.set $7
     (struct.get $1 0
      (local.get $6)
     )
    )
    (local.set $8
     (struct.get $1 1
      (local.get $6)
     )
    )
    (call $16
     (local.get $7)
     (block (result (ref eq))
      (local.set $9
       (call $2)
      )
      (local.set $10
       (struct.get $1 0
        (local.get $9)
       )
      )
      (local.set $11
       (struct.get $1 1
        (local.get $9)
       )
      )
      (local.get $11)
     )
    )
   )
  )
 )
 (func $4 (type $8) (param $0 (ref eq)) (result i32)
  (local $1 i32)
  (local.set $1
   (i31.get_u
    (block $block (result (ref i31))
     (return
      (array.len
       (struct.get $3 1
        (ref.cast (ref $3)
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
 (func $5 (type $9) (param $0 (ref eq)) (param $1 i32) (result i32)
  (local $2 (ref $0))
  (local $3 i32)
  (local.set $3
   (i31.get_u
    (block $block (result (ref i31))
     (local.set $2
      (struct.get $3 1
       (ref.cast (ref $3)
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
 (func $6 (type $10) (param $0 (ref $0)) (param $1 (ref $0)) (param $2 i32) (param $3 i32) (result (ref $0))
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
    (return_call $6
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
 (func $7 (type $11) (param $0 (ref $0)) (param $1 i32) (result (ref eq))
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
      (return_call $7
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
        (struct.new $3
         (i32.const 1)
         (call $6
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
 (func $8 (type $12) (param $0 (ref eq)) (param $1 (ref eq)) (param $2 i32) (result i32)
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
     (call $5
      (local.get $0)
      (local.get $2)
     )
    )
    (local.set $4
     (call $5
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
      (return_call $8
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
 (func $9 (type $13) (param $0 (ref eq)) (param $1 (ref eq)) (result i32)
  (local $2 i32)
  (local $3 i32)
  (local.set $2
   (call $4
    (local.get $0)
   )
  )
  (local.set $3
   (call $4
    (local.get $1)
   )
  )
  (if (result i32)
   (i32.eq
    (local.get $2)
    (local.get $3)
   )
   (then
    (return_call $8
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
 (func $10 (type $4) (param $0 (ref eq)) (param $1 (ref eq)) (param $2 (ref $0)) (param $3 i32) (param $4 i32) (param $5 i32) (result (ref eq))
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
    (return_call $7
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
       (call $5
        (local.get $0)
        (local.get $3)
       )
       (call $5
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
    (return_call $10
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
 (func $11 (type $4) (param $0 (ref eq)) (param $1 (ref eq)) (param $2 (ref $0)) (param $3 i32) (param $4 i32) (param $5 i32) (result (ref eq))
  (local $6 i32)
  (local $7 i32)
  (local $8 i32)
  (if (result (ref eq))
   (i32.eq
    (local.get $3)
    (local.get $4)
   )
   (then
    (return_call $7
     (local.get $2)
     (local.get $4)
    )
   )
   (else
    (local.set $6
     (call $5
      (local.get $0)
      (local.get $3)
     )
    )
    (local.set $7
     (i32.add
      (call $5
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
    (return_call $11
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
 (func $12 (type $4) (param $0 (ref eq)) (param $1 (ref eq)) (param $2 (ref $0)) (param $3 i32) (param $4 i32) (param $5 i32) (result (ref eq))
  (local $6 i32)
  (local $7 i32)
  (local $8 i32)
  (local.set $7
   (call $4
    (local.get $0)
   )
  )
  (local.set $8
   (call $4
    (local.get $1)
   )
  )
  (if (result (ref eq))
   (i32.eq
    (local.get $3)
    (local.get $7)
   )
   (then
    (return_call $7
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
      (return_call $12
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
          (call $5
           (local.get $0)
           (local.get $3)
          )
          (call $5
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
      (return_call $12
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
 (func $13 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (local $2 i32)
  (local $3 i32)
  (local.set $2
   (call $4
    (local.get $0)
   )
  )
  (local.set $3
   (call $4
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
  (return_call $10
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
 (func $14 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (if (result (ref eq))
   (i32.eq
    (call $9
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
    (return_call $11
     (local.get $0)
     (local.get $1)
     (array.new $0
      (i32.const 0)
      (call $4
       (local.get $0)
      )
     )
     (i32.const 0)
     (call $4
      (local.get $0)
     )
     (i32.const 0)
    )
   )
  )
 )
 (func $15 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (return_call $12
   (local.get $0)
   (local.get $1)
   (array.new $0
    (i32.const 0)
    (i32.add
     (call $4
      (local.get $0)
     )
     (call $4
      (local.get $1)
     )
    )
   )
   (i32.const 0)
   (i32.const 0)
   (i32.const 0)
  )
 )
 (func $16 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
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
     (return_call $13
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
     (return_call $13
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
    (return_call $13
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
 (func $17 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
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
     (return_call $14
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
     (return_call $14
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
 (func $18 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
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
     (return_call $15
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
     (return_call $15
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
      (return_call $15
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
 (func $19 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
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
        (call $9
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
        (call $9
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
 (func $20 (type $2) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
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
        (call $9
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
        (call $9
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
 (func $21 (type $14) (result i32)
  (i31.get_s
   (ref.cast (ref i31)
    (call $3)
   )
  )
 )
)
