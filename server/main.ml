let read file = In_channel.with_open_bin file In_channel.input_all

let stop message =
  prerr_endline ("cinepulse: " ^ message);
  exit 1

let packages dir =
  match Sys.readdir (Filename.concat dir "node_modules") with
  | names ->
      Array.sort compare names;
      Array.to_list names
  | exception Sys_error _ -> []

let dev = Sys.getenv_opt "YUKA_DEV" = Some "1"

(* Outside dev, a /static URL carries a digest of the directory, so a new deploy gives new URLs
   and cache_static lets browsers keep the files for good. *)
let static path = if dev then path else path ^ "?v=" ^ String.sub (Yuka.Server.tree_digest "static") 0 12

let cache_static handler request =
  let versioned = String.starts_with ~prefix:"/static/" (Dream.target request) && Dream.query request "v" <> None in
  Lwt.map
    (fun response ->
      if versioned && Dream.status response = `OK then
        Dream.set_header response "cache-control" "public, max-age=31536000, immutable";
      response)
    (handler request)

let head =
  String.concat ""
    [
      {|<meta name="viewport" content="width=device-width, initial-scale=1">|};
      {|<meta name="description" content="Discover and stream the latest movies and TV shows with CinePulse's premium cinematic experience.">|};
      {|<meta name="keywords" content="CinePulse, movie streaming, tv shows, discovery, cinematic UI, tmdb, watchlist, analytics, yuka, ocaml">|};
      {|<link rel="icon" type="image/svg+xml" href="|} ^ static "/static/favicon.svg" ^ {|">|};
      {|<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>|};
      {|<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Outfit:wght@400;500;600;700;800;900&display=swap">|};
      {|<link rel="preconnect" href="https://image.tmdb.org">|};
    ]

let () =
  Random.self_init ();
  let port = ref (match Option.bind (Sys.getenv_opt "PORT") int_of_string_opt with Some port -> port | None -> 8080) in
  let interface = ref "localhost" in
  let build = ref "_build/default" in
  Arg.parse
    [
      ("--port", Arg.Set_int port, "Port to listen on (default: $PORT, or 8080)");
      ("--interface", Arg.Set_string interface, "Network interface to listen on (default localhost)");
      ("--build", Arg.Set_string build, "The dune build directory (default _build/default)");
    ]
    (fun _ -> ())
    "main.exe [--port N] [--interface ADDRESS]";
  let dir = Filename.concat !build "client/out" in
  let manifest = read (Filename.concat !build "client/yuka_islands.json") in
  let metafile = Filename.concat !build "client/meta.json" in
  let assets =
    match
      (* `make bundle` writes the esbuild bundle and its metafile; without them, serve the module tree. *)
      if Sys.file_exists metafile then
        Yuka.Server.bundle ~dir:(Filename.concat dir "client") ~entry:"bundle/main.js" ~manifest
          ~metafile:(read metafile)
      else Yuka.Server.modules ~dir ~entry:"client/main.js" ~manifest ~packages:(packages dir)
          ~digest:(Yuka.Server.tree_digest dir)
    with
    | Ok assets -> assets
    | Error message -> stop message
  in
  if not (Sys.file_exists "static/app.css") then stop "static/app.css is missing: run `npm run css` (or `make css`) first";
  if not (App_server.Tmdb.configured ()) then
    prerr_endline "cinepulse: TMDB_API_KEY is not set (environment or .env): pages will show no titles";
  let config =
    Yuka.Server.config ~assets ~head ~styles:[ static "/static/app.css" ]
      ~public:[ ("/static", "static") ]
      ~dev
      ()
  in
  Dream.run ~interface:!interface ~port:!port
  @@ Dream.logger
  @@ cache_static
  @@ Yuka_dream.handler config App_server.Yuka_routes.app
