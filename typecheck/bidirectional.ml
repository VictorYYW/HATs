include Baux
open Language
open TypedCoreEff
open Sugar
open Rty

let app_subst (appf_arg, v) appf_ret =
  match appf_arg.rx with
  | None -> appf_ret
  | Some x ->
      let lit = _value_to_lit __FILE__ __LINE__ v in
      subst (x, lit.x) appf_ret

let unify_arr_ret v (arr, rethty) =
  match arr with
  | NormalArr x ->
      let lit = _value_to_lit __FILE__ __LINE__ v in
      let rethty = subst_hty (x.rx, lit.x) rethty in
      (Some x, rethty)
  | GhostArr x ->
      let lit = _value_to_lit __FILE__ __LINE__ v in
      let rethty = subst_hty (x.x, lit.x) rethty in
      (Some { rx = x.x; rty = mk_top x.ty }, rethty)
  | ArrArr _ -> (None, rethty)

let unify_arr v hty =
  let arr, rethty = rty_destruct_arr __FILE__ __LINE__ hty in
  unify_arr_ret v (arr, rethty)

let case_cond_mapping =
  [
    ("True", mk_rty_var_eq_c Nt.bool_ty (Const.B true));
    ("False", mk_rty_var_eq_c Nt.bool_ty (Const.B false));
  ]

