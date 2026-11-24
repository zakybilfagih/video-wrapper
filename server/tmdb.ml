(* The TMDB API: requests with a cache, and the records the pages show. *)

open App_shared
open Lwt.Syntax

exception Missing_key
exception Status of int

(* TMDB_API_KEY from the environment, else from a .env file in the working directory. *)
let key =
  lazy
    (let from_file () =
       match In_channel.with_open_text ".env" In_channel.input_lines with
       | exception Sys_error _ -> None
       | lines ->
           List.find_map
             (fun line ->
               match String.index_opt line '=' with
               | Some i when String.trim (String.sub line 0 i) = "TMDB_API_KEY" ->
                   let value = String.trim (String.sub line (i + 1) (String.length line - i - 1)) in
                   let unquoted =
                     if String.length value >= 2 && value.[0] = '"' then String.sub value 1 (String.length value - 2)
                     else value
                   in
                   Some unquoted
               | _ -> None)
             lines
     in
     match Sys.getenv_opt "TMDB_API_KEY" with
     | Some key when key <> "" -> Some key
     | _ -> ( match from_file () with Some key when key <> "" && key <> "YOUR_TMDB_API_KEY" -> Some key | _ -> None))

let configured () = Option.is_some (Lazy.force key)

(* At most [limit] requests to TMDB at a time, so a page that loads many titles stays
   under the rate limit. *)
let limit = 8
let running = ref 0
let waiting = Lwt_condition.create ()

let rec throttled f =
  if !running >= limit then
    let* () = Lwt_condition.wait waiting in
    throttled f
  else begin
    incr running;
    Lwt.finalize f (fun () ->
        decr running;
        Lwt_condition.signal waiting ();
        Lwt.return_unit)
  end

let fetch url =
  throttled (fun () ->
      let* result =
        Http_lwt_client.request url (fun _ buffer chunk -> Buffer.add_string buffer chunk; Lwt.return buffer) (Buffer.create 4096)
      in
      match result with
      | Error (`Msg message) -> Lwt.fail_with ("TMDB: " ^ message)
      | Ok (response, body) -> (
          match Http_lwt_client.Status.to_code response.status with
          | 200 -> (
              match Yuka.Json.of_string (Buffer.contents body) with
              | Ok json -> Lwt.return json
              | Error message -> Lwt.fail_with ("TMDB: " ^ message))
          | code -> Lwt.fail (Status code)))

(* Answers stay ten minutes. Two requests for one URL share one fetch. *)
let ttl = 600.
let cache : (string, float * Yuka.Json.t Lwt.t) Hashtbl.t = Hashtbl.create 256

let get path params =
  match Lazy.force key with
  | None -> Lwt.fail Missing_key
  | Some api_key -> (
      let query =
        String.concat "&"
          (List.map (fun (name, value) -> name ^ "=" ^ Dream.to_percent_encoded value) (("api_key", api_key) :: params))
      in
      let url = "https://api.themoviedb.org/3" ^ path ^ "?" ^ query in
      let now = Unix.gettimeofday () in
      match Hashtbl.find_opt cache url with
      | Some (time, answer) when now -. time < ttl -> answer
      | _ ->
          if Hashtbl.length cache > 2000 then
            Hashtbl.filter_map_inplace (fun _ ((time, _) as entry) -> if now -. time < ttl then Some entry else None) cache;
          let answer = fetch url in
          Hashtbl.replace cache url (now, answer);
          Lwt.on_failure answer (fun _ -> Hashtbl.remove cache url);
          answer)

(* Reading the JSON of TMDB, where any field may be missing or null. *)
module J = struct
  let field name = function `Assoc fields -> Option.value (List.assoc_opt name fields) ~default:`Null | _ -> `Null
  let string json name = match field name json with `String s -> s | _ -> ""
  let string_opt json name = match field name json with `String "" -> None | `String s -> Some s | _ -> None
  let int json name = match field name json with `Int i -> i | `Float f -> Float.to_int f | _ -> 0
  let float json name = match field name json with `Float f -> f | `Int i -> Float.of_int i | _ -> 0.
  let list f json name = match field name json with `List items -> List.map f items | _ -> []
  let first_some a b = match a with Some _ -> a | None -> b
end

let image ?(size = "w500") path =
  match path with
  | Some path -> "https://image.tmdb.org/t/p/" ^ size ^ path
  | None -> "https://placehold.co/500x750/1A1C22/666666?text=No+Image"

type card = {
  kind : Model.kind;
  id : int;
  title : string;
  poster : string option;
  backdrop : string option;
  rating : float;
  date : string;
  overview : string;
  genre_ids : int list;
}

let year card = if String.length card.date >= 4 then Some (String.sub card.date 0 4) else None

let card_of ~kind json =
  {
    kind;
    id = J.int json "id";
    title = (match J.string_opt json "title" with Some title -> title | None -> J.string json "name");
    poster = J.string_opt json "poster_path";
    backdrop = J.string_opt json "backdrop_path";
    rating = J.float json "vote_average";
    date = (match J.string_opt json "release_date" with Some date -> date | None -> J.string json "first_air_date");
    overview = J.string json "overview";
    genre_ids =
      (match J.field "genre_ids" json with
      | `List _ -> J.list (function `Int i -> i | _ -> 0) json "genre_ids"
      | _ -> J.list (fun genre -> J.int genre "id") json "genres");
  }

type 'a page = { results : 'a list; page : int; total_pages : int }

