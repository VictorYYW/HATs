let rec goal (size : int) (x0 : int) =
  (if sizecheck x0
   then goal (subs size) x0
   else (subs size) +:: (goal size x0) : int ulist)