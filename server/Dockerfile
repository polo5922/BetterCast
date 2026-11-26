# Build from the repository root:  docker build -f server/Dockerfile .
FROM dart:stable AS build
WORKDIR /src
COPY packages/bettercast_core/pubspec.* packages/bettercast_core/
COPY server/pubspec.* server/
WORKDIR /src/server
RUN dart pub get
WORKDIR /src
COPY packages/bettercast_core packages/bettercast_core
COPY server server
WORKDIR /src/server
RUN mkdir -p /out && dart pub get --offline && dart compile exe bin/server.dart -o /out/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server
EXPOSE 8080
ENTRYPOINT ["/app/server"]
