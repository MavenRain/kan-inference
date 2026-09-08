(module
 (type $0 (array (mut i32)))
 (type $1 (func (result (ref eq))))
 (type $2 (struct (field i32) (field (ref $0))))
 (type $3 (func (result i32)))
 (export "main" (func $1))
 (func $0 (type $1) (result (ref eq))
  (local $0 (ref $0))
  (local.set $0
   (array.new $0
    (i32.const 0)
    (i32.const 7)
   )
  )
  (array.set $0
   (local.get $0)
   (i32.const 0)
   (i32.const 277)
  )
  (array.set $0
   (local.get $0)
   (i32.const 1)
   (i32.const 23667)
  )
  (array.set $0
   (local.get $0)
   (i32.const 2)
   (i32.const 9925)
  )
  (array.set $0
   (local.get $0)
   (i32.const 3)
   (i32.const 13814)
  )
  (array.set $0
   (local.get $0)
   (i32.const 4)
   (i32.const 13092)
  )
  (array.set $0
   (local.get $0)
   (i32.const 5)
   (i32.const 31875)
  )
  (array.set $0
   (local.get $0)
   (i32.const 6)
   (i32.const 9)
  )
  (struct.new $2
   (i32.const 1)
   (local.get $0)
  )
 )
 (func $1 (type $3) (result i32)
  (i31.get_s
   (ref.cast (ref i31)
    (call $0)
   )
  )
 )
)
