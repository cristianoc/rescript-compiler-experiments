

class type v = object
  method hey : int -> int -> int 
end 

class type v2 = object
  method hey : int -> int -> int 
end 

type vv = 
  < 
    hey : int -> int -> int [@bs]
  >  

type vv2 = 
  < 
    hey : int -> int -> int [@bs]
  > 


val test_v : v  -> int
val test_vv : vv -> int 
