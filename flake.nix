{
  description = "lanesnap: end-to-end test against a real Hyprland in a NixOS VM";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      # nix build .#checks.x86_64-linux.vm -L   (needs KVM)
      checks.${system}.vm = pkgs.testers.runNixOSTest (import ./nix/vm-test.nix { src = self; });
    };
}
