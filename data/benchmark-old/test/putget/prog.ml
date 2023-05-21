type effect = Put of (int -> int -> unit) | Get of (int -> int)

(* let[@equation] ret_of_put = *)
(*   eqr *)
(*     (let a = Put (b, c) in *)
(*      Ret a) *)
(*     (Ret ()) *)

(* let[@equation] ret_of_get = *)
(*   eqr *)
(*     (let a = Get b in *)
(*      Ret a) *)
(*     (Ret 0) *)

let[@effrty] put ?l:(a = (true : [%v: int])) ?l:(b = (true : [%v: int])) =
  {
    pre = epsilon;
    post =
      ((Put ((v0 == a && v1 == b : [%v0: int]) : [%v1: int]);
        Ret (true : [%v0: unit])) : unit);
  }

let[@effrty] get ?l:(a = (true : [%v: int])) =
  let phi = (true : [%v: int -> bool]) in
  {
    pre =
      (Put ((v0 == a && phi v1 : [%v0: int]) : [%v1: int]);
       star
         (lorA
            (Get (true : [%v0: int]))
            (Put ((not (v0 == a) : [%v0: int]) : [%v1: int]))));
    post =
      ((Get (v0 == a : [%v0: int]);
        Ret (phi v0 : [%v0: int])) : int);
  }

let prog (n : int) : int =
  if n <= 0 then 0
  else
    let (m : int) = nat_gen () in
    let (dummy1 : unit) = perform (Put (n, m)) in
    let (y : int) = perform (Get n) in
    y

let[@assert] prog ?l:(n = (v >= 0 : [%v: int]) [@over]) =
  {
    pre = epsilon;
    post =
      ((lorA epsilon
          (Put ((0 <= v1 : [%v0: int]) : [%v1: int]);
           Get (0 <= v0 : [%v0: int]));
        Ret (0 <= v0 : [%v0: int])) : int);
  }

(* let[@assert] prog ?l:(n = (v >= 0 : [%v: int]) [@over]) : (int[@regex]) = *)
(*   Put ((v1 == n && v2 != n : [%v1: int]) : [%v2: int]); *)
(*   Ret (v1 == 2 : [%v1: int]) *)

(* let[@assert] prog ?l:(n = (v >= 0 : [%v: int]) [@over]) : (int[@regex]) = *)
(*   lorA *)
(*     (Ret (v1 == 1 : [%v1: int])) *)
(*     (Put ((v1 == n && v2 != n : [%v1: int]) : [%v2: int]); *)
(*      Ret (v1 == 2 : [%v1: int])) *)
