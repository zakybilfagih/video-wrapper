open App_shared

let read_cookie : string -> string =
  [%mel.raw
    {|function (name) {
  var parts = document.cookie ? document.cookie.split("; ") : [];
  for (var i = 0; i < parts.length; i++) {
    var eq = parts[i].indexOf("=");
    if (parts[i].slice(0, eq) === name) {
      try { return decodeURIComponent(parts[i].slice(eq + 1)) } catch (error) { return "" }
    }
  }
  return ""
}|}]

let now : unit -> int = [%mel.raw {|function () { return Math.floor(Date.now() / 1000) }|}]
let emit : string -> unit = [%mel.raw {|function (name) { window.dispatchEvent(new Event(name)) }|}]

let scroll_row : string -> int -> unit =
  [%mel.raw
    {|function (id, direction) {
  var row = document.getElementById(id);
  if (row) row.scrollBy({ left: direction * row.clientWidth, behavior: "smooth" });
}|}]

let on_visible : string -> (unit -> unit) -> unit -> unit =
  [%mel.raw
    {|function (id, callback) {
  var element = document.getElementById(id);
  if (!element || !("IntersectionObserver" in window)) return function () {};
  var observer = new IntersectionObserver(function (entries) {
    if (entries.some(function (entry) { return entry.isIntersecting })) { observer.disconnect(); callback() }
  }, { rootMargin: "400px" });
  observer.observe(element);
  return function () { observer.disconnect() };
}|}]

let after : int -> (unit -> unit) -> unit -> unit =
  [%mel.raw
    {|function (ms, callback) {
  var timer = setTimeout(function () { callback() }, ms);
  return function () { clearTimeout(timer) };
}|}]

let share : string -> unit =
  [%mel.raw
    {|function (title) {
  var url = window.location.href;
  if (navigator.share) {
    navigator.share({ title: title, text: "Check out " + title + " on CinePulse!", url: url }).catch(function () {});
  } else if (navigator.clipboard) {
    navigator.clipboard.writeText(url).then(function () { alert("Link copied to clipboard!") });
  }
}|}]

let toggle_fullscreen : string -> unit =
  [%mel.raw
    {|function (id) {
  var element = document.getElementById(id);
  if (!element) return;
  if (!(document.fullscreenElement || document.webkitFullscreenElement)) {
    if (element.requestFullscreen) element.requestFullscreen();
    else if (element.webkitRequestFullscreen) element.webkitRequestFullscreen();
  } else {
    if (document.exitFullscreen) document.exitFullscreen();
    else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
  }
}|}]

let is_fullscreen : unit -> bool =
  [%mel.raw {|function () { return !!(document.fullscreenElement || document.webkitFullscreenElement) }|}]

let on_document : string -> (unit -> unit) -> unit -> unit =
  [%mel.raw
    {|function (name, callback) {
  var listener = function () { callback() };
  document.addEventListener(name, listener);
  return function () { document.removeEventListener(name, listener) };
}|}]

let is_ended_message : Yuka.Event.t -> bool =
  [%mel.raw
    {|function (event) {
  var data = event.data;
  if (typeof data === "string") {
    if (data === "ended" || data === "video_ended") return true;
    try { data = JSON.parse(data) } catch (error) { return false }
  }
  return data === "ended" || data === "video_ended" || !!(data && (data.event === "ended" || data.type === "video_ended"));
}|}]

let background_video : string -> (bool -> unit) -> unit -> unit =
  [%mel.raw
    {|function (id, onPlaying) {
  var frame = document.getElementById(id);
  if (!frame) return function () {};
  var ready = false, captionsOff = false, state = -1, time = 0, duration = 0, playing = false;
  function post(message) { if (frame.contentWindow) frame.contentWindow.postMessage(JSON.stringify(message), "*") }
  function command(func, args) { post({ event: "command", func: func, args: args || [] }) }
  function listen() { post({ event: "listening", id: id, channel: "widget" }) }
  /* Works only once the captions module has loaded, which YouTube announces with
     apiInfoDelivery; cc_load_policy=0 does not stop captions the viewer turned on. */
  function hideCaptions() { command("unloadModule", ["captions"]); command("setOption", ["captions", "track", {}]) }
  function onMessage(event) {
    if (event.source !== frame.contentWindow) return;
    var data;
    try { data = typeof event.data === "string" ? JSON.parse(event.data) : event.data } catch (error) { return }
    if (!data) return;
    var info = data.info;
    ready = true;
    if (data.event === "onStateChange" && typeof info === "number") state = info;
    if (info && typeof info === "object") {
      if (typeof info.playerState === "number") state = info.playerState;
      if (typeof info.currentTime === "number") time = info.currentTime;
      if (typeof info.duration === "number") duration = info.duration;
    }
    if (data.event === "apiInfoDelivery" && info && info.captions) hideCaptions();
    if (state === 1 && !captionsOff) { captionsOff = true; hideCaptions() }
    /* Loop by hand before the end screen, instead of loop=1, whose playlist shows
       previous and next buttons. */
    if (state === 0 || (duration > 0 && time >= duration - 1)) { time = 0; command("seekTo", [0, true]); command("playVideo") }
    var now = state === 1 && time >= 0 && (duration === 0 || time < duration);
    if (now !== playing) { playing = now; onPlaying(now) }
  }
  window.addEventListener("message", onMessage);
  frame.addEventListener("load", listen);
  listen();
  var timer = setInterval(function () { if (ready) clearInterval(timer); else listen() }, 250);
  return function () {
    clearInterval(timer);
    window.removeEventListener("message", onMessage);
    frame.removeEventListener("load", listen);
  };
}|}]

let to_utf8 : string -> string = [%mel.raw {|function (text) { return unescape(encodeURIComponent(text)) }|}]

let of_utf8 : string -> string =
  [%mel.raw {|function (bytes) { try { return decodeURIComponent(escape(bytes)) } catch (error) { return bytes } }|}]

let () =
  Bridge.to_utf8 := to_utf8;
  Bridge.of_utf8 := of_utf8;
  Bridge.read_cookie := read_cookie;
  Bridge.now := now;
  Bridge.emit := emit;
  Bridge.scroll_row := scroll_row;
  Bridge.on_visible := on_visible;
  Bridge.after := after;
  Bridge.share := share;
  Bridge.toggle_fullscreen := toggle_fullscreen;
  Bridge.is_fullscreen := is_fullscreen;
  Bridge.on_document := on_document;
  Bridge.is_ended_message := is_ended_message;
  Bridge.background_video := background_video;
  Yuka.render ~islands ()
