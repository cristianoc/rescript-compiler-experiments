(* Copyright (C) 2015 - 2016 Bloomberg Finance L.P.
 * Copyright (C) 2017 - Hongbo Zhang, Authors of ReScript
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)






(* When we design a ppx, we should keep it simple, and also think about
   how it would work with other tools like merlin and ocamldep  *)

(**
   1. extension point
   {[
     [%bs.raw{| blabla |}]
   ]}
   will be desugared into
   {[
     let module Js =
     struct unsafe_js : string -> 'a end
     in Js.unsafe_js {| blabla |}
   ]}
   The major benefit is to better error reporting (with locations).
   Otherwise

   {[

     let f u = Js.unsafe_js u
     let _ = f (1 + 2)
   ]}
   And if it is inlined some where
*)




let () =
  Ast_derive_projector.init ();
  Ast_derive_js_mapper.init ()


let succeed attr attrs = 
  match attrs with 
  | [ _ ] -> ()
  | _ -> 
    Bs_ast_invariant.mark_used_bs_attribute attr;  
    Bs_ast_invariant.warn_discarded_unused_attributes attrs 

type mapper = Bs_ast_mapper.mapper
let default_mapper = Bs_ast_mapper.default_mapper
let default_expr_mapper = Bs_ast_mapper.default_mapper.expr 
let default_pat_mapper = Bs_ast_mapper.default_mapper.pat 
let pat_mapper (self : mapper) (e : Parsetree.pattern) = 
  match e.ppat_desc with 
  | Ppat_constant (Pconst_integer (s, Some 'l')) ->
    {e with ppat_desc = Ppat_constant (Pconst_integer(s,None))}
  | _ -> default_pat_mapper  self e 
let expr_mapper ~async_context ~in_function_def (self : mapper) (e : Parsetree.expression) =
  let old_in_function_def = !in_function_def in
  in_function_def := false;
  match e.pexp_desc with
  (* Its output should not be rewritten anymore *)
  | Pexp_extension extension ->
    Ast_exp_extension.handle_extension e self extension
  | Pexp_setinstvar ({txt;loc},expr) -> 
    if Stack.is_empty Js_config.self_stack then 
      Location.raise_errorf ~loc:e.pexp_loc "This assignment can only happen in object context";
    let name = Stack.top Js_config.self_stack in   
    if name = "" then 
      Location.raise_errorf ~loc:e.pexp_loc 
        "The current object does not assign a name";
    let open Ast_helper in     
    self.expr self 
      (Exp.apply ~loc:e.pexp_loc 
        (Exp.ident ~loc {loc; txt = Lident "#="})
        [Nolabel,
         (Exp.send  ~loc 
            (Exp.ident ~loc {loc; txt = Lident name})
            {loc ; txt});
         Nolabel, expr
         ])
  | Pexp_constant (
      Pconst_string
        (s, (Some delim)))
    ->
    Ast_utf8_string_interp.transform e s delim
  | Pexp_constant(
    Pconst_integer(s, Some 'l')
  ) ->
    {e with pexp_desc = Pexp_constant(Pconst_integer (s,None))} 
  (* End rewriting *)
  | Pexp_function cases ->
    (* {[ function [@bs.exn]
         | Not_found -> 0
         | Invalid_argument -> 1
       ]}*)
    async_context := false;
    (match Ast_attributes.process_pexp_fun_attributes_rev e.pexp_attributes with
     | false, _ ->
       default_expr_mapper self  e
     | true, pexp_attributes ->
       Ast_bs_open.convertBsErrorFunction e.pexp_loc self  pexp_attributes cases)

  | Pexp_fun (label, _, pat , body)
    ->
    let async = Ast_attributes.has_async_payload e.pexp_attributes <> None in
    begin match Ast_attributes.process_attributes_rev e.pexp_attributes with
      | Nothing, _ ->
        (* Handle @async x => y => ... is in async context *)
        async_context := (old_in_function_def && !async_context) || async;
        in_function_def := true;
        Ast_async.make_function_async ~async (default_expr_mapper self e)
      | Uncurry _, pexp_attributes
        ->
        async_context := async;
        {e with
         pexp_desc = Ast_uncurry_gen.to_uncurry_fn e.pexp_loc self label pat body async;
         pexp_attributes}
      | Method _ , _
        ->  Location.raise_errorf ~loc:e.pexp_loc "%@meth is not supported in function expression"
      | Meth_callback _, pexp_attributes
        ->
        (* FIXME: does it make sense to have a label for [this] ? *)
        async_context := false;
        {e with pexp_desc = Ast_uncurry_gen.to_method_callback e.pexp_loc  self label pat body ;
                pexp_attributes }
    end
  | Pexp_apply (fn, args  ) ->
    Ast_exp_apply.app_exp_mapper e self fn args
  | Pexp_object {pcstr_self;  pcstr_fields} ->
    let pexp_attributes = 
      match Ast_attributes.process_bs e.pexp_attributes with
      | true, pexp_attributes
        -> 
        Location.prerr_warning e.pexp_loc (Bs_ffi_warning "Here @bs attribute not needed any more");
        pexp_attributes 
      | false, e -> e in    
    {e with
     pexp_desc =
       Ast_util.ocaml_obj_as_js_object
         e.pexp_loc self pcstr_self pcstr_fields;
     pexp_attributes
    }

  | Pexp_match(b,
               [
                 {pc_lhs= {ppat_desc = Ppat_construct ({txt = Lident "true"},None)};pc_guard=None;pc_rhs=t_exp};
                 {pc_lhs= {ppat_desc = Ppat_construct ({txt = Lident"false"}, None)};pc_guard=None;pc_rhs=f_exp}
               ]) 
  | Pexp_match(b,
               [
                 {pc_lhs= {ppat_desc = Ppat_construct ({txt = Lident "false"},None)};pc_guard=None;pc_rhs=f_exp};
                 {pc_lhs= {ppat_desc = Ppat_construct ({txt = Lident"true"}, None)};pc_guard=None;pc_rhs=t_exp}
               ])   
    -> 
    default_expr_mapper self {e with pexp_desc = Pexp_ifthenelse (b,t_exp,Some f_exp)}    
  | Pexp_let (Nonrecursive, 
              [{pvb_pat = 
                  ({ ppat_desc = Ppat_record _ }
                  |{ ppat_desc = Ppat_alias ({ppat_desc = Ppat_record _},_)}
                  ) as p; 
                pvb_expr; 
                pvb_attributes; 
                pvb_loc = _}], body)             
    -> 
    begin match pvb_expr.pexp_desc with 
      | Pexp_pack _ -> default_expr_mapper self e 
      | _ -> 
        default_expr_mapper self 
          {e with 
           pexp_desc = Pexp_match(pvb_expr,
                                  [{pc_lhs = p; pc_guard = None; 
                                    pc_rhs = body}]);
           pexp_attributes = e.pexp_attributes @  pvb_attributes
          }
    end
  (* let [@warning "a"] {a;b} = c in body 
     The attribute is attached to value binding, 
     after the transformation value binding does not exist so we attach 
     the attribute to the whole expression, in general, when shuffuling the ast
     it is very hard to place attributes correctly
  *)
  | _ ->  default_expr_mapper self e

