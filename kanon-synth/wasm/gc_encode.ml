(** The byte encoder of the WasmGC subset, SPEC.md section 8.  This file
    holds no knowledge of the erased form:  it takes a module value of
    indices and instructions and answers the binary text.  link.ml owns
    the indices and emit.ml owns the instruction lists.

    A type section entry is one rec group (D-M1-5).  A group of one
    member is the plain final form of the composite type, 0x5F for a
    struct and 0x60 for a function, with no rec byte and no [sub] form:
    that is the M0 shape of SD-D17 and it keeps the bytes of every M0
    module.  A group of two or more members is the rec opcode 0x4E, the
    member count and one sub final entry per member, 0x4F with an empty
    supertype vector (A8).  The index of a type stays its position in
    the flat reading of the groups, which is the invariant [types]
    carries.

    Stage K adds i32 arrays with field mutability 1 for fresh Nat limbs.
    Struct fields remain immutable; only array construction stores.

    SD-D18:  [byte] is the one site with a byte buffer.  The buffer never
    leaves the function and its byte adder takes an integer, so the
    encoder holds no partial accessor and no other state that changes.
    Every
    other function builds its answer by concatenation. *)

type heaptype =
  | HEq  (** the eq hierarchy:  every M0 value is an eq reference *)
  | HI31  (** the tagged integer *)
  | HFunc  (** the generic function reference, the closure code field *)
  | HType of int  (** a defined type index *)

type valtype =
  | I32
  | Ref of heaptype  (** the non null reference form, 0x64 *)

type comptype =
  | CStruct of valtype list  (** every field is immutable *)
  | CArray of valtype  (** field mutability 1, used while constructing limbs *)
  | CFunc of valtype list * valtype list

(** One arm per mnemonic of SPEC.md section 8.  [Block] and [If] carry
    their bodies, so the end byte and the else byte are structural and
    are not arms of their own. *)
type instr =
  | Unreachable
  | Block of valtype option * instr list
  | If of valtype option * instr list * instr list
  | Br of int
  | Br_if of int
  | Br_on_cast of int * heaptype * heaptype
  | Return
  | Call of int
  | Return_call of int
  | Call_ref of int
  | Return_call_ref of int
  | Local_get of int
  | Local_set of int
  | Local_tee of int
  | I32_const of int
  | I32_add
  | I32_sub
  | I32_mul
  | I32_div_u
  | I32_eq
  | I32_ne
  | I32_lt_u
  | I32_gt_u
  | Ref_i31
  | I31_get_s
  | I31_get_u
  | Ref_cast of heaptype
  | Ref_func of int
  | Struct_new of int
  | Struct_get of int * int
  | Array_new of int
  | Array_get of int
  | Array_set of int
  | Array_len

