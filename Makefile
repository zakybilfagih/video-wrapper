PORT ?= 8080
YUKA ?= $(HOME)/Documents/yuka
OCAML_VERSION ?= 5.5.2

OPAM = opam exec --switch=$(CURDIR) --
DUNE = $(OPAM) dune

.PHONY: help
help: ## Print this help message
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

.PHONY: init
init: ## Create the local switch, pin yuka to $(YUKA), install the opam and npm packages
	opam switch create . ocaml-base-compiler.$(OCAML_VERSION) --no-install -y
	opam pin add --switch=$(CURDIR) -y --no-action dune.3.25.0 "git+https://github.com/davesnx/dune.git#1e6f26d4d6615e0d2770977a00d2f654fcc4dba3"
	opam pin add --switch=$(CURDIR) -y --no-action melange.7.0.1-55 "git+https://github.com/davesnx/melange.git#16162e70268bf63cab1e12fd14f49f8d06983cf6"
	OPAMEDITOR="sh $(CURDIR)/scripts/patch-yuka-opam.sh --public" opam pin add --switch=$(CURDIR) -y --no-action --edit yuka.dev $(YUKA)
	OPAMEDITOR="sh $(CURDIR)/scripts/patch-yuka-opam.sh" opam pin add --switch=$(CURDIR) -y --no-action --edit yuka-dream.dev $(YUKA)
	opam install --switch=$(CURDIR) -y yuka yuka-dream dream lwt http-lwt-client ocaml-lsp-server ocamlmerlin-mlx ocamlformat-mlx
	npm install

.PHONY: css
css: ## Build static/app.css with Tailwind
	npm run -s css

.PHONY: build
build: css ## Build the server, the client and the stylesheet
	$(DUNE) build

.PHONY: serve
serve: build ## Serve on PORT
	./_build/default/server/main.exe --port $(PORT)

.PHONY: dev
dev: css ## Rebuild, restart and reload on change (PORT)
	npm run -s css:watch & \
	$(DUNE) build ./server/main.exe && \
	$(OPAM) yuka dev --build 'dune build --watch' --assets _build/default/client/out --assets static \
	  -- ./_build/default/server/main.exe --port $(PORT)

.PHONY: bundle
bundle: build ## Bundle the client with esbuild, served instead of the module tree (a build deletes it)
	cd _build/default/client/out/client && rm -rf bundle && $(CURDIR)/node_modules/.bin/esbuild main.js \
	  --bundle --minify --format=esm --splitting --outdir=bundle --metafile=../../meta.json \
	  --define:__YUKA_DEV__=false --log-level=warning

.PHONY: dist
dist: bundle ## Stage the server, the client bundle, the stylesheet and the Dockerfile in dist/
	rm -rf dist && mkdir -p dist/build/client/out/client
	cp _build/default/server/main.exe Dockerfile dist/
	cp -r _build/default/client/out/client/bundle dist/build/client/out/client/
	cp _build/default/client/yuka_islands.json _build/default/client/meta.json dist/build/client/
	cp -r static dist/
	chmod -R u+w dist

.PHONY: deploy
deploy: dist ## Deploy dist/ to Railway
	cd dist && railway up --ci

.PHONY: clean
clean: ## Remove the build
	$(DUNE) clean
	rm -f static/app.css
	rm -rf dist
