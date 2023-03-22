module F (Ty : Typed.T) = struct
  open Termlang.F (Ty)

  type rty_kind = RtyLib | RtyToCheck

  type entry =
    | Mps of string list
    | Type_dec of Type_dec.t
    | Func_dec of string Normalty.Ntyped.typed
    | FuncImp of { name : string; if_rec : bool; body : term typed }
    | Rty of { name : string; kind : rty_kind; rty : unit }

  type t = entry list

  open Sugar
  open Zzdatatype.Datatype

  let mk_normal_top_ctx_ = function
    | Mps _ | FuncImp _ -> []
    | Rty _ -> _failatwith __FILE__ __LINE__ "unimp"
    | Func_dec x -> [ x ]
    | Type_dec d -> Type_dec.mk_ctx_ d

  let mk_normal_top_ctx es = List.concat @@ List.map mk_normal_top_ctx_ es

  let map_imps f codes =
    List.map
      (fun code ->
        match code with
        | FuncImp { name; if_rec; body } ->
            FuncImp { name; if_rec; body = f name if_rec body }
        | _ -> code)
      codes
end
