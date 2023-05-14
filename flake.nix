# Todo: ask mantas if he wants aiken pinned for contract hash or not
{
  inputs = {
    aiken.url = "github:aiken-lang/aiken";
    nixpkgs.follows = "aiken/nixpkgs";
  };
  outputs = {nixpkgs, aiken, ...}: let
    defaultSystems = ["x86_64-linux"];
    perSystem = nixpkgs.lib.genAttrs defaultSystems;
  in {
    devShell = perSystem (system: aiken.devShells.${system}.aiken);
  };
}