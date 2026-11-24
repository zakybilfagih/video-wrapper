# Runs the server built by `make dist`, from inside dist/ (see `make deploy`).
FROM debian:sid-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libgmp10 libssl3t64 libev4t64 zlib1g libzstd1 \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY . .
CMD ["sh", "-c", "exec ./main.exe --interface 0.0.0.0 --port ${PORT:-8080} --build build"]