let page_of f json = { results = J.list f json "results"; page = J.int json "page"; total_pages = J.int json "total_pages" }
let cards ~kind json = page_of (card_of ~kind) json

type credit = { person_id : int; name : string; role : string; profile : string option }

let credit_of ~role json =
  { person_id = J.int json "id"; name = J.string json "name"; role = J.string json role; profile = J.string_opt json "profile_path" }

(* The YouTube key of the first trailer. *)
let trailer json =
  List.find_map
    (fun video ->
      if J.string video "type" = "Trailer" && J.string video "site" = "YouTube" then J.string_opt video "key" else None)
    (match J.field "videos" json with `Null -> [] | videos -> J.list Fun.id videos "results")

let youtube key = "https://www.youtube.com/embed/" ^ key

let youtube_background key =
  youtube key
  ^ "?autoplay=1&mute=1&controls=0&disablekb=1&fs=0&playsinline=1&cc_load_policy=0&iv_load_policy=3&rel=0&enablejsapi=1"

let similar ~kind json = match J.field "similar" json with `Null -> [] | similar -> (cards ~kind similar).results
let cast json = List.map (credit_of ~role:"character") (J.list Fun.id (J.field "credits" json) "cast")
let genres json = J.list (fun genre -> (J.int genre "id", J.string genre "name")) json "genres"

let imdb json =
  J.first_some (J.string_opt json "imdb_id") (J.string_opt (J.field "external_ids" json) "imdb_id")

type collection_ref = { collection_id : int; collection_name : string; collection_backdrop : string option }

type movie = {
  movie : card;
  runtime : int;
  movie_genres : (int * string) list;
  budget : int;
  revenue : int;
  languages : string list;
  movie_imdb : string option;
  movie_cast : credit list;
  directors : credit list;
  movie_trailer : string option;
  movie_similar : card list;
  belongs_to : collection_ref option;
}

let append = [ ("append_to_response", "videos,credits,similar,recommendations,external_ids") ]

let movie id =
  let+ json = get ("/movie/" ^ Int.to_string id) append in
  {
    movie = card_of ~kind:Movie json;
    runtime = J.int json "runtime";
    movie_genres = genres json;
    budget = J.int json "budget";
    revenue = J.int json "revenue";
    languages = J.list (fun language -> J.string language "english_name") json "spoken_languages";
    movie_imdb = imdb json;
    movie_cast = cast json;
    directors =
      List.filter
        (fun credit -> credit.role = "Director")
        (List.map (credit_of ~role:"job") (J.list Fun.id (J.field "credits" json) "crew"));
    movie_trailer = trailer json;
    movie_similar = similar ~kind:Movie json;
    belongs_to =
      (match J.field "belongs_to_collection" json with
      | `Assoc _ as collection ->
          Some
            {
              collection_id = J.int collection "id";
              collection_name = J.string collection "name";
              collection_backdrop = J.string_opt collection "backdrop_path";
            }
      | _ -> None);
  }

type season = { season_number : int; season_name : string; episode_count : int }

type show = {
  show : card;
  seasons : season list;
  number_of_seasons : int;
  number_of_episodes : int;
  status : string;
  creators : credit list;
  show_genres : (int * string) list;
  episode_runtime : int;
  show_imdb : string option;
  show_cast : credit list;
  show_trailer : string option;
  show_similar : card list;
}

let show id =
  let+ json = get ("/tv/" ^ Int.to_string id) append in
  {
    show = card_of ~kind:Tv json;
    seasons =
      List.filter
        (fun season -> season.season_number > 0)
        (J.list
           (fun season ->
             {
               season_number = J.int season "season_number";
               season_name = J.string season "name";
               episode_count = J.int season "episode_count";
             })
           json "seasons");
    number_of_seasons = J.int json "number_of_seasons";
    number_of_episodes = J.int json "number_of_episodes";
    status = J.string json "status";
    creators = List.map (credit_of ~role:"job") (J.list Fun.id json "created_by");
    show_genres = genres json;
    episode_runtime = (match J.list (function `Int i -> i | _ -> 0) json "episode_run_time" with m :: _ -> m | [] -> 0);
    show_imdb = imdb json;
    show_cast = cast json;
    show_trailer = trailer json;
    show_similar = similar ~kind:Tv json;
  }

type episode = {
  episode_number : int;
  episode_name : string;
  episode_overview : string;
  still : string option;
  episode_rating : float;
  episode_minutes : int;
}

let season id number =
  let+ json = get (Printf.sprintf "/tv/%d/season/%d" id number) [] in
  J.list
    (fun episode ->
      {
        episode_number = J.int episode "episode_number";
        episode_name = J.string episode "name";
        episode_overview = J.string episode "overview";
        still = J.string_opt episode "still_path";
        episode_rating = J.float episode "vote_average";
        episode_minutes = J.int episode "runtime";
      })
    json "episodes"

