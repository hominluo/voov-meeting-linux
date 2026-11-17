{
  description = "Unofficial native VooV Meeting client for Linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        voov-meeting = pkgs.callPackage ./packaging/nix/voov-meeting.nix { };
        default = voov-meeting;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.system}.voov-meeting}/bin/voov-meeting";
        };
      });
    };
}
