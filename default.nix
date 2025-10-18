let nix-haskell = import ./deps/nix-haskell {};
    project = import ./project.nix;
in nix-haskell project