(* NOTE: The value term can only have pure refinement type (or a type error). *)
let rec value_type_infer typectx (value : value typed) : rty option =
  let str = layout_value value in
  let before_info line rulename =
    print_infer_info1 __FUNCTION__ line rulename typectx str
  in
  let end_info line rulename hty =
    let hty_str =
      let* hty' = hty in
      Some (layout_rty hty')
    in
    print_infer_info2 __FUNCTION__ line rulename typectx str hty_str;
    hty
  in
  let hty =
    match value.x with
    | VConst c ->
        let () = before_info __LINE__ "Const" in
        let hty =
          match c with
          | Const.U -> unit_rty
          | _ -> mk_rty_var_eq_c value.Nt.ty c
        in
        end_info __LINE__ "Const" (Some hty)
    | VVar x ->
        let () = before_info __LINE__ "Var" in
        let* rty = RCtx.get_ty_opt typectx.rctx x in
        let res =
          match rty with
          | ArrRty _ -> rty
          | BaseRty _ -> (
              match erase_rty rty with
              | Nt.Ty_unit -> rty
              | _ -> mk_rty_var_eq_var Nt.(x #: (erase_rty rty)))
        in
        end_info __LINE__ "Var" (Some res)
    | VTu _ -> _failatwith __FILE__ __LINE__ "unimp"
    | VLam _ | VFix _ ->
        _failatwith __FILE__ __LINE__
          "type synthesis of functions are disallowed"
  in
  hty

and value_type_check typectx (value : value typed) (hty : rty) : unit option =
  let str = layout_value value in
  let before_info line rulename =
    print_check_info __FUNCTION__ line rulename typectx str (layout_rty hty)
  in
  let end_info line rulename is_valid =
    print_typing_rule __FUNCTION__ line "Check"
      (spf "%s [%s]" rulename
         (match is_valid with Some _ -> "✓" | None -> "𐄂"));
    is_valid
  in
  let end_info_b line rulename b =
    let is_valid = if b then Some () else None in
    end_info line rulename is_valid
  in
  match value.x with
  | VConst _ ->
      let rulename = "Const" in
      let () = before_info __LINE__ rulename in
      let b =
        match value_type_infer typectx value with
        | None -> false
        | Some hty' -> subtyping_rty_bool __FILE__ __LINE__ typectx (hty', hty)
      in
      end_info_b __LINE__ rulename b
  | VVar _ ->
      let rulename = "Var" in
      let () = before_info __LINE__ rulename in
      let b =
        match value_type_infer typectx value with
        | None -> false
        | Some hty' -> subtyping_rty_bool __FILE__ __LINE__ typectx (hty', hty)
      in
      end_info_b __LINE__ rulename b
  | VFix { fixname; fixarg; fixbody } ->
      let rulename = "Fix" in
      let () = before_info __LINE__ rulename in
      let typectx' = typectx_new_to_right typectx fixname.x #:: hty in
      let value' = (VLam { lamarg = fixarg; lambody = fixbody }) #: value.ty in
      let res = value_type_check typectx' value' hty in
      end_info __LINE__ rulename res
  | VLam { lamarg; lambody } ->
      let rulename = "Lam" in
      let () = before_info __LINE__ rulename in
      let rarg, rethty = unify_arr (VVar lamarg.x) #: lamarg.ty hty in
      let typectx' = typectx_newopt_to_right typectx rarg in
      let res = comp_type_check typectx' lambody rethty in
      end_info __LINE__ rulename res
  | VTu _ -> _failatwith __FILE__ __LINE__ "die"

and app_type_infer_aux typectx (hty : rty) (apparg : value typed) : hty option =
  let arr, rethty = rty_destruct_arr __FILE__ __LINE__ hty in
  match arr with
  | NormalArr x ->
      let* () = value_type_check typectx apparg x.rty in
      Some (snd @@ unify_arr_ret apparg (arr, rethty))
  | GhostArr _ ->
      _failatwith __FILE__ __LINE__ "unimp"
      (* Some (snd @@ unify_arr_ret apparg (arr, rethty)) *)
  | ArrArr rty ->
      let* () = value_type_check typectx apparg rty in
      Some rethty

and multi_app_type_infer_aux typectx (f_hty : rty) (appargs : value typed list)
    : hty option =
  List.fold_left
    (fun f_hty apparg ->
      let* f_hty = f_hty in
      let rty = hty_force_rty f_hty in
      app_type_infer_aux typectx rty apparg)
    (Some (Rty f_hty)) appargs

(* and comp_type_check (typectx : typectx) (comp : comp typed) (hty : hty) *)
(*   : bool = *)

(* and split_typectx { typectx; curA; preA } x (rhs_regex : regex) = *)
(*   let rhs_regexs = Auxtyping.branchize_regex rhs_regex in *)
(*   let () = _force_not_emrty_list __FILE__ __LINE__ rhs_regexs in *)
(*   List.map *)
(*     (fun (curA', rty) -> *)
(*       let curA = smart_seq (curA, curA') in *)
(*       let typectx = typectx_new_to_right typectx x #:: rty in *)
(*       let typectx = { typectx; curA; preA } in *)
(*       typectx) *)
(*     rhs_regexs *)

and comp_type_check (typectx : typectx) (comp : comp typed) (hty : hty) :
    unit option =
  match hty with
  | Rty _ -> failwith "unimp"
  | Htriple { pre; resrty; post } ->
      comp_htriple_check typectx comp (pre, resrty, post)
  | Inter (hty1, hty2) ->
      let* () = comp_type_check typectx comp hty1 in
      let* () = comp_type_check typectx comp hty2 in
      Some ()

and comp_htriple_check (typectx : typectx) (comp : comp typed)
    (pre, resrty, post) : unit option =
  let str = layout_comp comp in
  let before_info line rulename =
    print_check_info __FUNCTION__ line rulename typectx str
      (layout_hty (Htriple { pre; resrty; post }))
  in
  let end_info line rulename is_valid =
    print_typing_rule __FUNCTION__ line "Check"
      (spf "%s [%s]" rulename
         (match is_valid with Some _ -> "✓" | None -> "𐄂"));
    is_valid
  in
  let let_aux typectx (lhs, rhs_hty) letbody (pre, resrty, post) =
    let rec aux rhs_hty =
      match rhs_hty with
      | Rty rty ->
          let typectx' = typectx_new_to_right typectx { rx = lhs.x; rty } in
          comp_htriple_check typectx' letbody (pre, resrty, post)
      | Htriple { resrty = rty; post = post'; _ } ->
          let typectx' = typectx_new_to_right typectx { rx = lhs.x; rty } in
          comp_htriple_check typectx' letbody
            (LandA (SeqA (pre, StarA AnyA), post'), resrty, post)
      | Inter (hty1, hty2) ->
          let* () = aux hty1 in
          let* () = aux hty2 in
          Some ()
    in
    aux rhs_hty
  in
  let comp_htriple_check_letappop rulename typectx (lhs, op, appopargs, letbody)
      hty =
    let () = before_info __LINE__ rulename in
    let f_hty = ROpCtx.get_ty typectx.opctx op.x in
    let* rhs_hty = multi_app_type_infer_aux typectx f_hty appopargs in
    let res = let_aux typectx (lhs, rhs_hty) letbody hty in
    end_info __LINE__ rulename res
  in
  let comp_htriple_check_letapppop = comp_htriple_check_letappop "TPOpApp" in
  let comp_htriple_check_letappeop = comp_htriple_check_letappop "TEOpApp" in
  let comp_htriple_check_letapp typectx (lhs, appf, apparg, letbody) hty =
    let rulename = "LetApp" in
    let () = before_info __LINE__ rulename in
    let* appf_rty = value_type_infer typectx appf in
    let* rhs_hty = app_type_infer_aux typectx appf_rty apparg in
    let res = let_aux typectx (lhs, rhs_hty) letbody hty in
    end_info __LINE__ rulename res
  in
  let handle_match_case typectx (matched, { constructor; args; exp }) hty =
    let _, fty =
      List.find (fun (x, _) -> String.equal constructor.x x) case_cond_mapping
    in
    let xs, rethty =
      List.fold_left
        (fun (xs, fty) x ->
          let value = (VVar x.x) #: x.ty in
          let fty = hty_force_rty fty in
          let rx, retty = unify_arr value fty in
          let xs = match rx with None -> xs | Some x -> xs @ [ x ] in
          (xs, retty))
        ([], Rty fty) args
    in
    let { v; phi } = hty_force_cty rethty in
    let matched_lit = _value_to_lit __FILE__ __LINE__ matched in
    let phi = P.subst_prop (v.x, matched_lit.x) phi in
    let a_rty = mk_unit_rty_from_prop phi in
    if subtyping_rty_is_bot_bool __FILE__ __LINE__ typectx a_rty then
      let () =
        Env.show_debug_typing @@ fun _ ->
        Pp.printf "@{<bold>@{<orange>matched case (%s) is unreachable@}@}\n"
          constructor.x
      in
      None
    else
      let a = (Rename.unique "a") #:: a_rty in
      let typectx' = typectx_new_to_rights typectx (xs @ [ a ]) in
      let res = comp_htriple_check typectx' exp hty in
      let () =
        Env.show_debug_typing @@ fun _ ->
        Pp.printf "@{<bold>@{<orange>matched case (%s): %b@}@}\n" constructor.x
          (match res with Some _ -> true | None -> false)
      in
      res
  in
  match comp.x with
  | CVal v ->
      let* () = value_type_check typectx v #: comp.ty resrty in
      if subtyping_srl_bool __FILE__ __LINE__ typectx (pre, post) then Some ()
      else None
  | CLetE { lhs; rhs; letbody } -> (
      match rhs.x with
      | CVal v ->
          let rulename = "LetValue" in
          let () = before_info __LINE__ rulename in
          let* rty = value_type_infer typectx v #: comp.ty in
          let typectx' = typectx_new_to_right typectx lhs.x #:: rty in
          let res = comp_htriple_check typectx' letbody (pre, resrty, post) in
          end_info __LINE__ rulename res
      | CApp { appf; apparg } ->
          comp_htriple_check_letapp typectx
            (lhs, appf, apparg, letbody)
            (pre, resrty, post)
      | CAppOp { op; appopargs } -> (
          match op.x with
          | Op.BuiltinOp _ ->
              comp_htriple_check_letapppop typectx
                (lhs, op, appopargs, letbody)
                (pre, resrty, post)
          | Op.DtOp _ -> _failatwith __FILE__ __LINE__ "die"
          | Op.EffOp _ ->
              let runtime, res =
                Sugar.clock (fun () ->
                    comp_htriple_check_letappeop typectx
                      (lhs, op, appopargs, letbody)
                      (pre, resrty, post))
              in
              let () =
                Env.show_debug_debug @@ fun _ ->
                Pp.printf "@{<bold>comp_htriple_check_letperform: @}%f\n"
                  runtime
              in
              res)
      | _ ->
          let () = Printf.printf "ERR:\n%s\n" (layout_comp rhs) in
          _failatwith __FILE__ __LINE__ "die")
  | CMatch { matched; match_cases } ->
      let () = before_info __LINE__ "Match" in
      let res =
        List.fold_left
          (fun res case ->
            let* () = res in
            handle_match_case typectx (matched, case) (pre, resrty, post))
          (Some ()) match_cases
      in
      end_info __LINE__ "Match" res
  | CAppOp _ | CApp _ -> _failatwith __FILE__ __LINE__ "not in MNF"
  | CLetDeTu _ -> _failatwith __FILE__ __LINE__ "unimp"
  | CErr ->
      let () = before_info __LINE__ "Err" in
      end_info __LINE__ "Err" None
