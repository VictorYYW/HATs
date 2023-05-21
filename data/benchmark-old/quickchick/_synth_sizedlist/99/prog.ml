let rec goal (size : int) =
  (if sizecheck size
   then []
   else
     if bool_gen ()
     then size :: (subs size) :: (goal (subs size))
     else (gt_eq_int_gen size) :: (goal (subs (gt_eq_int_gen (subs size)))) : 
  int list)