type func = {
  ftype : int;  (** the index of this function's type *)
  locals : valtype list;  (** the locals after the parameters, in order *)
  body : instr list;
}

type modul = {
  types : comptype list list;
      (** one rec group per entry;  the index of a type is its position
          in the concatenation of the groups *)
  funcs : func list;  (** the index of a function is its position *)
  exports : (string * int) list;
  declared : int list;  (** the functions the module declares *)
}

(** SD-D18.  The buffer is local, it holds one byte and it is read once. *)
let byte (n : int) : string =
  let b : Buffer.t = Buffer.create 1 in
  Buffer.add_uint8 b (n land 255);
  Buffer.contents b

(** LEB128, unsigned.  The continuation bit marks every byte but the
    last one. *)
let rec uleb (n : int) : string =
  if n < 128 then byte n
  else byte (128 lor (n land 127)) ^ uleb (n lsr 7) (* SD-M1 site *)

(** LEB128, signed.  The sign bit of the last byte carries the sign, so
    the walk stops on 0 with a clear bit six and on -1 with a set one. *)
let rec sleb (n : int) : string =
  let low : int = n land 127 in
  let rest : int = n asr 7 in
  let last : bool =
    (Int.equal rest 0 && Int.equal (low land 64) 0)
    || (Int.equal rest (-1) && not (Int.equal (low land 64) 0))
  in
  if last then byte low else byte (128 lor low) ^ sleb rest

(** A heap type rides in a reference type as a signed 33 bit number:  a
    defined type is its index and an abstract type is a negative code. *)
let heaptype (h : heaptype) : string =
  match h with
  | HEq -> sleb (-19)
  | HI31 -> sleb (-20)
  | HFunc -> sleb (-16)
  | HType i -> sleb i

let valtype (v : valtype) : string =
  match v with
  | I32 -> byte 0x7F
  | Ref h -> byte 0x64 ^ heaptype h

let vec (f : 'a -> string) (xs : 'a list) : string =
  uleb (List.length xs) ^ String.concat "" (List.map f xs)

(** A field of a struct is a storage type and a mutability byte.  Every
    M0 field is immutable, so the byte is always zero. *)
let field (v : valtype) : string = valtype v ^ byte 0x00

let comptype (c : comptype) : string =
  match c with
  | CStruct fields -> byte 0x5F ^ vec field fields
  | CArray v -> byte 0x5E ^ valtype v ^ byte 0x01
  | CFunc (params, results) -> byte 0x60 ^ vec valtype params ^ vec valtype results

(** A member of a multi-member group is a sub final entry:  0x4F, the
    empty vector of supertypes and the composite type. *)
let sub_final (c : comptype) : string = byte 0x4F ^ uleb 0 ^ comptype c

(** One type section entry.  A group of one keeps the M0 bytes and a
    group of two or more takes the rec opcode (D-M1-5, A8). *)
let rectype (g : comptype list) : string =
  match g with
  | [ c ] -> comptype c
  | [] -> byte 0x4E ^ uleb 0
  | _c1 :: _c2 :: _rest ->
      byte 0x4E ^ uleb (List.length g) ^ String.concat "" (List.map sub_final g)

let blocktype (b : valtype option) : string =
  Option.fold ~none:(byte 0x40) ~some:valtype b

(** The GC prefix, 0xFB, and the opcode after it. *)
let gc (op : int) : string = byte 0xFB ^ uleb op

let rec instr (i : instr) : string =
  match i with
  | Unreachable -> byte 0x00
  | Block (bt, body) -> byte 0x02 ^ blocktype bt ^ instrs body ^ byte 0x0B
  | If (bt, t, e) ->
      byte 0x04 ^ blocktype bt ^ instrs t ^ byte 0x05 ^ instrs e ^ byte 0x0B
  | Br l -> byte 0x0C ^ uleb l
  | Br_if l -> byte 0x0D ^ uleb l
  | Br_on_cast (l, src, dst) ->
      (* The flags byte answers whether the source and the target admit a
         null reference.  Every M0 reference is non null, so it is zero. *)
      gc 24 ^ byte 0x00 ^ uleb l ^ heaptype src ^ heaptype dst
  | Return -> byte 0x0F
  | Call f -> byte 0x10 ^ uleb f
  | Return_call f -> byte 0x12 ^ uleb f (* SD-M2 site *)
  | Call_ref t -> byte 0x14 ^ uleb t
  | Return_call_ref t -> byte 0x15 ^ uleb t
  | Local_get n -> byte 0x20 ^ uleb n
  | Local_set n -> byte 0x21 ^ uleb n
  | Local_tee n -> byte 0x22 ^ uleb n
  | I32_const n -> byte 0x41 ^ sleb n
  | I32_add -> byte 0x6A
  | I32_sub -> byte 0x6B
  | I32_mul -> byte 0x6C
  | I32_div_u -> byte 0x6E
  | I32_eq -> byte 0x46
  | I32_ne -> byte 0x47
  | I32_lt_u -> byte 0x49
  | I32_gt_u -> byte 0x4B
  | Ref_i31 -> gc 28
  | I31_get_s -> gc 29
  | I31_get_u -> gc 30
  | Ref_cast h -> gc 22 ^ heaptype h
  | Ref_func f -> byte 0xD2 ^ uleb f
  | Struct_new t -> gc 0 ^ uleb t
  | Struct_get (t, f) -> gc 2 ^ uleb t ^ uleb f
  | Array_new t -> gc 6 ^ uleb t
  | Array_get t -> gc 11 ^ uleb t
  | Array_set t -> gc 14 ^ uleb t
  | Array_len -> gc 15

and instrs (xs : instr list) : string = String.concat "" (List.map instr xs)

let section (id : int) (payload : string) : string =
  byte id ^ uleb (String.length payload) ^ payload

(** One entry of the locals vector for every local, so the encoder never
    compares two types to compress a run. *)
let locals (ls : valtype list) : string =
  vec (fun (v : valtype) -> uleb 1 ^ valtype v) ls

let code_entry (f : func) : string =
  let payload : string = locals f.locals ^ instrs f.body ^ byte 0x0B in
  uleb (String.length payload) ^ payload

let name (s : string) : string = uleb (String.length s) ^ s

let export_entry ((n : string), (idx : int)) : string =
  name n ^ byte 0x00 ^ uleb idx

(** The one element segment is declarative, flag 3, with the function
    kind byte and a vector of function indices (SD-D1).  A function
    reference reads a function only when this segment declares it. *)
let elem_segment (fs : int list) : string = uleb 3 ^ byte 0x00 ^ vec uleb fs

let magic : string = "\x00asm\x01\x00\x00\x00"

(** The sections in the order the format fixes:  type, function, export,
    element, code.  The element section is left out when no function
    reference reads a function (SD-D15:  the module has no import, table, memory,
    global, start or data section). *)
let encode (m : modul) : string =
  let type_section : string = section 1 (vec rectype m.types) in
  let func_section : string =
    section 3 (vec (fun (f : func) -> uleb f.ftype) m.funcs)
  in
  let export_section : string = section 7 (vec export_entry m.exports) in
  let elem_section : string =
    if Int.equal (List.length m.declared) 0 then ""
    else section 9 (uleb 1 ^ elem_segment m.declared)
  in
  let code_section : string = section 10 (vec code_entry m.funcs) in
  magic ^ type_section ^ func_section ^ export_section ^ elem_section
  ^ code_section
