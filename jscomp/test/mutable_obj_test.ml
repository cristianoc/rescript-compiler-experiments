



type u =
  < height : int [@bs.set] > 




let f (x : u) =
  x##height#= 3  ;
  x##height * 2

let f ( x : < height : int [@bs.set{no_get}] > ) =
  x##height#=3  



type v =
   < dec : int -> < x : int ; y : float >  [@bs] [@bs.set]  >  

let f (x : v ) =
  x##dec#= (fun [@bs] x -> [%bs.obj {x ; y = float_of_int x }])   