(* A movie or a show, as the watch page, the watchlist and the stats need it. *)
type media = {
  card : card;
  minutes : int;
  genre_names : (int * string) list;
  imdb_id : string option;
  media_cast : credit list;
  media_similar : card list;
  media_seasons : season list;
}

let media (kind : Model.kind) id =
  match kind with
  | Movie ->
      let+ m = movie id in
      {
        card = m.movie;
        minutes = m.runtime;
        genre_names = m.movie_genres;
        imdb_id = m.movie_imdb;
        media_cast = m.movie_cast;
        media_similar = m.movie_similar;
        media_seasons = [];
      }
  | Tv ->
      let+ s = show id in
      {
        card = s.show;
        minutes = s.episode_runtime;
        genre_names = s.show_genres;
        imdb_id = s.show_imdb;
        media_cast = s.show_cast;
        media_similar = s.show_similar;
        media_seasons = s.seasons;
      }

(* [None] when TMDB does not give the title, so a list of saved titles leaves it out. *)
let media_opt kind id = Lwt.catch (fun () -> Lwt.map Option.some (media kind id)) (fun _ -> Lwt.return_none)

let trending (kind : Model.kind) = Lwt.map (cards ~kind) (get ("/trending/" ^ Model.kind_slug kind ^ "/day") [])
let movie_list name = Lwt.map (cards ~kind:Movie) (get ("/movie/" ^ name) [])

let popular_page page =
  Lwt.map (cards ~kind:Movie) (get "/movie/popular" [ ("page", Int.to_string page) ])

let discover (kind : Model.kind) params = Lwt.map (cards ~kind) (get ("/discover/" ^ Model.kind_slug kind) params)

let genre_list (kind : Model.kind) =
  Lwt.map
    (fun json -> J.list (fun genre -> (J.int genre "id", J.string genre "name")) json "genres")
    (get ("/genre/" ^ Model.kind_slug kind ^ "/list") [])

type person_result = {
  person_result_id : int;
  person_result_name : string;
  person_result_profile : string option;
  department : string;
  known_for : string list;
}

type result = Title of card | Person_result of person_result

let search query =
  let+ json = get "/search/multi" [ ("query", query) ] in
  List.filter_map
    (fun item ->
      match J.string item "media_type" with
      | "movie" -> Some (Title (card_of ~kind:Movie item))
      | "tv" -> Some (Title (card_of ~kind:Tv item))
      | "person" ->
          Some
            (Person_result
               {
                 person_result_id = J.int item "id";
                 person_result_name = J.string item "name";
                 person_result_profile = J.string_opt item "profile_path";
                 department = J.string item "known_for_department";
                 known_for =
                   List.filteri
                     (fun index _ -> index < 2)
                     (J.list (fun known -> (card_of ~kind:Movie known).title) item "known_for");
               })
      | _ -> None)
    (J.list Fun.id json "results")

type filmography = { credit : card; as_ : string }

type person = {
  person_id : int;
  person_name : string;
  known_for_department : string;
  photo : string option;
  biography : string;
  birthday : string option;
  place_of_birth : string option;
  filmography : filmography list;
}

let person id =
  let+ json = get ("/person/" ^ Int.to_string id) [ ("append_to_response", "combined_credits") ] in
  let credits = J.field "combined_credits" json in
  let credit item =
    let kind : Model.kind = if J.string item "media_type" = "tv" then Tv else Movie in
    let role = match J.string_opt item "character" with Some role -> role | None -> J.string item "job" in
    { credit = card_of ~kind item; as_ = role }
  in
  let all =
    List.stable_sort
      (fun a b -> compare b.credit.date a.credit.date)
      (J.list credit credits "cast" @ J.list credit credits "crew")
  in
  let seen = Hashtbl.create 64 in
  {
    person_id = J.int json "id";
    person_name = J.string json "name";
    known_for_department = J.string json "known_for_department";
    photo = J.string_opt json "profile_path";
    biography = J.string json "biography";
    birthday = J.string_opt json "birthday";
    place_of_birth = J.string_opt json "place_of_birth";
    filmography =
      List.filter
        (fun entry ->
          let key = (entry.credit.kind, entry.credit.id) in
          if Hashtbl.mem seen key then false else (Hashtbl.add seen key (); true))
        all;
  }

type collection = {
  collection : collection_ref;
  collection_overview : string;
  parts : card list;
}

let collection id =
  let+ json = get ("/collection/" ^ Int.to_string id) [] in
  let parts = J.list (card_of ~kind:Movie) json "parts" in
  let date card = if card.date = "" then "9999-12-31" else card.date in
  {
    collection =
      {
        collection_id = J.int json "id";
        collection_name = J.string json "name";
        collection_backdrop = J.string_opt json "backdrop_path";
      };
    collection_overview = J.string json "overview";
    parts = List.stable_sort (fun a b -> compare (date a) (date b)) parts;
  }
