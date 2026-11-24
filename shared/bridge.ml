(* Browser functions that Yuka does not give. The client entry (client/main.ml) sets
   them; on the server they keep these defaults and are never called. *)

let read_cookie : (string -> string) ref = ref (fun _ -> "")

(* Seconds since the epoch. *)
let now : (unit -> int) ref = ref (fun () -> 0)

(* Fires a window event with this name, for islands that listen with
   Yuka.Browser.on_window. *)
let emit : (string -> unit) ref = ref (fun _ -> ())

(* Scrolls the element with this id by one width, left (-1) or right (1). *)
let scroll_row : (string -> int -> unit) ref = ref (fun _ _ -> ())

(* Calls the function once the top 60px of the element with this id are in view;
   gives the function that stops watching. *)
let on_visible : (string -> (unit -> unit) -> unit -> unit) ref = ref (fun _ _ () -> ())

(* Calls the function after this many milliseconds; gives the function that cancels. *)
let after : (int -> (unit -> unit) -> unit -> unit) ref = ref (fun _ _ () -> ())

(* Shares the current URL with this title (navigator.share), or copies it. *)
let share : (string -> unit) ref = ref (fun _ -> ())

(* Enters or leaves fullscreen for the element with this id. *)
let toggle_fullscreen : (string -> unit) ref = ref (fun _ -> ())
let is_fullscreen : (unit -> bool) ref = ref (fun () -> false)

(* Listens on document until the function it gives is called. *)
let on_document : (string -> (unit -> unit) -> unit -> unit) ref = ref (fun _ _ () -> ())

(* Drives the YouTube embed (enablejsapi=1) in the iframe with this id as a silent
   background: loops it, drops captions, and calls the function with true while
   the video plays and false while YouTube may draw anything over it (loading,
   buffering, paused, the first second and the end). Gives the function that
   stops. *)
let background_video : (string -> (bool -> unit) -> unit -> unit) ref = ref (fun _ _ () -> ())

(* Whether a window message event says that the video of an embedded player ended. *)
let is_ended_message : (Yuka.Event.t -> bool) ref = ref (fun _ -> false)

(* Yuka.Router encodes and decodes URLs byte by byte, which is right on the server,
   where a string holds UTF-8, but not in the browser, where it holds UTF-16 code units.
   [to_utf8] gives the UTF-8 bytes of a browser string as a string with one byte per
   unit, and [of_utf8] reads it back. On the server both are the identity. *)
let to_utf8 : (string -> string) ref = ref Fun.id
let of_utf8 : (string -> string) ref = ref Fun.id
