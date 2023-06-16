From stdpp Require Import mapset.
From stdpp Require Import natmap.
From CT Require Import CoreLangProp.
From CT Require Import OperationalSemantics.
From CT Require Import BasicTypingProp.
From CT Require Import RefinementType.
From CT Require Import Denotation.
From CT Require Import Instantiation.

Import Atom.
Import CoreLang.
Import Tactics.
Import NamelessTactics.
Import ListCtx.
Import Trace.
Import OperationalSemantics.
Import BasicTyping.
Import RefinementType.
Import Denotation.
Import Instantiation.
Import Qualifier.

(** Well-formedness *)
Definition wf_am (Γ: listctx pty) (A: am): Prop := closed_am (ctxdom ⦑ Γ ⦒) A.

Inductive wf_pty: listctx pty -> pty -> Prop :=
| wf_pty_base: forall Γ b ϕ,
    closed_pty (ctxdom ⦑ Γ ⦒) {v: b | ϕ } -> wf_pty Γ {v: b | ϕ }
| wf_pty_arr: forall Γ ρ T A B (L: aset),
    wf_pty Γ ρ ->
    wf_am Γ A ->
    amlist_typed B T ->
    (forall x, x ∉ L ->
          (forall Bi ρi, In (Bi, ρi) B ->
                    wf_pty (Γ ++ [(x, ρ)]) ρi
          )
    ) ->
    wf_pty Γ (-: ρ ⤑[: T | A ⇒ B ]).

Inductive wf_hty: listctx pty -> hty -> Prop :=
| wf_hty_: forall Γ T A B,
    amlist_typed B T ->
    (forall Ai ρi, In (Ai, ρi) B -> wf_am Γ Ai /\ wf_pty Γ ρi) ->
    wf_hty Γ [: T | A ⇒ B ].

Notation " Γ '⊢WF' τ " := (wf_hty Γ τ) (at level 20, τ constr, Γ constr).
Notation " Γ '⊢WFp' τ " := (wf_pty Γ τ) (at level 20, τ constr, Γ constr).

Definition subtyping (Γ: listctx pty) (τ1 τ2: hty) : Prop :=
  (* Assume [τ1] and [τ2] are valid [hty]s. *)
  forall Γv, ctxRst Γ Γv -> forall e, ⟦(m{ Γv }h) τ1⟧ (m{ Γv }t e) → ⟦(m{ Γv }h) τ2⟧ (m{ Γv }t e).

Notation " Γ '⊢' τ1 '⪡' τ2 " := (subtyping Γ τ1 τ2) (at level 20, τ1 constr, τ2 constr, Γ constr).

Reserved Notation "Γ '⊢' e '⋮t' τ" (at level 20).
Reserved Notation "Γ '⊢' e '⋮v' τ"  (at level 20).


(** Typing *)
Inductive term_type_check : listctx pty -> tm -> hty -> Prop :=
| TValue: forall Γ v ρ,
    Γ ⊢ v ⋮v ρ ->
    Γ ⊢ v ⋮t (pty_to_rty ρ)
| TSub: forall Γ e (τ1 τ2: hty),
    Γ ⊢WF τ2 ->
    Γ ⊢ e ⋮t τ1 ->
    Γ ⊢ τ1 ⪡ τ2 ->
    Γ ⊢ e ⋮t τ2
