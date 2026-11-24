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

let head =
  String.concat ""
    [
      {|<meta name="viewport" content="width=device-width, initial-scale=1">|};
      {|<meta name="description" content="Discover and stream the latest movies and TV shows with CinePulse's premium cinematic experience.">|};
      {|<meta name="keywords" content="CinePulse, movie streaming, tv shows, discovery, cinematic UI, tmdb, watchlist, analytics, yuka, ocaml">|};
      {|<link rel="icon" type="image/svg+xml" href="/static/favicon.svg">|};
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
  let assets =
    match
      Yuka.Server.modules ~dir ~entry:"client/main.js"
        ~manifest:(read (Filename.concat !build "client/yuka_islands.json"))
        ~packages:(packages dir) ~digest:(Yuka.Server.tree_digest dir)
    with
    | Ok assets -> assets
    | Error message -> stop message
  in
  if not (Sys.file_exists "static/app.css") then stop "static/app.css is missing: run `npm run css` (or `make css`) first";
  if not (App_server.Tmdb.configured ()) then
    prerr_endline "cinepulse: TMDB_API_KEY is not set (environment or .env): pages will show no titles";
  let config =
    Yuka.Server.config ~assets ~head ~styles:[ "/static/app.css" ]
      ~public:[ ("/static", "static") ]
      ~dev:(Sys.getenv_opt "YUKA_DEV" = Some "1")
      ()
  in
  Dream.run ~interface:!interface ~port:!port
  @@ Dream.logger
  @@ Yuka_dream.handler config App_server.Yuka_routes.app
