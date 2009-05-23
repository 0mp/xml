(*
 * (c) 2007-2009 Anastasia Gornostaeva <ermine@ermine.pp.ru>
 * 
 * http://www.w3.org/TR/xml (fourth edition)
 * http://www.w3.org/TR/REC-xml-names
 *)

exception NonXmlelement
exception InvalidNS

type namespace = [
| `URI of string
| `None
]

type prefix = string

type ncname = string

type name = ncname

type qname = namespace * prefix * name

type cdata = string

type attribute = qname * cdata

type element = 
  | Xmlelement of qname * attribute list * element list
  | Xmlcdata of cdata

let ns_xml = `URI "http://www.w3.org/XML/1998/namespace"

let no_ns = `None

let encode = Xml_encode.encode
let decode = Xml_decode.decode

module Serialization =
struct
  type t = {
    default_nss: namespace list;
    bindings: (string, string) Hashtbl.t
  }

   let bind_prefix t prefix namespace =
     match namespace with
       | `None -> raise InvalidNS
       | `URI str -> Hashtbl.add t.bindings str prefix
             
   let create default_nss =
     let bindings = Hashtbl.create 5 in
     let t =
       { default_nss = default_nss;
         bindings = bindings
       } in
       bind_prefix t "xml" ns_xml;
       t

   let string_of_qname t (ns, _prefix, name) =
     match ns with
       | `None -> name
       | `URI str -> 
           let prefix =
             try Hashtbl.find t.bindings str with Not_found -> "" in
             if prefix = "" then
               name
             else
               prefix ^ ":" ^ name
                 
   let string_of_attr t (qname, value) =
     (string_of_qname t qname) ^ "='" ^ encode value ^ "'"
       
   let string_of_list f sep = function
     | [] -> ""
     | x :: [] -> f x
     | x :: xs -> List.fold_left (fun res x -> res ^ sep ^ (f x)) (f x) xs
         
   let string_of_ns t ns =
     match ns with 
       | `None -> ""
       | `URI str ->
           let prefix = 
             try Hashtbl.find t.bindings str with Not_found -> "" in
             if prefix = "" then
               "xmlns='" ^ encode str ^ "'"
             else
               "xmlns:" ^ prefix ^ "='" ^ encode  str ^ "'"
                 
                 
   let local_namespaces t (ns, _prefix, _name) attrs lnss =
     let lnss =
       if List.mem ns t.default_nss || List.mem ns lnss then
         lnss
       else
         ns :: lnss
     in
       List.fold_left (fun acc ((ns, _prefix, _name), _value) ->
                         if ns = no_ns ||
                           ns = ns_xml ||
                           List.mem ns t.default_nss || 
                           List.mem ns lnss then
                             acc
                         else
                           ns :: acc) lnss attrs
         
   let rec aux_serialize lnss t out = function
     | Xmlelement ((ns, _prefix, _name) as qname, attrs, children) ->
         out "<";
         out (string_of_qname t qname);
         if attrs <> [] then (
           out " ";
           out (string_of_list (string_of_attr t) " " attrs)
         );
         let lnss = local_namespaces t qname attrs lnss in
           if lnss <> [] then (
             out " ";
             out (string_of_list (string_of_ns t) " " lnss)
           );
           if children = [] then
             out "/>"
           else (
             out ">";
             List.iter (aux_serialize []
                          {t with default_nss = lnss @ t.default_nss} 
                          out) children;
             out "</";
             out (string_of_qname t qname);
             out ">"
           )
     | Xmlcdata text ->
         out (encode text)
           
   let serialize_document t out xml =
     aux_serialize t.default_nss t out xml
       
end

let get_qname = function
  | Xmlelement (qname, _, _) -> qname
  | _ -> raise NonXmlelement
      
let get_namespace (namespace, _prefix, _name) = namespace

let get_prefix (_ns, prefix, _name) = prefix
  
let is_prefixed (_ns, prefix, _name) = prefix = ""
  
let get_name (_namespace, _prefix, name) = name

