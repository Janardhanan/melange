(*
 * Copyright (c) 2005 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 * $Id: mplc.ml,v 1.18 2006/02/17 17:28:40 avsm Exp $
 *)

open Printf
open Mpl_utils

let default_log_level = Logger.Verbose


let _ =
    let module MS = Mpl_syntaxtree in
    let module MT = Mpl_typechk in
    let log_level = ref default_log_level in
    let files = ref [] in
    let want_sc = ref false in
    let parse = [
        "-q", Arg.Unit (fun () -> log_level := Logger.Quiet),
        "Quiet mode";
        "-v", Arg.Unit (fun () -> log_level := Logger.Verbose),
        "Verbose mode";
        "-s", Arg.Unit (fun () -> want_sc := true),
        "Want Statecalls";
    ] in
    let usagestr = "Usage: mplc <options> input-file" in    
    Arg.parse parse (fun x -> files := x :: !files) usagestr;
    (* Need to have at least one input file *)
    if List.length !files < 1 then begin Arg.usage parse usagestr; exit 1; end;
    Logger.set_log_level !log_level;
    Logger.log (sprintf "Input files: %s" (String.concat " " !files));
    (* Open file and start compilation process *)
    List.iter (fun file ->
        Logger.log (sprintf "Processing %s" file);
        let fin = open_in file in
        let lexbuf = Lexing.from_channel fin in
        Mpl_location.start_parse file;
        let result = try Mpl_parser.main Mpl_lexer.token lexbuf 
        with MS.Syntax_error l -> begin
            Logger.log_quiet (sprintf "Syntax error%s near token '%s'"
                (Mpl_location.string_of_location l) (Lexing.lexeme lexbuf));
            exit 1;
        end in
        let ts = MT.typecheck result in
          let ts = List.map (Mpl_cfg.make_env !want_sc) ts in
        let e = Printer.init_printer
            ~msg:(Some "(* This file was autogenerated by MPL *)") stdout in
        List.iter2 (Mpl_ocaml.marshal e) result.MS.pdefs ts;
        ()
    ) !files
