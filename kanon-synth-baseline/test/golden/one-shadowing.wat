(module
 (type $0 (struct (field i32) (field (ref func)) (field (ref eq))))
 (type $1 (func (param (ref eq) (ref eq)) (result (ref eq))))
 (type $2 (func (param (ref eq)) (result (ref eq))))
 (type $3 (struct (field (ref eq))))
 (type $4 (func (result (ref eq))))
 (type $5 (func (result i32)))
 (elem declare func $5)
 (export "main" (func $6))
 (func $0 (type $2) (param $0 (ref eq)) (result (ref eq))
  (local.get $0)
 )
 (func $1 (type $2) (param $0 (ref eq)) (result (ref eq))
  (local $1 (ref eq))
  (local $2 (ref eq))
  (local.set $1
   (local.get $0)
  )
  (local.set $2
   (ref.i31
    (i32.const 0)
   )
  )
  (local.get $1)
 )
 (func $2 (type $1) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (local.get $0)
 )
 (func $3 (type $2) (param $0 (ref eq)) (result (ref eq))
  (local $1 (ref $0))
  (local $2 (ref $0))
  (local.set $1
   (struct.new $0
    (i32.const 1)
    (ref.func $5)
    (struct.new $3
     (local.get $0)
    )
   )
  )
  (local.set $2
   (local.get $1)
  )
  (return_call_ref $1
   (struct.get $0 2
    (local.get $2)
   )
   (ref.i31
    (i32.const 0)
   )
   (ref.cast (ref $1)
    (struct.get $0 1
     (local.get $2)
    )
   )
  )
 )
 (func $4 (type $4) (result (ref eq))
  (return_call $1
   (ref.i31
    (i32.const 7)
   )
  )
 )
 (func $5 (type $1) (param $0 (ref eq)) (param $1 (ref eq)) (result (ref eq))
  (return_call $2
   (struct.get $3 0
    (ref.cast (ref $3)
     (local.get $0)
    )
   )
   (local.get $1)
  )
 )
 (func $6 (type $5) (result i32)
  (i31.get_s
   (ref.cast (ref i31)
    (call $4)
   )
  )
 )
)
