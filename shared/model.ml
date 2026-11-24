(* Types that the server and the browser share: route params and island props. *)

type kind = Movie | Tv [@@deriving codec]

let kind_slug = function Movie -> "movie" | Tv -> "tv"

let kind_param =
  Yuka.Router.Param.make
    ~decode:(function "movie" -> Some Movie | "tv" -> Some Tv | _ -> None)
    ~encode:kind_slug

(* One entry of a select that loads a page: its label, the page and whether it is the
   current one. *)
type choice = { label : string; url : string; selected : bool } [@@deriving codec]

type button_style = Card | Hero | Toolbar [@@deriving codec]

(* What a history entry knows about playback: the detail page was seen, the movie
   played, or the episode (season, episode) of a show played. *)
type play = Viewed | Played | Episode of int * int [@@deriving codec]

type provider = { id : string; name : string; url : string } [@@deriving codec]
type episode = { number : int; name : string } [@@deriving codec]
