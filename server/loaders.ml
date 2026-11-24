open App_shared

(* What the cookies of the visitor say: see Saved. *)
type me = {
  watchlist : Saved.item list;
  history : Saved.History.entry list;
  searches : string list;
  provider : string;
  autoplay : bool;
}

let cookie req name =
  match Yuka.Server.Request.cookie req name with Some value -> Dream.from_percent_encoded value | None -> ""

let me req =
  Yuka.Async.return
    (Ok
       {
         watchlist = Saved.Watchlist.parse (cookie req Saved.Watchlist.cookie);
         history = Saved.History.parse (cookie req Saved.History.cookie);
         searches = Saved.Searches.parse (cookie req Saved.Searches.cookie);
         provider = (match cookie req Saved.Player.provider with "" -> Providers.default | id -> id);
         autoplay = cookie req Saved.Player.autoplay = "1";
       })

(* A title that TMDB does not have is the not-found page. *)
let found load =
  Yuka_dream.to_async
    (Lwt.catch
       (fun () -> Lwt.map Result.ok (load ()))
       (function Tmdb.Status 404 -> Lwt.return (Error Yuka.Server.Not_found) | exn -> Lwt.fail exn))

let movie (_ : Yuka.Server.request) ~id = found (fun () -> Tmdb.movie id)
let show (_ : Yuka.Server.request) ~id = found (fun () -> Tmdb.show id)
let person (_ : Yuka.Server.request) ~id = found (fun () -> Tmdb.person id)
let collection (_ : Yuka.Server.request) ~id = found (fun () -> Tmdb.collection id)
let media (_ : Yuka.Server.request) ~kind ~id = found (fun () -> Tmdb.media kind id)

(* Quick Pick: a random movie of the first five pages of popular movies. *)
let random (_ : Yuka.Server.request) =
  Yuka_dream.to_async
    (Lwt.map
       (fun (page : Tmdb.card Tmdb.page) ->
         let location =
           match page.results with
           | [] -> Routes.home ()
           | cards -> Routes.movie ~id:(List.nth cards (Random.int (List.length cards))).id ()
         in
         Error (Yuka.Server.Redirect { location; kind = `Temporary }))
       (Tmdb.popular_page (1 + Random.int 5)))