let expr_mapper ~async_context ~in_function_def (self : mapper) (e : Parsetree.expression) =
  let async_saved = !async_context in
  let result = expr_mapper ~async_context ~in_function_def self e in
  async_context := async_saved;
  match Ast_attributes.has_await_payload e.pexp_attributes with
  | None -> result
  | Some _ ->
    if !async_context = false then
      Location.raise_errorf ~loc:e.pexp_loc "Await on expression not in an async context";
    Ast_await.create_await_expression result

let typ_mapper (self : mapper) (typ : Parsetree.core_type) = 
  Ast_core_type_class_type.typ_mapper self typ

let class_type_mapper (self : mapper) ({pcty_attributes; pcty_loc} as ctd : Parsetree.class_type) = 
  let pcty_attributes = 
    match Ast_attributes.process_bs pcty_attributes with
    | false,  _ ->
      pcty_attributes
    | true, pcty_attributes -> 
      Location.prerr_warning pcty_loc (Bs_ffi_warning "Here @bs attribute is not needed any more.");
      pcty_attributes in 
  (match ctd.pcty_desc with
   | Pcty_signature ({pcsig_self; pcsig_fields })
     ->
     let pcsig_self = self.typ self pcsig_self in
     {ctd with
      pcty_desc = Pcty_signature {
          pcsig_self ;
          pcsig_fields = Ast_core_type_class_type.handle_class_type_fields self pcsig_fields
        };
      pcty_attributes
     }               
   | Pcty_open _ (* let open M in CT *)
   | Pcty_constr _
   | Pcty_extension _
   | Pcty_arrow _ ->
     default_mapper.class_type self ctd)
(* {[class x : int -> object
     end [@bs]
   ]}
           Actually this is not going to happpen as below is an invalid syntax
   {[class type x = int -> object
       end[@bs]]}
*)


