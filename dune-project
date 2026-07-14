(lang dune 3.0)

(generate_opam_files true)

(maintainers "JSIP Organizers")

(authors "JSIP Organizers")

(homepage "https://github.com/jane-street-immersion-program/jsip-racing-game/")

(bug_reports
 "https://github.com/jane-street-immersion-program/jsip-racing-game/issues")

(license MIT)

(package
 (name jsip-racing-game)
 (synopsis "A racing game built in OCaml")
 (depends
  (ocaml
   (>= 5.2.0))
  dune
  ocaml-lsp-server
  ocamlformat
  (odoc :with-doc)
  graphics
  core
  core_unix
  core_bench
  ppx_jane
  async
  async_log
  async_rpc_kernel
  (bin_prot :with-test)
  (expect_test_helpers_core :with-test)
  (expect_test_helpers_async :with-test)))
