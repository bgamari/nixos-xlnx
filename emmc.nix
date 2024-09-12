{ config, pkgs, ... }:

{
  imports = [
    ./nixos.nix
  ];

  config = {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "xlnx-firmware-update";
        text = ''
          systemctl start boot-firmware.mount
          cp ${config.hardware.zynq.boot-bin} /boot/firmware/BOOT.BIN
          sync /boot/firmware/BOOT.BIN
        '';
      })
    ];
  };
}