let signature_item_mapper (self : mapper) (sigi : Parsetree.signature_item) 
  : Parsetree.signature_item =        
  match sigi.psig_desc with
  | Psig_type (
      rf, 
      tdcls) ->  
    Ast_tdcls.handleTdclsInSigi self sigi rf tdcls
  | Psig_value ({pval_attributes; pval_prim} as value_desc)

    ->
    let pval_attributes = self.attributes self pval_attributes in 
  if Ast_attributes.rs_externals pval_attributes pval_prim then     
  Ast_external.handleExternalInSig self value_desc sigi  
    else 
      (match 
         Ast_attributes.has_inline_payload
           pval_attributes with 
      | Some ((_,PStr [{pstr_desc = Pstr_eval ({pexp_desc },_)}]) as attr) ->
        begin match pexp_desc with
          | Pexp_constant (
              Pconst_string
                (s,dec)) -> 
            succeed attr pval_attributes;
            { sigi with 
              psig_desc = Psig_value
                  { 
                    value_desc with
                    pval_prim = External_ffi_types.inline_string_primitive s dec;
                    pval_attributes = []
                  }}
          | Pexp_constant(
              Pconst_integer (s,None)
            ) ->       
            succeed attr pval_attributes;  
            let s = Int32.of_string s in  
            { sigi with 
              psig_desc = Psig_value
                  { 
                    value_desc with
                    pval_prim = External_ffi_types.inline_int_primitive s ;
                    pval_attributes = []
                  }}
          | Pexp_constant(Pconst_integer (s, Some 'L'))
            -> 
            let s = Int64.of_string s in  
            succeed attr pval_attributes;
            {sigi with psig_desc = Psig_value  {
                 value_desc with 
                 pval_prim = External_ffi_types.inline_int64_primitive s;
                 pval_attributes = [];
               } }
          | Pexp_constant (Pconst_float(s,None)) -> 
            succeed attr pval_attributes;
            {sigi with psig_desc = Psig_value  {
                 value_desc with 
                 pval_prim = External_ffi_types.inline_float_primitive s;
                 pval_attributes = [];
               } }
          | Pexp_construct ({txt = Lident ("true" | "false" as txt)}, None)       
            -> 
            succeed attr pval_attributes;
            { sigi with 
              psig_desc = Psig_value
                  { 
                    value_desc with
                    pval_prim = External_ffi_types.inline_bool_primitive (txt = "true") ;
                    pval_attributes = []
                  }}
          | _ -> 
            default_mapper.signature_item self sigi
        end 
      | Some  _            
      | None ->
        default_mapper.signature_item self sigi
      )
  | _ -> default_mapper.signature_item self sigi


let structure_item_mapper (self : mapper) (str : Parsetree.structure_item) : Parsetree.structure_item =
  match str.pstr_desc with
  | Pstr_type (
      rf, 
      tdcls) (* [ {ptype_attributes} as tdcl ] *)->
    Ast_tdcls.handleTdclsInStru self str rf tdcls
  | Pstr_primitive prim 
    when Ast_attributes.rs_externals prim.pval_attributes prim.pval_prim
    ->
    Ast_external.handleExternalInStru self prim str
  | Pstr_value 
      (Nonrecursive, [
          {
            pvb_pat = ({ppat_desc = Ppat_var pval_name} as pvb_pat); 
            pvb_expr ; 
            pvb_attributes ; 
            pvb_loc}]) 

    ->   
    let pvb_expr = self.expr self pvb_expr in 
    let pvb_attributes = self.attributes self pvb_attributes in 
    let has_inline_property = Ast_attributes.has_inline_payload pvb_attributes in    
    begin match has_inline_property, pvb_expr.pexp_desc with 
      | Some attr, Pexp_constant(
          Pconst_string
            (s,dec))
        ->      
        succeed attr pvb_attributes; 
        {str with pstr_desc = Pstr_primitive  {
             pval_name = pval_name ;
             pval_type = Ast_literal.type_string (); 
             pval_loc = pvb_loc;
             pval_attributes = [];
             pval_prim = External_ffi_types.inline_string_primitive s dec
           } } 
      | Some attr, Pexp_constant(Pconst_integer (s,None))
        -> 
        let s = Int32.of_string s in  
        succeed attr pvb_attributes; 
        {str with pstr_desc = Pstr_primitive  {
             pval_name = pval_name ;
             pval_type = Ast_literal.type_int (); 
             pval_loc = pvb_loc;
             pval_attributes = [];
             pval_prim = External_ffi_types.inline_int_primitive s
           } }
      | Some attr, Pexp_constant(Pconst_integer (s, Some 'L'))
        -> 
        let s = Int64.of_string s in  
        succeed attr pvb_attributes; 
        {str with pstr_desc = Pstr_primitive  {
             pval_name = pval_name ;
             pval_type = Ast_literal.type_int64; 
             pval_loc = pvb_loc;
             pval_attributes = [];
             pval_prim = External_ffi_types.inline_int64_primitive s
           } }             
      | Some attr, Pexp_constant(Pconst_float (s, None))
        ->
        succeed attr pvb_attributes; 
        {str with pstr_desc = Pstr_primitive  {
             pval_name = pval_name ;
             pval_type = Ast_literal.type_float; 
             pval_loc = pvb_loc;
             pval_attributes = [];
             pval_prim = External_ffi_types.inline_float_primitive s
           } }                 
      | Some attr, Pexp_construct ({txt = Lident ("true" | "false" as txt) },None) -> 
        succeed attr pvb_attributes; 
        {str with pstr_desc = Pstr_primitive  {
             pval_name = pval_name ;
             pval_type = Ast_literal.type_bool (); 
             pval_loc = pvb_loc;
             pval_attributes = [];
             pval_prim = External_ffi_types.inline_bool_primitive (txt = "true")
           } }
      | _ ->
        { str with pstr_desc =  Pstr_value(Nonrecursive, [{pvb_pat ; pvb_expr; pvb_attributes; pvb_loc}])}
    end
  | Pstr_attribute({txt = "bs.config" | "config" },_)  -> str      
  | _ -> default_mapper.structure_item self str


