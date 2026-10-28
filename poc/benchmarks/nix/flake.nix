{
  # Banc B (ADR 0000 §3) : sample-app construite par Nix.
  # nixpkgs est épinglé sur une archive immuable de releases.nixos.org ;
  # flake.lock en fige le narHash.
  description = "Banc B : sample-app (Go + interface npm + image OCI) construite par Nix";

  inputs.nixpkgs.url = "https://releases.nixos.org/nixos/25.11/nixos-25.11.12484.b6018f87da91/nixexprs.tar.xz";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      version = "1.0.0";
      src = ../../sample-app;

      web = pkgs.buildNpmPackage {
        pname = "sample-app-web";
        inherit version;
        src = "${src}/web";
        npmDepsHash = "sha256-3+4R8TNuuQqVjFaA8O3UoUCFZQBGqbSgwlxzAOj/VP4=";
        installPhase = ''
          runHook preInstall
          cp -r dist $out
          runHook postInstall
        '';
      };

      app = pkgs.buildGoModule {
        pname = "sample-app";
        inherit version src;
        vendorHash = "sha256-yORLX/6dJqy7/IWKTqoEdBYTK++cvNsqm0SkPfrfPNM=";
        env.CGO_ENABLED = "0";
        ldflags = [ "-s" "-w" "-X main.Version=${version}" ];
        preBuild = ''
          rm -rf web/dist
          cp -r ${web} web/dist
        '';
      };

      image = pkgs.dockerTools.buildLayeredImage {
        name = "sample-app";
        tag = version;
        config.Cmd = [ "${app}/bin/sample-app" ];
      };
    in
    {
      packages.${system} = { inherit web app image; default = app; };
    };
}
