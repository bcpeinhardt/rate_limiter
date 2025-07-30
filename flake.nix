{
  description = "rate_limiter";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.gleam
            pkgs.erlang
            pkgs.rebar3
          ];
          shellHook = ''
            export PS1="(nix-dev) $PS1"
          '';
        };
      });
}
