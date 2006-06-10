(*
   dnsquery.mli -- map DNS query-response mechanism onto trie database
   Copyright (c) 2005-2006 Tim Deegan <tjd@phlegethon.org>      
*)


type query_answer = {
  rcode : Dns.Dns.rcode_t;
  aa : bool;
  answer : (Mpl_stdlib.env -> Dns.Dns.Answers.o) list;
  authority : (Mpl_stdlib.env -> Dns.Dns.Authority.o) list;
  additional : (Mpl_stdlib.env -> Dns.Dns.Additional.o) list;
}

val answer_query : string list -> 
  [> `A
   | `AAAA
   | `AFSDB
   | `ANY
   | `CNAME
   | `HINFO
   | `ISDN
   | `MAILB
   | `MB
   | `MG
   | `MINFO
   | `MR
   | `MX
   | `NS
   | `PTR
   | `RP
   | `RT
   | `SOA
   | `SRV
   | `TXT
   | `UNSPEC
   | `Unknown of int
   | `WKS
   | `X25 ] -> 
  Dnstrie.dnstrie -> query_answer
