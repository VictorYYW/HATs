include Head
open Zzdatatype.Datatype
open Language
open Rty
open Sugar

let minterm_to_op_model { global_tab; local_tab }
    NRegex.{ op; global_embedding; local_embedding } =
  let global_m = tab_i_to_b global_tab global_embedding in
  let m = StrMap.find "minterm_to_op_model" local_tab op in
  let local_m = tab_i_to_b m local_embedding in
  (global_m, local_m)

let display_trace rctx ctx mt_list =
  match List.last_destruct_opt mt_list with
  | Some (mt_list, ret_mt) ->
      let global_m, ret_m = minterm_to_op_model ctx ret_mt in
      let mt_list =
        List.map
          (fun mt ->
            let _, m = minterm_to_op_model ctx mt in
            m)
          mt_list
      in
      let () = Printf.printf "Gamma:\n" in
      let () = Printf.printf "%s\n" @@ PTypectx.layout_typed_l rctx in
      let () = Printf.printf "Global:\n" in
      let () = pprint_bool_tab global_m in
      let () =
        List.iteri
          (fun idx m ->
            let () = Printf.printf "[<%i>]:\n" idx in
            let () = pprint_bool_tab m in
            ())
          mt_list
      in
      let () = Printf.printf "[Ret]:\n" in
      let () = pprint_bool_tab ret_m in
      ()
  | None -> Printf.printf "Empty trace ϵ\n"

let model_verify_bool sub_pty_bool (global_m, local_m) =
  match local_m with
  | EmptyTab | LitTab _ ->
      let m = merge_global_to_local global_m local_m in
      let lhs_pty = Rty.mk_unit_pty_from_prop @@ tab_to_prop m in
      let rhs_pty = Rty.mk_unit_pty_from_prop mk_false in
      let local_vars = tab_vs m in
      let res = not (sub_pty_bool local_vars (lhs_pty, rhs_pty)) in
      let () =
        Pp.printf "@{<bold>%s@} ≮: %s\n@{<bold>Result:@} %b\n"
          (Rty.layout_pty lhs_pty) (Rty.layout_pty rhs_pty) res
      in
      res
      (* let () = *)
      (*   Printf.printf "local_vars: %s\n" *)
      (*     (List.split_by ", " *)
      (*        (fun Rty.{ x; ty } -> spf "%s:%s" x (Rty.layout_pty ty)) *)
      (*        local_vars) *)
      (* in *)
  | PtyTab { ptytab = local_m } ->
      let ctxurty = Rty.mk_unit_pty_from_prop @@ tab_to_prop global_m in
      let binding = { px = Rename.unique "a"; pty = ctxurty } in
      let pos_set =
        List.filter_map (fun (k, v) -> if v then Some k else None)
        @@ List.of_seq @@ PtyMap.to_seq local_m
      in
      let neg_set =
        List.filter_map (fun (k, v) -> if not v then Some k else None)
        @@ List.of_seq @@ PtyMap.to_seq local_m
      in
      (* let () = *)
      (*   Printf.printf "pos_set: %s\n" *)
      (*   @@ List.split_by_comma Rty.layout_pty pos_set *)
      (* in *)
      (* let () = *)
      (*   Printf.printf "neg_set: %s\n" *)
      (*   @@ List.split_by_comma Rty.layout_pty neg_set *)
      (* in *)
      let nty = ptytab_get_nty local_m in
      let lhs_pty = Auxtyping.common_sub_ptys nty neg_set in
      let rhs_pty = Auxtyping.common_sup_ptys nty pos_set in
      let b = not (sub_pty_bool [ binding ] (lhs_pty, rhs_pty)) in
      let () =
        Pp.printf "%s |- %s ≮: @{<bold>%s@}\n@{<bold>Result:@} %b\n"
          ((fun { pty; _ } -> spf "%s" (Rty.layout_pty pty)) binding)
          (Rty.layout_pty lhs_pty) (Rty.layout_pty rhs_pty) b
      in
      (* let () = failwith "end" in *)
      (* let () = Pp.printf "@{<bold>if_valid: %b@}\n" b in *)
      b

let minterm_verify_bool sub_pty_bool ctx mt =
  let model = minterm_to_op_model ctx mt in
  model_verify_bool sub_pty_bool model

let op_models m prop =
  let rec aux prop =
    match prop with
    | Lit (AC (Const.B b)) -> b
    | Lit lit -> tab_models_lit m lit
    | Implies (a, b) -> (not (aux a)) || aux b
    | Ite (a, b, c) -> if aux a then aux b else aux c
    | Not a -> not (aux a)
    | And es -> List.for_all aux es
    | Or es -> List.exists aux es
    | Iff (a, b) -> aux (Implies (a, b)) && aux (Implies (b, a))
    | Forall _ | Exists _ -> _failatwith __FILE__ __LINE__ "die"
  in
  aux prop

let ret_models local_m pty =
  let local_m =
    match local_m with
    | LitTab _ | EmptyTab -> _failatwith __FILE__ __LINE__ "die"
    | PtyTab { ptytab = m } -> m
  in
  PtyMap.find pty local_m

(* let minterm_to_qualifier { optab; _ } (op, n) = *)
(*   let mt_map = StrMap.find "minterm die" optab op in *)
(*   let len = LitMap.cardinal mt_map.lit_to_idx in *)
(*   let l = id_to_bl len n [] in *)
(*   let props = *)
(*     List.mapi *)
(*       (fun i b -> *)
(*         let lit = Lit (IntMap.find "minterm die" mt_map.idx_to_lit i) in *)
(*         if b then lit else Not lit) *)
(*       l *)
(*   in *)
(*   And props *)

open Rty

let models_event ctx mt = function
  | RetEvent pty ->
      if String.equal mt.NRegex.op ret_name then
        let _, local_m = minterm_to_op_model ctx mt in
        ret_models local_m pty
      else false
  | GuardEvent _ ->
      _failatwith __FILE__ __LINE__ "die"
      (* | GuardEvent phi -> *)
      (* let global_m, _ = minterm_to_op_model ctx mt in *)
      (* op_models global_m phi *)
  | EffEvent { op; phi; _ } ->
      if String.equal mt.NRegex.op op then
        let global_m, local_m = minterm_to_op_model ctx mt in
        let m = merge_global_to_local global_m local_m in
        op_models m phi
      else false

let desymbolic_sevent ctx mts se =
  let open NRegex in
  match se with
  | GuardEvent phi ->
      let l = mts_to_global_m mts in
      let l =
        List.filter
          (fun global_embedding ->
            let m = tab_i_to_b ctx.global_tab global_embedding in
            op_models m phi)
          l
      in
      if List.length l > 0 then Epsilon else Empt
  | _ ->
      let op = se_get_op se in
      let mts =
        NRegex.mts_fold_on_op op
          (fun mt res ->
            if models_event ctx mt se then NRegex.Minterm mt :: res else res)
          mts []
      in
      if List.length mts > 0 then Union mts else Empt

(* NOTE: the None indicate the empty set *)
let desymbolic ctx mts regex =
  let open NRegex in
  let rec aux regex =
    match regex with
    | EmptyA -> Empt
    | AnyA -> Any
    | EpsilonA -> Epsilon
    | EventA se -> desymbolic_sevent ctx mts se
    | LorA (t1, t2) -> Union [ aux t1; aux t2 ]
    | LandA (t1, t2) -> Intersect [ aux t1; aux t2 ]
    | SeqA (t1, t2) -> Concat [ aux t1; aux t2 ]
    | StarA t -> Star (aux t)
    | ComplementA t -> Complement (aux t)
  in
  let res = aux regex in
  simp res