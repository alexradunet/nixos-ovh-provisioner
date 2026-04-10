{
  description = "NixOS OVH VPS provisioner";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko }: {
    nixosConfigurations.ovh-vps-base = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./presets/ovh-vps-base.nix
        ./presets/ovh-single-disk.nix
        {
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGUUyhPt6Tsu+opLgmvLDVpTK+uz0ICpAIVhjTN3kGZ1 alex@yoga-laptop"
          ];
        }
      ];
    };
  };
}