let local_module_name =     
  let v = ref 0 in       
  fun  () -> 
    incr v ;
    "local_" ^ string_of_int !v


let expand_reverse  (stru : Ast_structure.t) (acc : Ast_structure.t) : Ast_structure.t = 
  if stru = [] then acc 
  else begin 
    Typemod_hide.check stru; 
    let local_module_name = local_module_name () in 
    let last_loc = (List.hd stru).pstr_loc  in 
    let stru = List.rev stru in 
    let first_loc = (List.hd  stru).pstr_loc in 
    let loc = {first_loc with loc_end = last_loc.loc_end; } in  
    let open Ast_helper in 
    Str.module_         
      ~loc
      { pmb_name = {txt = local_module_name; loc}; 
        pmb_expr = {
          pmod_desc= Pmod_structure stru;
          pmod_loc = loc; 
          pmod_attributes = [] };
        pmb_attributes = Typemod_hide.attrs; pmb_loc = loc} ::
    Str.open_ ~loc {
      popen_lid = {txt = Lident local_module_name; loc};
      popen_override = Override;
      popen_loc = loc;
      popen_attributes = []
    } :: acc   
  end


let rec 
  structure_mapper (self : mapper) (stru : Ast_structure.t) =     
  match stru with 
  | [] -> []  
  | item::rest -> 
    match item.pstr_desc with 
    | Pstr_extension ( ({txt = ("bs.raw"| "raw") ; loc}, payload), _attrs)
      ->
      Ast_exp_handle_external.handle_raw_structure loc payload :: structure_mapper self rest
    (* | Pstr_extension (({txt = "i"}, _),_)
      -> 
      structure_mapper self rest *)
    | Pstr_extension (({txt = "private"}, _),_)
      -> 
      let rec aux acc (rest : Ast_structure.t) =
        match rest with 
        | {pstr_desc = Pstr_extension (({txt = "private";loc}, payload), _) } :: next -> 
          begin match payload with  
            | PStr work -> 
              aux (Ext_list.rev_map_append work acc (fun x -> self.structure_item self x)) next 
            | (PSig _ | PTyp _ | PPat _) -> 
              Location.raise_errorf ~loc "private extension is not support"
          end        
        | _ -> expand_reverse acc (structure_mapper self rest)
      in  aux  [] stru
    | _ ->    
      self.structure_item self item  :: structure_mapper self rest

let  mapper : mapper =
  { default_mapper with
    expr = expr_mapper ~async_context:(ref false) ~in_function_def:(ref false);
    pat = pat_mapper; 
    typ = typ_mapper ;
    class_type = class_type_mapper;      
    signature_item =  signature_item_mapper ;
    value_bindings = Ast_tuple_pattern_flatten.value_bindings_mapper;
    structure_item = structure_item_mapper;
    structure = structure_mapper;
    (* Ad-hoc way to internalize stuff *)
    label_declaration = (fun self lbl -> 
        let lbl = default_mapper.label_declaration self lbl in 
        match lbl.pld_attributes with 
        | [ {txt="internal"}, _ ] -> 
          {lbl with pld_name = {lbl.pld_name with txt = String.capitalize_ascii lbl.pld_name.txt };
                    pld_attributes = []}
        | _ -> lbl  
      )
  }

















