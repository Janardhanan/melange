(*
   dnsquery.ml -- map DNS query-response mechanism onto trie database
   Copyright (c) 2005-2006 Tim Deegan <tjd@phlegethon.org>      
*)

open Dnsrr
open Dnstrie

open Dns
open Dns_rr

module H = Hashcons

(* We answer a query with RCODE, AA, ANSWERS, AUTHORITY and ADDITIONAL *)

type query_answer = {
    rcode : Dns.rcode_t;
    aa: bool;
    answer: (Mpl_stdlib.env -> Dns.Answers.o) list;
    authority: (Mpl_stdlib.env -> Dns.Authority.o) list;
    additional: (Mpl_stdlib.env -> Dns.Additional.o) list;
  } 


let answer_query qname qtype trie = 

  let aa_flag = ref true in
  let ans_rrs = ref [] in
  let auth_rrs = ref [] in
  let add_rrs = ref [] in
  let addqueue = ref [] in
  let rrlog = ref [] in 

  (* We must avoid repeating RRSets in the response.  To do this, we
     keep two lists: one of RRSets that are already included, and one of
     RRSets we plan to put in the additional records section.  When we
     add an RRSet to the answer or authority section we strip it from
     the additionals queue, and when we enqueue an additional RRSet we
     make sure it's not already been included.  
     N.B. (1) We only log those types that might turn up more than once. 
     N.B. (2) We can use "==" and "!=" because owners are unique:
              they are either the owner field of a dnsnode from the 
              trie, or they are the qname, which only happens if it 
              does not have any RRSets of its own and matched a wildcard.*)
  let log_rrset owner rrtype =
    addqueue := List.filter 
	(fun (n, t) -> rrtype != t || owner != n.owner.H.node) !addqueue;
    rrlog := (owner, rrtype) :: !rrlog
  in
  let in_log owner rrtype = 
      List.exists (fun (o, t) -> o == owner && t == rrtype) !rrlog
  in
  let enqueue_additional dnsnode rrtype = 
    if not (in_log dnsnode.owner.H.node rrtype) 
    then addqueue := (dnsnode, rrtype) :: !addqueue 
  in

  (* Map an RRSet into MPL closures and include it in the response *)
  let add_rrset owner ttl rdata section = 
    let addfn x = match section with 
      `Answer -> ans_rrs := (Dns.Answers.t ~rr:x) :: !ans_rrs 
    | `Authority -> auth_rrs := (Dns.Authority.t ~rr:x) :: !auth_rrs 
    | `Additional -> add_rrs := (Dns.Additional.t ~rr:x) :: !add_rrs 
    in
    let mapfn ?(aclass = Some `IN) x = x ~name:owner ?aclass ~ttl:ttl in
    match rdata with 
      A l -> log_rrset owner `A; 
        List.iter (fun i -> addfn (`A (mapfn Dns_rr.A.t ~ip:i))) l
    | NS l -> log_rrset owner `NS;
	List.iter (fun d -> 
	  enqueue_additional d `A;
	  enqueue_additional d `AAAA;
          addfn (`NS (mapfn Dns_rr.NS.t ~hostname:d.owner.H.node))) l
    | CNAME l -> 
	List.iter (fun d -> 
	  addfn (`CNAME (mapfn Dns_rr.CNAME.t ~cname:d.owner.H.node))) l
    | SOA l -> log_rrset owner `SOA;
	  List.iter (fun (prim,admin,serial,refresh,retry,expire,minttl) ->
            addfn (`SOA (mapfn Dns_rr.SOA.t ~primary_ns:prim.owner.H.node
			   ~admin_mb:admin.owner.H.node ~serial:serial 
			   ~refresh:refresh ~retry:retry
			   ~expiration:expire ~minttl:minttl))) l
    | MB l -> 
	List.iter (fun d -> 
	  enqueue_additional d `A;
	  enqueue_additional d `AAAA;
	  addfn (`MB (mapfn Dns_rr.MB.t ~madname:d.owner.H.node))) l
    | MG l -> 
	List.iter (fun d -> 
	  addfn (`MG (mapfn Dns_rr.MG.t ~mgmname:d.owner.H.node))) l
    | MR l -> 
	List.iter (fun d -> 
	  addfn (`MR (mapfn Dns_rr.MR.t ~newname:d.owner.H.node))) l
    | WKS l -> 
	List.iter (fun (address, protocol, bitmap) -> 
	  addfn (`WKS (mapfn Dns_rr.WKS.t ~address:address
			 ~protocol:protocol ~bitmap:(`Str bitmap.H.node)))) l
    | PTR l -> 
	List.iter (fun d -> 
	  addfn (`PTR (mapfn Dns_rr.PTR.t ~ptrdname:d.owner.H.node))) l
    | HINFO l -> 
	  List.iter (fun (cpu, os) -> 
	    addfn (`HINFO (mapfn Dns_rr.HINFO.t ~cpu:cpu.H.node 
			     ~os:os.H.node))) l
    | MINFO l -> 
	List.iter (fun (rm, em) -> 
	  addfn (`MINFO (mapfn Dns_rr.MINFO.t ~rmailbox:rm.owner.H.node
			   ~emailbox:em.owner.H.node))) l
    | MX l -> 
	List.iter (fun (pref, d) -> 
	  enqueue_additional d `A;
	  enqueue_additional d `AAAA;
	  addfn (`MX (mapfn Dns_rr.MX.t ~preference:pref
			~hostname:d.owner.H.node))) l
    | TXT l ->
	List.iter (fun sl -> (* XXX handle multiple TXT cstrings properly *)
	  let s = String.concat "" (List.map (fun x -> x.H.node) sl) in 
          addfn (`TXT (mapfn Dns_rr.TXT.t ~data:s ~misc:`None))) l
    | RP l -> 
	List.iter (fun (mbox, txt) -> 
	  addfn (`RP (mapfn Dns_rr.RP.t ~mbox_dname:mbox.owner.H.node
			~txt_dname:txt.owner.H.node))) l
    | AFSDB l ->
	List.iter (fun (t, d) -> 
	  enqueue_additional d `A;
	  enqueue_additional d `AAAA;
	  addfn (`AFSDB (mapfn Dns_rr.AFSDB.t ~subtype:t
			   ~hostname:d.owner.H.node))) l
    | X25 l -> log_rrset owner `X25;
	List.iter (fun s -> 
	  addfn (`X25 (mapfn Dns_rr.X25.t ~psdn_address:s.H.node))) l
    | ISDN l -> log_rrset owner `ISDN;
	List.iter (function (* XXX handle multiple cstrings properly *)
	    (addr, None) -> 
	      addfn (`ISDN (mapfn Dns_rr.ISDN.t ~data:(addr.H.node)))
          | (addr, Some sa) -> (* XXX Handle multible charstrings properly *)
	      addfn (`ISDN (mapfn Dns_rr.ISDN.t 
			      ~data:(addr.H.node ^ sa.H.node)))) l
    | RT l -> 
	List.iter (fun (pref, d) -> 
	  enqueue_additional d `A;
	  enqueue_additional d `AAAA;
	  enqueue_additional d `X25;
	  enqueue_additional d `ISDN;
	  addfn (`RT (mapfn Dns_rr.RT.t ~preference:pref
			~intermediate_host:d.owner.H.node))) l
    | AAAA l -> log_rrset owner `AAAA;
	List.iter (fun i -> 
	  addfn (`AAAA (mapfn Dns_rr.AAAA.t ~ip:(`Str i.H.node)))) l 
    | SRV l -> 
        List.iter (fun (pri, weight, port, d) -> 
	  enqueue_additional d `A;
	  enqueue_additional d `AAAA;
	  addfn (`SRV (mapfn Dns_rr.SRV.t ~priority:pri ~weight:weight 
			 ~port:port ~target:d.owner.H.node))) l
    | UNSPEC l -> 
	  List.iter (fun s -> 
	    addfn (`UNSPEC (mapfn Dns_rr.UNSPEC.t ~data:(`Str s.H.node)))) l
    | Unknown (t, l) -> () (* XXX Support unknown-type responses *)
  in
  
  (* Get an RRSet, which may not exist *)
  let add_opt_rrset node rrtype section = 
    if not (in_log node.owner.H.node rrtype)
    then let a = get_rrsets rrtype node.rrsets false in
    List.iter (fun s -> add_rrset node.owner.H.node s.ttl s.rdata section) a 
  in

  (* Get an RRSet, which must exist *)
  let add_req_rrset node rrtype section = 
    if not (in_log node.owner.H.node rrtype)
    then let a = get_rrsets rrtype node.rrsets false in
    if a = [] then raise TrieCorrupt; 
    List.iter (fun s -> add_rrset node.owner.H.node s.ttl s.rdata section) a
  in

  (* Get the SOA RRSet for a negative response *)
  let add_negative_soa_rrset node = 
    (* Don't need to check if it's already there *)
    let a = get_rrsets `SOA node.rrsets false in
    if a = [] then raise TrieCorrupt;
    (* RFC 2308: The TTL of the SOA RRset in a negative response must be set to
       the minimum of its own TTL and the "minimum" field of the SOA itself *)
    List.iter (fun s -> 
      match s.rdata with
	SOA ((_, _, _, _, _, _, ttl) :: _) -> 
	  add_rrset node.owner.H.node (min s.ttl ttl) s.rdata `Authority
      | _ -> raise TrieCorrupt ) a
  in

  (* Fill in the ANSWER section *)
  let rec add_answer_rrsets owner ?(lc = 5) rrsets rrtype  = 
    let add_answer_rrset s = 
      match s with 
	{ rdata = CNAME (d::_) } -> (* Only follow the first CNAME in a set *)
	  if not (lc < 1 || rrtype = `CNAME ) then begin 
            add_answer_rrsets d.owner.H.node ~lc:(lc - 1) d.rrsets rrtype end;
	  add_rrset owner s.ttl s.rdata `Answer;
      | _ -> add_rrset owner s.ttl s.rdata `Answer
    in
    let a = get_rrsets rrtype rrsets true in
    List.iter add_answer_rrset a
  in

  (* Call the trie lookup and assemble the RRs for a response *)
  let main_lookup qname qtype trie = 
    let key = canon2key qname in
    match lookup key trie with
      `Found (sec, node, zonehead) ->	  (* Name has RRs, and we own it. *)
	add_answer_rrsets node.owner.H.node node.rrsets qtype;
	add_opt_rrset zonehead `NS `Authority;
	`NoError
	  
    | `NoError (zonehead) ->	 	  (* Name "exists", but has no RRs. *)
	add_negative_soa_rrset zonehead;
	`NoError

    | `NoErrorNSEC (zonehead, nsec) ->
	add_negative_soa_rrset zonehead;
	(* add_opt_rrset nsec `NSEC `Authority; *)
	`NoError
	  
    | `Delegated (sec, cutpoint) ->	  (* Name is delegated. *)
	add_req_rrset cutpoint `NS `Authority; 
	aa_flag := false; 
	(* DNSSEC child zone keys *)
	`NoError

    | `Wildcard (source, zonehead) ->	  (* Name is matched by a wildcard. *)
	add_answer_rrsets qname source.rrsets qtype; 
	add_opt_rrset zonehead `NS `Authority;
	`NoError

    | `WildcardNSEC (source, zonehead, nsec) -> 
	add_answer_rrsets qname source.rrsets qtype; 
	add_opt_rrset zonehead `NS `Authority;
	(* add_opt_rrset nsec `NSEC `Authority; *)
	`NoError

    | `NXDomain (zonehead) ->		  (* Name doesn't exist. *)
	add_negative_soa_rrset zonehead;
	`NXDomain

    | `NXDomainNSEC (zonehead, nsec1, nsec2) ->
	add_negative_soa_rrset zonehead;
	(* add_opt_rrset nsec1 `NSEC `Authority; *)
	(* add_opt_rrset nsec2 `NSEC `Authority; *)
	`NXDomain
  in
      
  try 
    let rc = main_lookup qname qtype trie in	
    List.iter (fun (o, t) -> add_opt_rrset o t `Additional) !addqueue;
    { rcode = rc; aa = !aa_flag; 
      answer = !ans_rrs; authority = !auth_rrs; additional = !add_rrs }
  with 
    BadDomainName _ -> { rcode = `FormErr; aa = false; 
			 answer = []; authority = []; additional=[] }
  | TrieCorrupt ->  { rcode = `ServFail; aa = false;
		      answer = []; authority = []; additional=[] }
