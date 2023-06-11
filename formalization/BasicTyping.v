From stdpp Require Import mapset.
From CT Require Import CoreLangProp.

Import Atom.
Import CoreLang.
Import Tactics.
Import NamelessTactics.

Definition ty_of_const (c: constant): base_ty :=
  match c with
  | cnat _ => TNat
  | cbool _ => TBool
  end.

Definition ret_ty_of_op (op: effop): base_ty :=
  match op with
  | op_plus_one => TNat
  | op_eq_zero => TNat
  | op_rannat => TNat
  | op_ranbool => TBool
  | op_read => TNat
  | op_write => TBool
  end.

Definition ty_of_op (op: effop): ty := TNat ⤍ (ret_ty_of_op op).

Definition context := amap ty.

Reserved Notation "Γ '⊢t' t '⋮t' T" (at level 40).
Reserved Notation "Γ '⊢t' t '⋮v' T" (at level 40).

(** Basic typing rules  *)
Inductive tm_has_type : context -> tm -> ty -> Prop :=
| T_Value : forall Γ v T, Γ ⊢t v ⋮v T -> Γ ⊢t v ⋮t T
| T_Lete : forall Γ e1 e2 T1 T2 (L: aset),
    Γ ⊢t e1 ⋮t T1 ->
    (forall (x: atom), x ∉ L -> (<[ x := T1]> Γ) ⊢t e2 ^t^ x ⋮t T2) ->
    Γ ⊢t (tlete e1 e2) ⋮t T2
| T_LetOp : forall Γ (op: effop) v1 e (T1 Tx: base_ty) T (L: aset),
    Γ ⊢t v1 ⋮v T1 ->
    (ty_of_op op) = T1 ⤍ Tx ->
    (forall (x: atom), x ∉ L -> (<[x := TBase Tx]> Γ) ⊢t e ^t^ x ⋮t T) ->
    Γ ⊢t tleteffop op v1 e ⋮t T
| T_LetApp : forall Γ v1 v2 e T1 Tx T (L: aset),
    Γ ⊢t v1 ⋮v T1 ⤍ Tx ->
    Γ ⊢t v2 ⋮v T1 ->
    (forall (x: atom), x ∉ L -> (<[x := Tx]> Γ) ⊢t e ^t^ x ⋮t T) ->
    Γ ⊢t tletapp v1 v2 e ⋮t T
| T_Matchb: forall Γ v e1 e2 T,
    Γ ⊢t v ⋮v TBool ->
    Γ ⊢t e1 ⋮t T ->
    Γ ⊢t e2 ⋮t T ->
    Γ ⊢t (tmatchb v e1 e2) ⋮t T
with value_has_type : context -> value -> ty -> Prop :=
| T_Const : forall Γ (c: constant), Γ ⊢t c ⋮v (ty_of_const c)
| T_Var : forall Γ (x: atom) T,
    Γ !! x = Some T -> Γ ⊢t x ⋮v T
| T_Lam : forall Γ Tx T e (L: aset),
    (forall (x: atom), x ∉ L -> (<[x := Tx]> Γ) ⊢t e ^t^ x ⋮t T) ->
    Γ ⊢t vlam Tx e ⋮v Tx ⤍ T
| T_Fix : forall Γ (Tx: base_ty) T e (L: aset),
    (forall (f: atom), f ∉ L -> (<[f := TBase Tx]>) Γ ⊢t (vlam (Tx ⤍ T) e) ^v^ f ⋮v ((Tx ⤍ T) ⤍ T)) ->
    Γ ⊢t vfix (Tx ⤍ T) (vlam Tx e) ⋮v Tx ⤍ T
where "Γ '⊢t' t '⋮t' T" := (tm_has_type Γ t T) and "Γ '⊢t' t '⋮v' T" := (value_has_type Γ t T).

Scheme value_has_type_mutual_rec := Induction for value_has_type Sort Prop
    with tm_has_type_mutual_rec := Induction for tm_has_type Sort Prop.

Global Hint Constructors tm_has_type: core.
Global Hint Constructors value_has_type: core.

Lemma basic_typing_contains_fv_tm: forall Γ e T, Γ ⊢t e ⋮t T -> fv_tm e ⊆ dom Γ.
Admitted.

Lemma basic_typing_contains_fv_value: forall Γ e T, Γ ⊢t e ⋮v T -> fv_value e ⊆ dom Γ.
Admitted.

Ltac instantiate_atom_listctx :=
  let acc := collect_stales tt in
  instantiate (1 := acc); intros;
  repeat (match goal with
          | [H: forall (x: atom), x ∉ ?L -> _, H': ?a ∉ _ ∪ (stale _) |- _ ] =>
              assert (a ∉ L) as Htmp by fast_set_solver;
              specialize (H a Htmp); clear Htmp; repeat destruct_hyp_conj; auto
          end; simpl).

Lemma basic_typing_regular_value: forall Γ v t, Γ ⊢t v ⋮v t -> lc v.
Admitted.

Lemma basic_typing_regular_tm: forall Γ e t, Γ ⊢t e ⋮t t -> lc e.
Admitted.

Ltac basic_typing_regular_simp :=
  repeat match goal with
    | [H: _ ⊢t _ ⋮v _ |- lc _] => apply basic_typing_regular_value in H; destruct H; auto
    | [H: _ ⊢t _ ⋮t _ |- lc _] => apply basic_typing_regular_tm in H; destruct H; auto
    | [H: _ ⊢t _ ⋮v _ |- body _] => apply basic_typing_regular_value in H; destruct H; auto
    | [H: _ ⊢t _ ⋮t _ |- body _] => apply basic_typing_regular_tm in H; destruct H; auto
    end.

Lemma empty_basic_typing_bool_value_exists: forall (v: value), ∅ ⊢t v ⋮v TBool -> v = true \/ v = false.
Admitted.

Lemma empty_basic_typing_nat_value_exists: forall (v: value), ∅ ⊢t v ⋮v TNat -> (exists (i: nat), v = i).
Admitted.

Lemma empty_basic_typing_base_const_exists: forall (v: value) (B: base_ty), ∅ ⊢t v ⋮v B -> (exists (c: constant), v = c).
Admitted.


Lemma empty_basic_typing_arrow_value_lam_exists:
  forall (v: value) T1 T2, ∅ ⊢t v ⋮v T1 ⤍ T2 ->
                        (exists e, v = vlam T1 e) \/ (exists e, v = vfix (T1 ⤍ T2) (vlam T1 e)).
Admitted.

Lemma tricky_closed_value_exists: forall (T: ty), exists v, forall Γ, Γ ⊢t v ⋮v T.
Proof.
  induction T.
  - destruct b. exists 0. constructor; auto. exists true. constructor; auto.
  - mydestr. exists (vlam T1 x). econstructor; eauto.
    intros.
Admitted.