| TLetE: forall Γ e_x e Tx A T Bx_ρx BxB_ρ Bx_ρx_B_ρ (L: aset),
    Γ ⊢WF [: T | A ⇒ BxB_ρ ] ->
    Γ ⊢ e_x ⋮t [: Tx | A ⇒ Bx_ρx ] ->
    Bx_ρx = map (fun '(Bx, ρx, _, _) => (Bx, ρx)) Bx_ρx_B_ρ ->
    BxB_ρ = map (fun '(Bx, _, B, ρ) => (aconcat Bx B, ρ)) Bx_ρx_B_ρ ->
    (forall x, x ∉ L ->
          forall Bxi ρxi Bi ρi,
            In (Bxi, ρxi, Bi, ρi) Bx_ρx_B_ρ ->
            (Γ ++ [(x, ρxi)]) ⊢ (e ^t^ x) ⋮t [: T | aconcat A Bxi ⇒ [(Bi, ρi)]]) ->
    Γ ⊢ (tlete e_x e) ⋮t [: T | A ⇒ BxB_ρ ]
| TApp: forall Γ (v1 v2: value) e ρ Tx A T Bx_ρx BxB_ρ Bx_ρx_B_ρ (L: aset),
    Γ ⊢WF [: T | A ⇒ BxB_ρ ] ->
    Γ ⊢ v2 ⋮v ρ ->
    Γ ⊢ v1 ⋮v (-: ρ ⤑[: Tx | A ⇒ Bx_ρx ]) ->
    Bx_ρx = map (fun '(Bx, ρx, _, _) => (Bx, ρx)) Bx_ρx_B_ρ ->
    BxB_ρ = map (fun '(Bx, _, B, ρ) => (aconcat Bx B, ρ)) Bx_ρx_B_ρ ->
    (forall x, x ∉ L ->
          forall Bxi ρxi Bi ρi,
            In (Bxi, ρxi, Bi, ρi) Bx_ρx_B_ρ ->
            (Γ ++ [(x, ρxi ^p^ v2)]) ⊢ (e ^t^ x) ⋮t [: T | aconcat A (Bxi ^a^ v2) ⇒ [(Bi, ρi)]]) ->
    Γ ⊢ (tletapp v1 v2 e) ⋮t [: T | A ⇒ BxB_ρ ]
| TEffOp: forall Γ (op: effop) (v2: value) e ρ A ϕx T Aop' Bi ρi (L: aset),
    (* NOTE: it does not seem like we need to substitute [ϕx] here, i.e. [{1 ~q>
    v2}ϕx], because bound variable [1] is already restricted to [v2]. *)
    Aop' = ⟨ op | b1:v= v2 & ϕx ⟩ ->
    Γ ⊢WF [: T | A ^a^ v2 ⇒ [(aconcat Aop' Bi, ρi)] ] ->
    builtin_typing_relation op (-: ρ ⤑[: ret_ty_of_op op | A ⇒ [(aϵ, {v: ret_ty_of_op op | ϕx})] ]) ->
    Γ ⊢ v2 ⋮v ρ ->
    (forall x, x ∉ L ->
          forall Aop, Aop = ⟨ op | b1:v= v2 & b0:x= x ⟩ ->
          (Γ ++ [(x, {v: ret_ty_of_op op | {1 ~q> v2 } ϕx})]) ⊢ (e ^t^ x) ⋮t ([: T | aconcat A Aop ⇒ [(Bi, ρi)]] ^h^ x)) ->
    Γ ⊢ (tleteffop op v2 e) ⋮t [: T | A ^a^ v2 ⇒ [(aconcat Aop' Bi, ρi)] ]
| TMatchb_true: forall Γ (v: value) e1 e2 τ,
    Γ ⊢WF τ ->
    Γ ⊢ v ⋮v (mk_eq_constant true) ->
    Γ ⊢ e1 ⋮t τ ->
    ⌊ Γ ⌋* ⊢t e2 ⋮t ⌊ τ ⌋ ->
    Γ ⊢ (tmatchb v e1 e2) ⋮t τ
| TMatchb_false: forall Γ (v: value) e1 e2 τ,
    Γ ⊢WF τ ->
    Γ ⊢ v ⋮v (mk_eq_constant false) ->
    Γ ⊢ e2 ⋮t τ ->
    ⌊ Γ ⌋* ⊢t e1 ⋮t ⌊ τ ⌋ ->
    Γ ⊢ (tmatchb v e1 e2) ⋮t τ
with value_type_check : listctx pty -> value -> pty -> Prop :=
| TConstant: forall Γ (c: constant),
    Γ ⊢WFp (mk_eq_constant c) ->
    Γ ⊢ c ⋮v (mk_eq_constant c)
| TVar: forall Γ (x: atom) ρ,
    ctxfind Γ x = Some ρ ->
    Γ ⊢ x ⋮v ρ
| TLam: forall Γ Tx ρ e T A B (L: aset),
    Γ ⊢WFp (-: ρ ⤑[: T | A ⇒ B ] ) ->
    (forall x, x ∉ L -> (Γ ++ [(x, ρ)]) ⊢ (e ^t^ x) ⋮t ([: T | A ⇒ B ] ^h^ x)) ->
    Γ ⊢ (vlam Tx e) ⋮v (-: ρ ⤑[: T | A ⇒ B ])
| TLamFix: forall Γ Tx ρ e T A B (L: aset),
    Γ ⊢WFp (-: ρ ⤑[: T | A ⇒ B ]) ->
    (forall f, f ∉ L -> (Γ ++ [(f, (-: ρ ⤑[: T | A ⇒ B ]))]) ⊢ ((vlam Tx e) ^v^ f) ⋮v (-: ρ ⤑[: T | A ⇒ B ])) ->
    Γ ⊢ (vfix (⌊ -: ρ ⤑[: T | A ⇒ B ] ⌋) (vlam Tx e)) ⋮v (-: ρ ⤑[: T | A ⇒ B ])
where
"Γ '⊢' e '⋮t' τ" := (term_type_check Γ e τ) and "Γ '⊢' e '⋮v' τ" := (value_type_check Γ e τ).


Scheme value_type_check_rec := Induction for value_type_check Sort Prop
    with term_type_check_rec := Induction for term_type_check Sort Prop.

Lemma value_typing_regular: forall (Γ: listctx pty) (v: value) (ρ: pty),
    Γ ⊢ v ⋮v ρ -> ⌊ Γ ⌋* ⊢t v ⋮v ⌊ ρ ⌋ /\ wf_pty Γ ρ.
Admitted.

Lemma tm_typing_regular: forall (Γ: listctx pty) (e: tm) (τ: hty),
    Γ ⊢ e ⋮t τ -> ⌊ Γ ⌋* ⊢t e ⋮t ⌊ τ ⌋ /\ wf_hty Γ τ.
Admitted.

Lemma well_formed_builtin_typing: forall op ρx A B ρ,
    builtin_typing_relation op (-: ρx ⤑[: ret_ty_of_op op | A ⇒ [(B, ρ)] ]) ->
    forall (v_x: constant), p⟦ ρx ⟧ v_x ->
                       forall α, a⟦ A ^a^ v_x ⟧ α ->
                            (exists (c: constant), p⟦ ρ ^p^ v_x ⟧ c) /\
                              (forall (c: constant), α ⊧{op ~ v_x}⇓{ c } -> p⟦ ρ ^p^ v_x ⟧ c).
Admitted.

Lemma reduction_tlete:  forall e_x e α β v,
    α ⊧ tlete e_x e ↪*{ β } v <->
    (exists (βx βe: trace) (v_x: value),
      β = βx ++ βe /\ α ⊧ e_x ↪*{ βx } v_x /\ (α ++ βx) ⊧ (e ^t^ v_x) ↪*{ βe } v).
Admitted.

(* I have proved this lemma in Poirot. *)
Lemma msubst_open: forall (Γv: env) e (v_x: value) (x: atom),
    x # (dom Γv ∪ stale e ∪ stale v_x) ->
    (m{Γv}t) e ^t^ v_x = (m{<[x:=v_x]> Γv}t) (e ^t^ x).
Admitted.

(** maybe open/close should be a type class *)

Lemma msubst_open_hty: forall (Γv: env) e (v_x: value) (x: atom),
    x # (dom Γv ∪ stale e ∪ stale v_x) ->
    (m{Γv}h) e ^h^ v_x = (m{<[x:=v_x]> Γv}h) (e ^h^ x).
Admitted.

Lemma msubst_hty: forall (Γv: env) T A B, m{Γv}h [:T|A⇒B] = [:T|m{Γv}a A ⇒ m{Γv}pa B].
Admitted.

Lemma msubst_lete: forall (Γv: env) e_x e, (m{Γv}t (tlete e_x e) = tlete ((m{Γv}t) e_x) ((m{Γv}t) e)).
Admitted.

Lemma msubst_concat: forall (Γv: env) A1 A2, m{Γv}a (aconcat A1 A2) = (aconcat (m{Γv}a A1) (m{Γv}a A2)).
Admitted.

Lemma msubst_amlist_typed: forall (Γv: env) B T,
    amlist_typed ((m{Γv}pa) B) T <-> amlist_typed B T.
Admitted.

Lemma in_msubst: forall (Γv: env) (A: am) (ρ: pty) (B: list (am * pty)),
    In (A, ρ) (m{Γv}pa B) <-> exists A' ρ', A = m{Γv}a A' /\ ρ = m{Γv}p ρ' /\ In (A', ρ') B.
Admitted.

Definition subst4 Γv (x: am * pty * am * pty) :=
  match x with
    | (A, ρa, B, ρb) => (m{Γv}a A, m{Γv}p ρa, m{Γv}a B, m{Γv}p ρb)
  end.

Lemma in_msubst4: forall (Γv: env) (A1: am) (ρ1: pty) (A2: am) (ρ2: pty) (B4: list (am * pty * am * pty)),
    In (A1, ρ1, A2, ρ2) (List.map (subst4 Γv) B4) ->
    exists A1' ρ1' A2' ρ2',
      A1 = m{Γv}a A1' /\ ρ1 = m{Γv}p ρ1' /\ A2 = m{Γv}a A2' /\ ρ2 = m{Γv}p ρ2' /\ In (A1', ρ1', A2', ρ2') B4.
Admitted.

Lemma am_concat: forall A B α β,
  (a⟦A⟧) α -> (a⟦B⟧) β -> (a⟦ aconcat A B ⟧) (α ++ β).
Admitted.

Lemma am_denotation_fv: forall Γv x v_x A,
    x ∉ stale A -> forall α, a⟦(m{<[x:=v_x]> Γv}a) A⟧ α <-> a⟦(m{Γv}a) A⟧ α.
Admitted.

Lemma in_singleton {T1 T2: Type}: forall (a1 a1': T1) (a2 a2': T2), In (a1, a2) [(a1', a2')] -> a1 = a1' /\ a2 = a2'.
Proof.
  intros. inversion H. inversion H0; subst; auto. inversion H0.
Qed.

Lemma ptyR_typed_closed t ρ e :
  ptyR t ρ e ->
  ⌊ ρ ⌋ = t /\ ∅ ⊢t e ⋮t ⌊ ρ ⌋ /\ closed_pty ∅ ρ.
Proof.
  destruct t; simpl; intuition.
Qed.

Lemma ctxRst_closed_env Γ Γv : ctxRst Γ Γv -> closed_env Γv.
Proof.
  unfold closed_env.
  induction 1.
  - apply map_Forall_empty.
  - apply map_Forall_insert_2; eauto.
    unfold closed_value.
    change (fv_value v) with (fv_tm v).
    apply equiv_empty.
    erewrite <- dom_empty.
    eapply basic_typing_contains_fv_tm.
    eapply ptyR_typed_closed.
    eauto.
Qed.

Ltac apply_msubst_ind :=
  unfold msubst;
  match goal with
  | |- ?T =>
      match T with
      | context [map_fold ?a ?b ?m] =>
          match eval pattern (map_fold a b m) in T with
          | ?P _ =>
              match eval pattern m in P with
              | ?P _ =>
                  let P := eval simpl in (fun r m => P m r) in
                    apply (map_fold_ind P)
              end
          end
      end
  end.

Ltac gen_closed_env :=
  repeat
    match goal with
    | H : closed_env (<[?i:=_]> ?m), H' : ?m !! ?i = None |- _ =>
        let H1 := fresh "H" in
        let H2 := fresh "H" in
        destruct (closed_env_insert _ _ _ H' H) as [H1 H2];
        uniq_hyp H1; uniq_hyp H2
    | H : closed_env ?m, H' : ?m !! _ = Some ?v |- _ =>
        let T := fresh "H" in
        assert (closed_value v) as T by eauto;
        uniq_hyp T
    (* | H : ctxRst _ ?env |- _ => *)
    (*     let T := fresh "H" in *)
    (*     assert (closed_env env) as T by eauto using ctxRst_closed_env; *)
    (*     uniq_hyp T *)
    end.

Lemma msubst_insert {T: Type}
  (f_subst: atom -> value -> T -> T)
  (subst_commute: forall x u_x y u_y e,
      x <> y -> x ∉ fv_value u_y -> y ∉ fv_value u_x ->
      f_subst x u_x (f_subst y u_y e) =
        f_subst y u_y (f_subst x u_x e))
  :
  forall (Γv: env) (x: atom) (v_x: value) (e: T),
    closed_env Γv ->
    closed_value v_x ->
    Γv !! x = None ->
    msubst f_subst (<[x:=v_x]> Γv) e = f_subst x v_x (msubst f_subst Γv e).
Proof.
  intros.
  apply map_fold_insert_L; eauto.
  intros.
  assert (closed_env (<[x:=v_x]>Γv)). {
    apply map_Forall_insert; eauto.
  }
  gen_closed_env.
  apply subst_commute; eauto; my_set_solver.
Qed.

Ltac msubst_tac :=
  intros *; apply_msubst_ind; intros; subst; simpl; eauto;
  gen_closed_env; simp_hyps; subst.

Ltac apply_msubst_insert :=
  simpl; f_equal;
  first [ symmetry; apply msubst_insert | apply msubst_insert ];
  (* TODO: hintdb? *)
  eauto using subst_commute_value, subst_commute_tm, subst_commute_qualifier,
    subst_commute_pty, subst_commute_am, subst_commute_postam.

Lemma msubst_fv {T: Type} `{@Stale aset T} : forall (Γv: env) (x: atom) (v_x: value)
                             (f_subst: atom -> value -> T -> T)
                             (e: T),
    x # e ->
    msubst f_subst (<[x:=v_x]> Γv) e = msubst f_subst Γv e.
Proof.
Admitted.

Lemma msubst_bvar: forall Γv n, (m{Γv}v) (vbvar n) = vbvar n.
Proof.
  msubst_tac.
Qed.

Lemma msubst_constant: forall Γv (c: constant), (m{Γv}v) c = c.
Proof.
  msubst_tac.
Qed.

Lemma msubst_fvar: forall Γv (x : atom),
    closed_env Γv ->
    (m{Γv}v) x = match Γv !! x with
                 | Some v => v
                 | None => x
                 end.
Proof.
  msubst_tac.
  destruct (decide (x = i)); subst; simplify_map_eq. reflexivity.
  case_match.
  apply subst_fresh_value.
  gen_closed_env. my_set_solver.
  simpl. rewrite decide_False; eauto.
Qed.

Lemma msubst_arrty: forall Γv ρ T A B,
    closed_env Γv ->
    (m{Γv}p) (-:ρ⤑[:T|A⇒B]) = (-:(m{Γv}p ρ)⤑[:T| (m{Γv}a A) ⇒ (m{Γv}pa B) ]).
Proof.
  msubst_tac.
  simpl. f_equal.
  apply_msubst_insert.
  apply_msubst_insert.
  symmetry.
  change
    (map_fold postam_subst B (<[i:=x]> m) =
       postam_subst i x (map_fold postam_subst B m)).
  apply_msubst_insert.
Qed.

Lemma msubst_bty: forall Γv b ϕ, closed_env Γv -> (m{Γv}p) {v:b|ϕ} = {v:b| (m{Γv}q) ϕ}.
Proof.
  msubst_tac. apply_msubst_insert.
Qed.

Lemma msubst_qualifier: forall Γv ϕ,
    closed_env Γv ->
    (m{Γv}q) ϕ =
      match ϕ with
      | qual vals prop =>
          qual (vmap (m{Γv}v) vals) prop
      end.
Proof.
  msubst_tac.
  - destruct ϕ.
    f_equal.
    erewrite Vector.map_ext.
    by rewrite Vector.map_id.
    intros. simpl.
    by rewrite map_fold_empty.
  - destruct ϕ. simpl. f_equal.
    rewrite Vector.map_map.
    apply Vector.map_ext.
    apply_msubst_insert.
Qed.

Lemma msubst_lam: forall Γv T e,
    closed_env Γv ->
    ((m{Γv}v) (vlam T e)) = (vlam T ((m{Γv}t) e)).
Proof.
  msubst_tac. apply_msubst_insert.
Qed.

Lemma msubst_fix: forall Γv T e,
    closed_env Γv ->
    ((m{Γv}v) (vfix T e)) = (vfix T ((m{Γv}t) e)).
Proof.
  msubst_tac. apply_msubst_insert.
Qed.

Lemma msubst_value: forall Γv (v:value),
    closed_env Γv ->
    (m{Γv}t) (treturn v) = (m{Γv}v) v.
Proof.
  msubst_tac. apply_msubst_insert.
Qed.

Lemma msubst_match: forall Γv (v: value) e1 e2,
    closed_env Γv ->
    ((m{Γv}t) (tmatchb v e1 e2)) = tmatchb (m{Γv}v v) (m{Γv}t e1) (m{Γv}t e2).
Proof.
  msubst_tac. apply_msubst_insert.
Qed.

Lemma msubst_tleteffop: forall Γv op (v2: value) e,
    closed_env Γv ->
    (m{Γv}t) (tleteffop op v2 e) = (tleteffop op (m{Γv}v v2) (m{Γv}t e)).
Proof.
  msubst_tac. apply_msubst_insert.
Qed.

Lemma msubst_pty_to_rty: forall Γv ρ,
    closed_env Γv ->
    (m{Γv}h) (pty_to_rty ρ) = pty_to_rty (m{Γv}p ρ).
Proof.
  msubst_tac.
  unfold pty_to_rty.
  simpl. f_equal.

  admit.
  admit.

  repeat f_equal.
  apply_msubst_insert.
Admitted.

Ltac msubst_simp :=
  match goal with
  | H: context [ m{ _ }h (pty_to_rty _) ] |- _ => rewrite msubst_pty_to_rty in H
  | |- context [ m{ _ }h (pty_to_rty _) ] => rewrite msubst_pty_to_rty
  | H: context [ m{ _ }h _ ] |- _ => rewrite msubst_hty in H
  | |- context [ m{ _ }h _ ] => rewrite msubst_hty
  | H: context [ m{ _ }p {v: _ | _ } ] |- _ => rewrite msubst_bty in H
  | |- context [ m{ _ }p {v: _ | _ } ] => rewrite msubst_bty
  | H: context [ m{ _ }p (-: _ ⤑[: _ | _ ⇒ _ ]) ] |- _ => rewrite msubst_arrty in H
  | |- context [ m{ _ }p (-: _ ⤑[: _ | _ ⇒ _ ]) ] => rewrite msubst_arrty
  | H: context [ m{ _ }a (aconcat _ _) ] |- _ => rewrite msubst_concat in H
  | |- context [ m{ _ }a (aconcat _ _) ] => rewrite msubst_concat
  | H: context [ m{ _ }t (tlete _ _) ] |- _ => rewrite msubst_lete in H
  | |- context [ m{ _ }t (tlete _ _) ] => rewrite msubst_lete
  | H: context [ m{ _ }t (tleteffop _ _ _) ] |- _ => rewrite msubst_tleteffop in H
  | |- context [ m{ _ }t (tleteffop _ _ _) ] => rewrite msubst_tleteffop
  | H: context [ m{ _ }v (vfix _ _) ] |- _ => rewrite msubst_fix in H
  | |- context [ m{ _ }v (vfix _ _) ] => rewrite msubst_fix
  | H: context [ m{ _ }t (treturn _) ] |- _ => rewrite msubst_value in H
  | |- context [ m{ _ }t (treturn _) ] => rewrite msubst_value
  | H: context [ m{ _ }v (vlam _ _) ] |- _ => rewrite msubst_lam in H
  | |- context [ m{ _ }v (vlam _ _) ] => rewrite msubst_lam
  | H: context [ m{ _ }t (tmatchb _ _ _) ] |- _ => rewrite msubst_match in H
  | |- context [ m{ _ }t (tmatchb _ _ _) ] => rewrite msubst_match
  | H: context [ m{ _ }v (vbvar _) ] |- _ => rewrite msubst_bvar in H
  | |- context [ m{ _ }v (vbvar _) ] => rewrite msubst_bvar
  | H: context [ m{ _ }v (vfvar _) ] |- _ => rewrite msubst_fvar in H
  | |- context [ m{ _ }v (vfvar _) ] => rewrite msubst_fvar
  | H: context [ m{ _ }v (vconst _) ] |- _ => rewrite msubst_constant in H
  | |- context [ m{ _ }v (vconst _) ] => rewrite msubst_constant
  | H: context [ m{ _ }q _ ] |- _ => rewrite msubst_qualifier in H
  | |- context [ m{ _ }q _ ] => rewrite msubst_qualifier
  end; eauto using ctxRst_closed_env.

Lemma ptyR_msubst_insert_eq Γv ρ v x u :
  closed_env Γv ->
  closed_value u ->
  Γv !! x = None ->
  (p⟦(m{ Γv }p) ρ⟧) v ->
  (p⟦(m{ <[x:=u]> Γv }p) ρ⟧) v.
Proof.
  intros. rewrite msubst_insert; eauto using subst_commute_pty.
  rewrite subst_fresh_pty. auto.
  select (p⟦_⟧ _) (fun H => apply ptyR_typed_closed in H).
  simp_hyps. select (closed_pty _ _) (fun H => sinvert H). my_set_solver.
Qed.

Lemma ctxRst_dom Γ Γv x :
  ctxRst Γ Γv ->
  x ∉ ctxdom Γ <-> x ∉ dom Γv.
Proof.
  induction 1; simpl; eauto.
  rewrite ctxdom_app_union.
  rewrite dom_insert.
  simpl. my_set_solver.
Qed.

Lemma ctxRst_ctxfind Γ Γv x ρ :
  ctxRst Γ Γv ->
  ctxfind Γ x = Some ρ ->
  exists (v : value), Γv !! x = Some v /\ p⟦ m{ Γv }p ρ ⟧ v.
Proof.
  induction 1.
  - easy.
  - intros.
    select (ctxfind (_ ++ _) _ = _)
      (fun H => apply ctxfind_app in H; eauto using ok_ctx_ok).

    assert (forall (v' : value), (p⟦(m{env}p) ρ⟧) v' ->
                            (p⟦(m{<[x0:=v]> env}p) ρ⟧) v'). {
      select (p⟦ _ ⟧ _) (fun H => apply ptyR_typed_closed in H). simp_hyps.
      intros.
      apply ptyR_msubst_insert_eq; eauto using ctxRst_closed_env.
      select (_ ⊢t _ ⋮t _)
        (fun H => apply basic_typing_contains_fv_tm in H; simpl in H).
      my_set_solver.
      select (ok_ctx _) (fun H => apply ok_ctx_ok in H; apply ok_post_destruct in H).
      simp_hyps. apply not_elem_of_dom. eapply ctxRst_dom; eauto.
    }

    destruct_or!; simp_hyps.
    + eexists. split; eauto.
      assert (x <> x0). {
        select (ok_ctx _) (fun H => sinvert H); listctx_set_simpl.
        select (ctxfind _ _ = _) (fun H => apply ctxfind_some_implies_in_dom in H).
        my_set_solver.
      }
      by simplify_map_eq.
    + simpl in *.
      case_decide; try easy. simplify_eq.
      eexists. split; eauto. by simplify_map_eq.
Qed.


Lemma value_reduction_refl: forall α β (v1: value) v2, α ⊧ v1 ↪*{ β} v2 -> v2 = v1 /\ β = [].
Admitted.

Ltac reduction_simp :=
  match goal with
  | H: _ ⊧ (treturn _) ↪*{ _ } _  |- _ => apply value_reduction_refl in H;
                                        destruct H as (Htmp1 & Htmp2);
                                        subst; try rewrite Htmp1; try clear Htmp1; try clear Htmp2
  end.

Lemma denotation_application_base_arg:
  forall (b: base_ty) ϕ T A B (Tb: ty) e,
    Tb = b ->
    (forall(v: value), p⟦ {v:b|ϕ} ⟧ v -> ⟦ [:T | A ^a^ v ⇒ B ^pa^ v ] ⟧ (e ^t^ v)) ->
    p⟦ -: {v:b|ϕ} ⤑[:T|A⇒B] ⟧ (vlam Tb e).
Admitted.

Lemma denotation_application_arr_arg:
  forall ρx (Tx: ty) Ax Bx T A B Te e,
    Te = (⌊ ρx ⌋ ⤍ Tx) ->
    (forall (v: value), p⟦ -: ρx ⤑[:Tx|Ax⇒Bx] ⟧ v -> ⟦ [:T | A ⇒ B ] ⟧ (e ^t^ v)) ->
    p⟦ -: -: ρx ⤑[:Tx|Ax⇒Bx] ⤑[:T|A⇒B] ⟧ (vlam Te e).
Admitted.

Lemma reduction_tletapp:  forall v1 v2 e α β v,
    α ⊧ tletapp v1 v2 e ↪*{ β} v <->
      lc v1 /\ lc v2 /\ body e /\
        ((exists Tx e1,
             v1 = vlam Tx e1 /\ α ⊧ tlete (e1 ^t^ v2) e ↪*{ β} v) \/
           (exists T Tx (e1: tm),
               v1 = vfix T (vlam Tx e1) /\ α ⊧ tletapp ((vlam T e1) ^v^ v2) (vfix T (vlam Tx e1)) e ↪*{ β} v)).
Admitted.

Lemma reduction_tleteffop:  forall op v2 e α β v,
    α ⊧ (tleteffop op v2 e) ↪*{ β} v <->
      body e /\ (exists (c2 c_x: constant) β',
                   v2 = c2 /\ β = ev{ op ~ c2 := c_x } :: β' /\
                     α ⊧{op ~ c2}⇓{ c_x } /\ (α ++ [ev{op ~ c2 := c_x}]) ⊧ (e ^t^ c_x) ↪*{ β'} v ).
Admitted.

Lemma reduction_matchb_true:  forall e1 e2 α β v,
    α ⊧ tmatchb true e1 e2 ↪*{ β} v <-> lc e2 /\ α ⊧ e1 ↪*{ β} v.
Admitted.

Lemma reduction_matchb_false:  forall e1 e2 α β v,
    α ⊧ tmatchb false e1 e2 ↪*{ β} v <-> lc e1 /\ α ⊧ e2 ↪*{ β} v.
Admitted.

Lemma lc_am_dot: lc_am ∘.
Admitted.

Lemma am_fv_dot_empty: am_fv ∘ = ∅.
Admitted.

Lemma denotation_value_pure: forall (ρ: pty) (v: value), p⟦ ρ ⟧ v <-> ⟦pty_to_rty ρ ⟧ v.
Proof.
  unfold pty_to_rty; split; intros.
  - split. admit. split. admit.
    intros Hamlist α β v' Hα Hstepv. reduction_simp.
    exists aϵ, ρ. split. unfold In. left; auto. split; auto. repeat constructor; auto.
  - destruct H as (Ht & Hclose & H).
    assert (amlist_typed [(aϵ, ρ)] ⌊ρ⌋) as Hamlist. { admit. }
    specialize (H Hamlist [] [] v).
    assert (closed_am ∅ (astar ∘) ∧ repeat_tr (a⟦∘⟧) []) as H1.
    { split; auto. repeat constructor; simpl; auto. apply lc_am_dot. rewrite am_fv_dot_empty; auto. constructor. }
    assert ([] ⊧ v ↪*{ [] } v) as Hstepv. constructor. admit.
    specialize (H H1 Hstepv). mydestr. apply in_singleton in H. mydestr; subst; auto.
Admitted.

Lemma closed_bool_typed_value: forall v, ∅ ⊢t v ⋮v TBool -> v = true \/ v = false.
Proof.
  intros. inversion H.
  - destruct c. destruct b; subst; auto. inversion H3.
  - subst. inversion H0.
Qed.

Lemma am_concat_opev_head: forall op ϕ A α,
    a⟦ ⟨op|ϕ⟩ ;+ A ⟧ α <-> (exists c2 c_x α', α = ev{op~c2:=c_x} :: α' /\ a⟦ ⟨op|ϕ⟩ ⟧ [ev{op~c2:=c_x}] /\ a⟦ A ⟧ α').
Admitted.

Lemma am_concat_opev_tail: forall op ϕ A α,
    a⟦ A ;+ ⟨op|ϕ⟩ ⟧ α <-> (exists α' c2 c_x , α = α' ++ [ev{op~c2:=c_x}] /\ a⟦ ⟨op|ϕ⟩ ⟧ [ev{op~c2:=c_x}] /\ a⟦ A ⟧ α').
Admitted.

Theorem fundamental: forall (Γ: listctx pty) (e: tm) (τ: hty),
    Γ ⊢ e ⋮t τ ->
    (* NOTE: [τ] being valid should be a regularity lemma. *)
    forall Γv, ctxRst Γ Γv -> ⟦ msubst hty_subst Γv τ ⟧ (msubst tm_subst Γv e).
Proof.
  apply (term_type_check_rec
           (* NOTE: should this be the denotation of [pty]? *)
           (* (fun Γ (v: value) ρ _ => *)
           (*    forall Γv, ctxRst Γ Γv -> ⟦ m{Γv}h (pty_to_rty ρ) ⟧ (m{Γv}v v)) *)
           (fun Γ (v: value) ρ _ =>
              forall Γv, ctxRst Γ Γv -> p⟦ m{Γv}p ρ ⟧ (m{Γv}v v))
           (fun Γ e (τ: hty) _ =>
              forall Γv, ctxRst Γ Γv -> ⟦ m{Γv}h τ ⟧ (m{Γv}t e))
        ).
  (* [TConstant] *)
  - intros Γ c HWF Γv HΓv. repeat msubst_simp.
    assert ((m{Γv}p) (mk_eq_constant c) = (mk_eq_constant c)) as Htmp. {
      unfold mk_eq_constant, mk_q_bvar_eq_val.
      repeat (msubst_simp; simpl).
    }
    rewrite Htmp; clear Htmp.
    simpl.
    repeat split; try solve [repeat econstructor].
    simpl. set_solver.
    intros. unfold bpropR. simpl.
    specialize (H []). apply multi_step_value in H.
    qauto.

  (* [TVar] *)
  - intros Γ x ρ Hfind Γv HΓv. repeat msubst_simp.
    eapply ctxRst_ctxfind in HΓv; eauto.
    qauto.

  (* [TLam] *)
  - intros Γ Tx ρ e T A B L HWF _ HDe Γv HΓv. repeat msubst_simp.
    auto_pose_fv x. repeat specialize_with x.
    destruct ρ.
    + repeat msubst_simp. apply denotation_application_base_arg. admit.
      intros v_x Hv_x. assert (ctxRst (Γ ++ [(x, {v:B0|ϕ})]) (<[x := v_x]> Γv)) as HΓv'. admit.
      specialize (HDe _ HΓv').
      rewrite <- msubst_open in HDe. 2: { admit. } rewrite <- msubst_open_hty in HDe. 2: { admit. }
      repeat msubst_simp. auto.
    + repeat msubst_simp. apply denotation_application_arr_arg. admit.
      intros v_x Hv_x. assert (ctxRst (Γ ++ [(x, -:ρ⤑[:T0|pre⇒post] )]) (<[x := v_x]> Γv)) as HΓv'. admit.
      specialize (HDe _ HΓv').
      rewrite <- msubst_open in HDe.
      2: { admit. }
      assert ((m{<[x:=v_x]> Γv}h) ([:T|A⇒B] ^h^ x) = m{Γv}h [:T|A⇒B]) as Htmp3. admit. rewrite Htmp3 in HDe.
      repeat msubst_simp. auto.

  - intros Γ Tx ρ e T A B L HWF _ HDe Γv HΓv. repeat msubst_simp. rewrite <- denotation_value_pure.
    auto_pose_fv f. repeat specialize_with f. admit.
  - intros Γ v ρ _ HDv Γv HΓv. specialize (HDv _ HΓv). repeat msubst_simp. auto.
  - intros Γ e τ1 τ2 HWFτ2 _ HDτ1 Hsub Γv HΓv. specialize (HDτ1 _ HΓv). apply Hsub in HDτ1; auto.
  - intros Γ e_x e Tx A T Bx_ρx BxB_ρ Bx_ρx_B_ρ L HWFBρ HTe_x HDe_x Hin1 Hin2 _ He Γv HΓv.
    auto_pose_fv x. repeat specialize_with x. repeat msubst_simp.
    split. admit. split. admit.
    intros HBtyped α β v HDα Hstepv.
    rewrite reduction_tlete in Hstepv. destruct Hstepv as (βx & βe & v_x & Htmp & Hstepv_x & Hstepv). subst.
    rewrite msubst_open with (x:=x) in Hstepv. 2: { admit. }
    specialize (HDe_x _ HΓv). repeat msubst_simp.
    destruct HDe_x as (Hte_x & Hclosede_x & HDe_x).
    assert (amlist_typed ((m{Γv}pa) Bx_ρx) Tx) as HH1. { rewrite msubst_amlist_typed. admit. }
    specialize (HDe_x HH1 _ _ _ HDα Hstepv_x).
    destruct HDe_x as (Bxi' & ρxi' & HinBx_ρx & Hβx & Hv_x).
    apply in_msubst in HinBx_ρx. destruct HinBx_ρx as (Bxi & ρxi & Htmp0 & Htmp1 & HinBx_ρx); subst.
    apply Hin1 in HinBx_ρx. destruct HinBx_ρx as (Bi & ρi & Hin). clear Hin1.
    assert (ctxRst (Γ ++ [(x, ρxi)]) (<[x:=v_x]> Γv)) as HH2. { constructor; auto. admit. }
    specialize (He _ _ _ _ Hin (<[ x := v_x]> Γv) HH2). repeat msubst_simp.
    destruct He as (Hte & Hclosede & He).
    assert (amlist_typed ((m{<[x:=v_x]> Γv}pa) [(Bi, ρi)]) T) as HH3. { rewrite msubst_amlist_typed. admit. }
    specialize (He HH3 (α ++ βx) βe v).
    assert (x ∉ stale Bxi). admit.
    assert ((a⟦(m{<[x:=v_x]> Γv}a) (aconcat A Bxi)⟧) (α ++ βx)) as Hconcat.
    { rewrite am_denotation_fv; try fast_set_solver. repeat msubst_simp.
      apply am_concat; auto. } repeat msubst_simp.
    specialize (He Hconcat Hstepv). destruct He as (Bi'' & ρi'' & Hini & Hβe & Hv).
    apply in_msubst in Hini. destruct Hini as (Bi' & ρi' & Htmp0 & Htmp1 & Hini); subst.
    apply in_singleton in Hini. mydestr; subst.
    assert (In ((aconcat Bxi Bi), ρi) BxB_ρ) as Hinii. { apply Hin2. eauto. }
    exists (m{<[x:=v_x]> Γv}a (aconcat Bxi Bi)), (m{<[x:=v_x]> Γv}p ρi).
    repeat split; auto.
    + rewrite in_msubst. exists (aconcat Bxi Bi), ρi. repeat split; auto.
      * rewrite msubst_fv; auto. admit.
      * rewrite msubst_fv; auto. admit.
    + repeat msubst_simp. apply am_concat; auto. rewrite am_denotation_fv; auto.
  - intros Γ v1 v2 e ρ Tx A T Bx_ρx BxB_ρ Bx_ρx_B_ρ L HWF _ HDv2 _ HDv1 Hin1 Hin2 _ He Γv HΓv.
    auto_pose_fv x. repeat specialize_with x. repeat msubst_simp.
    specialize (HDv1 _ HΓv). specialize (HDv2 _ HΓv). repeat msubst_simp.
    rewrite <- denotation_value_pure in HDv1. rewrite <- denotation_value_pure in HDv2. admit.
  - intros Γ op v2 e ρ A ϕx T Aop' Bi ρi L HAop' HWF Hbuiltin _ HDv2 _ He Γv HΓv.
    auto_pose_fv x. repeat specialize_with x. specialize (HDv2 _ HΓv).
    split. admit. split. admit. repeat msubst_simp.
    intros HBtyped α β v HDα Hstepv. repeat msubst_simp.
    rewrite reduction_tleteffop in Hstepv. destruct Hstepv as (Hbe & (c2 & c_x & β' & Hc2 & Hβ' & Hc_x & Hstepv)); subst.
    assert ((exists (c: constant), v2 = c) \/ exists (x2: atom), v2 = x2) as Htmp. admit.
    destruct Htmp as [(c & Hc) | (x2 & Hx2)]; mydestr; subst.
    + invclear HAop'.
      assert ((p⟦ρ⟧) c) as HDc. admit.
      specialize (well_formed_builtin_typing _ _ _ _ _ Hbuiltin _ HDc) as HstepOP.
      assert ((m{Γv}a) (A ^a^ c) = (A ^a^ c)) as HAclosed. admit. rewrite HAclosed in HDα.
      specialize (HstepOP _ HDα). destruct HstepOP as (_ & HDD). repeat msubst_simp. invclear Hc2.
      specialize (HDD _ Hc_x).
      exists ((m{Γv}a) (⟨op|b1:c= c2 ∧∧({1 ~q> c2 } ϕx)⟩ ;+ Bi)), (m{Γv}p ρi). split. admit. repeat msubst_simp.
      assert (is_Aop op c2 x ⟨op|b1:c= c2 ∧∧ b0:x= x ⟩) as HAop. { constructor. }
      assert (ctxRst (Γ ++ [(x, {v:ret_ty_of_op op|{1 ~q> c2} ϕx})]) (<[ x:= vconst c_x ]> Γv)) as HΓv'. admit.
      specialize (He _ HAop _ HΓv').
      destruct He as (_ & _ & He). rewrite <- msubst_open_hty in He. 2: { admit. }
      repeat msubst_simp.
      assert (amlist_typed ((m{Γv}pa) [(Bi, ρi)] ^pa^ c_x) T) as Hamlist'. admit.
      specialize (He Hamlist' (α ++ [ev{op~c2:=c_x}]) β' v).
      assert ((a⟦((m{Γv}a) A);+((m{Γv}a) ⟨op|b1:c=c2∧∧b0:x=x⟩) ^a^ c_x⟧) (α ++ [ev{op~c2:=c_x}])) as H1. admit.
      assert ((α ++ [ev{op~c2:= c_x}]) ⊧ (m{<[x:= vconst c_x]> Γv}t) (e ^t^ x) ↪*{ β'} v) as H2. admit.
      specialize (He H1 H2).
      destruct He as (y1 & y2 & Hy1y2 & Hy1 & Hy2).
      assert (y1 = m{Γv}a Bi /\ y2 = m{Γv}p ρi) as Htmp4. admit. mydestr; subst.
      split; auto. repeat msubst_simp. admit.
    + admit.
  - intros Γ v e1 e2 τ HWFτ _ HDv _ HDe1 Hte2 Γv HΓv.
    specialize (HDv _ HΓv). specialize (HDe1 _ HΓv). repeat msubst_simp. rewrite <- denotation_value_pure in HDv.
    assert (((m{Γv}v) v) = true) as Htmp. admit. rewrite Htmp in HDv. rewrite Htmp. clear Htmp.
    destruct τ. repeat msubst_simp.
    destruct HDe1 as (Hte1 & Hclosede1 & HDe1).
    split. admit. split. admit.
    intros HBtyped α β v' HDα Hstepv. eapply HDe1; eauto.
    rewrite reduction_matchb_true in Hstepv; mydestr; auto.
  - (* same as matchb true *) admit.
Admitted.
