(module
 (type $0 (struct (field (ref eq)) (field (ref eq))))
 (type $1 (func (param (ref eq)) (result (ref $0))))
 (type $2 (func (result (ref eq))))
 (type $3 (func (result i32)))
 (export "main" (func $2))
 (func $0 (type $1) (param $0 (ref eq)) (result (ref $0))
  (struct.new $0
   (local.get $0)
   (local.get $0)
  )
 )
 (func $1 (type $2) (result (ref eq))
  (local $0 (ref $0))
  (local $1 (ref eq))
  (local $2 (ref eq))
  (local.set $0
   (call $0
    (ref.i31
     (i32.const 5)
    )
   )
  )
  (local.set $1
   (struct.get $0 0
    (local.get $0)
   )
  )
  (local.set $2
   (struct.get $0 1
    (local.get $0)
   )
  )
  (local.get $1)
 )
 (func $2 (type $3) (result i32)
  (i31.get_s
   (ref.cast (ref i31)
    (call $1)
   )
  )
 )
)