let match_qname ?ns ?(can_be_prefixed=false) name (ns', prefix', name') =
  (name' = name) &&
    (match ns with None -> true | Some v -> ns' = v) &&
    (match can_be_prefixed with true -> true | false -> prefix' = "")
  
let get_attrs ?ns = function
  | Xmlelement (_', attrs, _) -> (
      match ns with
        | None -> attrs
        | Some v -> List.find_all (fun ((ns', _, _), _) -> ns' = v) attrs
    )
  | _ -> raise NonXmlelement
      
let get_attr_value ?ns ?(can_be_prefixed=false) name attrs =
  let (_, value) =
    List.find (fun (qname, _) ->
                 match_qname ?ns ~can_be_prefixed name qname
              ) attrs
  in
    value
      
let safe_get_attr_value ?ns ?(can_be_prefixed=false) name attrs =
  try get_attr_value ?ns ~can_be_prefixed name attrs with Not_found -> ""
     
let get_element ?ns ?(can_be_prefixed=false) name childs =
  List.find (function
               | Xmlelement (qname, _, _) ->
                   match_qname ?ns ~can_be_prefixed name qname
               | _ -> false
            ) childs
    
let get_elements ?ns ?(can_be_prefixed=false) name childs =
  List.filter (function
                 | Xmlelement (qname, _, _) ->
                     match_qname ?ns ~can_be_prefixed name qname
                 | Xmlcdata cdata -> false
              ) childs
    
let get_children = function
  | Xmlelement (_, _, children) -> children
  | _ -> raise NonXmlelement
      
let get_subelement ?ns ?(can_be_prefixed=false) name el =
  get_element ?ns ~can_be_prefixed name (get_children el)
    
let get_subelements ?ns ?(can_be_prefixed=false) name el =
  get_elements ?ns ~can_be_prefixed name (get_children el)
    
let get_first_element els =
  List.find (function
               | Xmlelement _ -> true
               | _ -> false) els
    
let get_cdata el =
  let childs = get_children el in
  let rec collect_cdata acc = function
    | [] -> String.concat "" (List.rev acc)
    | (Xmlcdata cdata) :: l -> collect_cdata (cdata :: acc) l
    | _ :: l -> collect_cdata acc l
  in
    collect_cdata [] childs
      
let remove_cdata els =
  List.filter (function
                 | Xmlelement _ -> true
                 | _ -> false) els
    
let make_element qname attrs children =
  Xmlelement (qname, attrs, children)
    
let make_attr ?ns ?prefix  name value =
  let ns = match ns with None -> no_ns | Some v -> v in
  let prefix = match prefix with None -> "" | Some v -> v in
    (ns, prefix, name), value
    
let make_simple_cdata qname cdata =
  Xmlelement (qname, [], [Xmlcdata cdata])
    
let mem_qname ?ns ?(can_be_prefixed=false) name els =
  List.exists (function
                 | Xmlelement (qname, _, _) ->
                     match_qname ?ns ~can_be_prefixed name qname
                 | _ -> false) els
    
let mem_child ?ns ?(can_be_prefixed=false) name el =
  mem_qname ?ns ~can_be_prefixed name (get_children el)
      
let iter f el = List.iter f (get_children el)
  
(*
 * Parsing
 *)
  
let split_attrs attrs =
  List.fold_left (fun (nss, attrs) (name, value) ->
                    let prefix, lname = Xmlparser.split_name name in
                      if prefix = "" && lname = "xmlns" then
                        ((`URI value, "") :: nss), attrs
                      else if prefix = "xmlns" && lname <> "" then
                        ((`URI value, lname) :: nss) , attrs
                      else
                        nss, (((prefix, lname), value) :: attrs)
                 ) ([], []) attrs
    
let add_namespaces namespaces nss =
  List.iter (fun (ns, prefix) -> Hashtbl.add namespaces prefix ns) nss
    
let remove_namespaces namespaces nss =
  List.iter (fun (ns, prefix) -> Hashtbl.remove namespaces prefix) nss
    
let parse_qname nss (prefix, lname) =
  try
    let namespace = Hashtbl.find nss prefix in
      (namespace, prefix, lname)
  with Not_found ->
    (no_ns, prefix, lname)
      
let parse_qname_attribute nss (prefix, lname) = 
  if prefix = "" then
    no_ns, prefix, lname
  else
    try
      let ns = Hashtbl.find nss prefix in
        ns, prefix, lname
    with Not_found ->
      (no_ns, prefix, lname)
        
let parse_attrs nss attrs =
  List.map (fun (name, value) -> parse_qname_attribute nss name, value) attrs
    
let parse_element_head namespaces name attrs =
  let lnss, attrs = split_attrs attrs in
    add_namespaces namespaces lnss;
    let qname = parse_qname namespaces (Xmlparser.split_name name) in
    let attrs =  parse_attrs namespaces attrs in
      qname, lnss, attrs
        
let string_of_tag (ns, _prefix, name) =
  let prefix =
    match ns with
      | `None -> ""
      | `URI str -> "URI " ^ str
  in
    Printf.sprintf "(%S) %s" prefix name
      
let process_production (state, tag) =
  let namespaces = Hashtbl.create 1 in
  let () = Hashtbl.add namespaces "xml" ns_xml in
    
  let rec process_prolog (state, tag) =
    match tag with
      | Xmlparser.Comment _
      | Xmlparser.Doctype _
      | Xmlparser.Pi _
      | Xmlparser.Whitespace _ ->
          process_prolog (Xmlparser.parse state)
      | Xmlparser.StartElement (name, attrs) ->
          let qname, lnss, attrs = parse_element_head namespaces name attrs in
          let nextf childs (state, tag) =
            let el = Xmlelement (qname, attrs, childs) in
              remove_namespaces namespaces lnss;
              process_epilogue el (state, tag)
          in
            get_childs qname nextf [] (Xmlparser.parse state)
      | Xmlparser.EndOfBuffer ->
          failwith "End of Buffer"
      | Xmlparser.EndOfData ->
          raise End_of_file
      | _ ->
          failwith "Unexpected tag"
            
  and get_childs qname nextf childs (state, tag) =
    match tag with
      | Xmlparser.Whitespace str ->
          get_childs qname nextf (Xmlcdata str :: childs) (Xmlparser.parse state)
      | Xmlparser.Text str ->
          get_childs qname nextf (Xmlcdata str :: childs) (Xmlparser.parse state)
      | Xmlparser.StartElement (name, attrs) ->
          let qname', lnss, attrs = parse_element_head namespaces name attrs in
          let newnextf childs' (state, tag) =
            let child = 
              Xmlelement (qname', attrs, childs') in
              remove_namespaces namespaces lnss;
              get_childs qname nextf (child :: childs) (state, tag)
          in
            get_childs qname' newnextf [] (Xmlparser.parse state)
      | Xmlparser.EndElement name ->
          let qname' = parse_qname namespaces (Xmlparser.split_name name) in
            if qname = qname' then
              nextf (List.rev childs) (Xmlparser.parse state)
            else 
              failwith (Printf.sprintf "Bad end tag: expected %s, was %s"
                          (string_of_tag qname)
                          (string_of_tag qname'))
      | Xmlparser.Comment _
      | Xmlparser.Pi _ ->
          get_childs qname nextf childs (Xmlparser.parse state)
      | Xmlparser.Doctype _dtd ->
          failwith "Doctype declaration inside of element"
      | Xmlparser.EndOfBuffer ->
          failwith "End of Buffer"
      | Xmlparser.EndOfData ->
          raise End_of_file
            
  and process_epilogue el (state, tag) =
    match tag with
      | Xmlparser.Comment _
      | Xmlparser.Pi _
      | Xmlparser.Whitespace _ ->
          process_epilogue el (Xmlparser.parse state)
      | Xmlparser.EndOfBuffer ->
          failwith "End Of Buffer"
      | Xmlparser.EndOfData ->
          el
      | _ ->
          failwith "Invalid epilogue"
  in
    process_prolog (state, tag)

let parse_document ?unknown_encoding_handler ?entity_resolver buf =
  let p = Xmlparser.create ?unknown_encoding_handler ?entity_resolver () in
    process_production (Xmlparser.parse ~buf ~finish:true p)
      
