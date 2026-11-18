{
  description = "senselesssoccer (internal codename): Odin + raylib dev shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # nixpkgs' Odin patches vendor:raylib to link the system libraylib
      # (raylib 6.2 on GLFW 3.4, which runs natively on Wayland) instead of
      # the bundled static library, which it strips.
      libs = with pkgs; [
        raylib
        libGL
        wayland
        libxkbcommon
      ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          odin
          ols
        ];
        buildInputs = libs;

        # /run/opengl-driver/lib holds the Mesa (radeonsi) driver on NixOS.
        shellHook = ''
          export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath libs}:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        '';
      };
    };
}
