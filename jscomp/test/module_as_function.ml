external nightmare :  < show : bool >   ->  int  = "nightmare" [@@bs.module]

let v = nightmare [%bs.obj {show = true}]
