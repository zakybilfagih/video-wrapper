(* What CinePulse keeps for a visitor, in cookies of their browser: the watchlist,
   the watch history with playback progress, recent searches, the stream provider
   and the auto-play choice. The browser writes them; the server reads them to
   render the pages. Items and entries use only [A-Za-z0-9._], which cookies keep
   as written. *)

open Model

type item = { kind : kind; id : int }

let item_key { kind; id } = (match kind with Movie -> "m" | Tv -> "t") ^ Int.to_string id

let item_of_key key =
  if String.length key < 2 then None
  else
    match (key.[0], int_of_string_opt (String.sub key 1 (String.length key - 1))) with
    | 'm', Some id -> Some { kind = Movie; id }
    | 't', Some id -> Some { kind = Tv; id }
    | _ -> None

let split separator text = if text = "" then [] else String.split_on_char separator text
let take n list = List.filteri (fun index _ -> index < n) list
let year = 365 * 24 * 60 * 60

(* In the browser only. *)
let read name = !Bridge.read_cookie name
let write name value = ignore (Yuka.Browser.set_cookie ~max_age:year name value)

module Watchlist = struct
  let cookie = "cp_watchlist"
  let limit = 200
  let parse text = List.filter_map item_of_key (split '_' text)
  let print items = String.concat "_" (List.map item_key items)
  let mem item items = List.mem item items
  let changed = "cp:watchlist"

  (* Adds the item at the front, or removes it; gives whether it is now saved. *)
  let toggle item =
    let items = parse (read cookie) in
    let saved = not (mem item items) in
    let items = if saved then take limit (item :: items) else List.filter (( <> ) item) items in
    write cookie (print items);
    !Bridge.emit changed;
    saved

  let count () = List.length (parse (read cookie))
end

module History = struct
  type entry = { item : item; time : int; play : play }

  let cookie = "cp_history"
  let limit = 50

  let entry_of_string text =
    let fields = split '.' text in
    match fields with
    | key :: time :: rest -> (
        match (item_of_key key, int_of_string_opt time) with
        | Some item, Some time -> (
            match rest with
            | [] -> Some { item; time; play = Viewed }
            | [ "w" ] -> Some { item; time; play = Played }
            | [ season; episode ] -> (
                match (int_of_string_opt season, int_of_string_opt episode) with
                | Some season, Some episode -> Some { item; time; play = Episode (season, episode) }
                | _ -> None)
            | _ -> None)
        | _ -> None)
    | _ -> None

  let entry_to_string { item; time; play } =
    String.concat "."
      (item_key item :: Int.to_string time
      ::
      (match play with
      | Viewed -> []
      | Played -> [ "w" ]
      | Episode (season, episode) -> [ Int.to_string season; Int.to_string episode ]))

  let parse text = List.filter_map entry_of_string (split '_' text)
  let print entries = String.concat "_" (List.map entry_to_string entries)

  (* Puts the item at the front. A view keeps the progress the item already had. *)
  let add ~time item play entries =
    let old = List.find_opt (fun entry -> entry.item = item) entries in
    let play = match (play, old) with Viewed, Some old -> old.play | _ -> play in
    take limit ({ item; time; play } :: List.filter (fun entry -> entry.item <> item) entries)

  let record item play = write cookie (print (add ~time:(!Bridge.now ()) item play (parse (read cookie))))
  let clear () = write cookie ""
end

module Searches = struct
  let cookie = "cp_searches"
  let limit = 8
  let parse text = List.filter (fun query -> query <> "") (split '\n' text)

  let add query queries =
    let query = String.trim query in
    if String.length query <= 2 then queries
    else
      let same other = String.lowercase_ascii other = String.lowercase_ascii query in
      take limit (query :: List.filter (fun other -> not (same other)) queries)

  let save queries = write cookie (String.concat "\n" queries)
  let remember query = save (add query (parse (read cookie)))
  let remove query = save (List.filter (( <> ) query) (parse (read cookie)))
end

module Player = struct
  let provider = "cp_provider"
  let autoplay = "cp_autoplay"
end
