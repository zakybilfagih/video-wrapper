open App_shared

let routes =
  Router.make ~not_found:Pages.not_found ~error:Pages.error
    [
      Router.group ~path:"/watch" ~loader:Loaders.me
        [
          Router.route Watch ~path:"/:kind<Model.kind>/:id<int>" ~page:Pages.watch ~loader:Loaders.media
            ~search:{ season = default int 1; episode = default int 1 };
        ];
      Router.route Random ~path:"/random" ~page:Pages.random ~loader:Loaders.random ~prefetch:`Off;
      Router.group ~path:"/" ~layout:Pages.shell
      [
        Router.group ~path:"/search" ~layout:Pages.search_layout
          [
            Router.group ~path:"/" ~loader:Loaders.me
              [ Router.route Search ~path:"/" ~page:Pages.search ~search:{ q = optional string; tab = default string "all" } ];
          ];
        Router.group ~path:"/" ~loader:Loaders.me
          [
            Router.route Home ~path:"/" ~page:Pages.home;
            Router.route Decide ~path:"/decide" ~page:Pages.decide ?overlay:Pages.decide_dialog
              ~search:{ mood = optional string; time = optional string };
            Router.route Browse ~path:"/browse" ~page:Pages.browse
              ~search:
                {
                  genre = optional int;
                  sort = default string "popularity.desc";
                  rating = default int 0;
                  runtime = default string "any";
                  year = default string "any";
                  view = default string "grid";
                  pages = default int 1;
                };
            Router.route Tv_shows ~path:"/tv-shows" ~page:Pages.tv_shows
              ~search:
                {
                  genre = optional int;
                  sort = default string "popularity.desc";
                  rating = default int 0;
                  pages = default int 1;
                };
            Router.route Watchlist ~path:"/watchlist" ~page:Pages.watchlist;
            Router.route History ~path:"/history" ~page:Pages.history;
            Router.route Stats ~path:"/stats" ~page:Pages.stats;
            Router.route Movie ~path:"/movie/:id<int>" ~page:Pages.movie ~loader:Loaders.movie;
            Router.route Trailer ~path:"/movie/:id<int>/trailer" ~page:Pages.trailer ?overlay:Pages.trailer_dialog
              ~loader:Loaders.movie;
            Router.route Show ~path:"/tv/:id<int>" ~page:Pages.show ~loader:Loaders.show
              ~search:{ season = optional int };
            Router.route Person ~path:"/person/:id<int>" ~page:Pages.person ~loader:Loaders.person
              ~search:{ tab = default string "all" };
            Router.route Collection ~path:"/collection/:id<int>" ~page:Pages.collection ~loader:Loaders.collection;
          ];
      ];
  ]
