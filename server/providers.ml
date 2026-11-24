(* The stream providers. Add or remove one here: the watch page shows them all. *)

open App_shared

type provider = {
  id : string;
  name : string;
  (* [None] when the provider does not have this kind of title. *)
  url : kind:Model.kind -> tmdb:int -> imdb:string option -> season:int -> episode:int -> string option;
}

let all =
  [
    {
      id = "vidsrc";
      name = "VidSrc";
      url =
        (fun ~kind ~tmdb ~imdb:_ ~season ~episode ->
          match kind with
          | Movie -> Some (Printf.sprintf "https://vidsrc.me/embed/movie?tmdb=%d" tmdb)
          | Tv -> Some (Printf.sprintf "https://vidsrc.me/embed/tv?tmdb=%d&season=%d&episode=%d" tmdb season episode));
    };
    {
      id = "superembed";
      name = "SuperEmbed";
      url =
        (fun ~kind ~tmdb ~imdb:_ ~season ~episode ->
          match kind with
          | Movie -> Some (Printf.sprintf "https://multiembed.mov/?video_id=%d&tmdb=1" tmdb)
          | Tv -> Some (Printf.sprintf "https://multiembed.mov/?video_id=%d&tmdb=1&s=%d&e=%d" tmdb season episode));
    };
    {
      id = "2embed";
      name = "2Embed";
      url =
        (fun ~kind ~tmdb ~imdb:_ ~season ~episode ->
          match kind with
          | Movie -> Some (Printf.sprintf "https://www.2embed.cc/embed/%d" tmdb)
          | Tv -> Some (Printf.sprintf "https://www.2embed.cc/embedtv/%d&s=%d&e=%d" tmdb season episode));
    };
    {
      id = "vidsrc_embed";
      name = "VidSrc Pro";
      url =
        (fun ~kind ~tmdb ~imdb ~season ~episode ->
          let base = "https://vidsrc-embed.ru/embed" in
          let id = match imdb with Some imdb -> "imdb=" ^ imdb | None -> Printf.sprintf "tmdb=%d" tmdb in
          match kind with
          | Movie -> Some (Printf.sprintf "%s/movie?%s" base id)
          | Tv -> Some (Printf.sprintf "%s/tv?%s&season=%d&episode=%d" base id season episode));
    };
    {
      id = "godrive";
      name = "GoDrive";
      url =
        (fun ~kind ~tmdb ~imdb ~season ~episode ->
          let base = "https://godriveplayer.com/player.php" in
          match (kind, imdb) with
          | Movie, Some imdb -> Some (Printf.sprintf "%s?imdb=%s" base imdb)
          | Movie, None -> Some (Printf.sprintf "%s?tmdb=%d" base tmdb)
          | Tv, _ -> Some (Printf.sprintf "%s?type=series&tmdb=%d&season=%d&episode=%d" base tmdb season episode));
    };
  ]

let default = "vidsrc"

let for_title ~kind ~tmdb ~imdb ~season ~episode : Model.provider list =
  List.filter_map
    (fun provider ->
      Option.map
        (fun url -> { Model.id = provider.id; name = provider.name; url })
        (provider.url ~kind ~tmdb ~imdb ~season ~episode))
    all
