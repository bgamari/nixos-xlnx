# nixos-xlnx

NixOS and Nix packages for Xilinx ZynqMP SoCs. It's like PetaLinux, but instead of Yocto/OpenEmbedded/BitBake, it uses NixOS/Nixpkgs/Nix. Currently it targets Vivado 2022.2 and Nixpkgs unstable. Zynq 7000 support is planned.

This project isn't considered stable yet. Pin your inputs!

## Limitations

Device-tree and FSBL BSP generation from XSA is highly couple with Vitis HSI, and I haven't figured out a trivial way to generate them with Nix. Currently you have to build FSBL and device-tree with Vitis. I wrote a simple Vitis XSCT script [`vitisgenfw.tcl`](./vitisgenfw.tcl) to make that process a bit easier.

Vivado 2023 introduces system device tree, which is a variation of device tree that can be used to generate FSBL BSP. This project currently only targets Vivado 2022.2 so I haven't tried that.

This project targets 2022.2 only because I use that version in a project. More versions are planned but I don't expect I'll be able to test them on a real board any time soon.

## Build SD card images

After finishing your hardware design in Vivado, choose File > Export > Export Hardware... Save the XSA file. Run [`vitisgenfw.tcl`](./vitisgenfw.tcl) to generate the bitstream, FSBL, PMUFW, and device-tree.

```bash
source /installation/path/to/Vitis/2022.2/settings64.sh
xsct ./vitisgenfw.tcl vivado_exported.xsa ./output/directory/
```

Assume you have Nix flakes enabled, configure NixOS as follows:

```nix
{
  inputs.nixos-xlnx.url = "github:chuangzhu/nixpkgs";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, nixos-xlnx }: {
    nixosConfigurations.zynqmpboard = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-xlnx.nixosModules.sd-image

        ({ pkgs, lib, config, ... }: {
          nixpkgs.hostPlatform = "aarch64-linux";
          hardware.zynq = {
            bitstream = ./output/directory/system.bit;
            fsbl = ./output/directory/fsbl_a53.elf;
            pmufw = ./output/directory/pmufw.elf;
            dtb = ./output/directory/system.dtb;
          };
          hardware.deviceTree.overlays = [
            { name = "system-user"; dtsFile = ./system-user.dts; }
          ];
          users.users.root.initialPassword = "INSECURE CHANGE ME LATER";
          services.openssh = {
            enable = true;
            settings.PermitRootLogin = "yes";
          };
          # ... Other NixOS configurations
        })

      ];
    };
  };
}
```

Vivado only knows your PL/PS configuration *inside the SoC*, thus the device-tree generated by Vitis may not suit your *board* configuration. If you used PetaLinux before, you know that frequently you need to override properties, add/delete nodes in DTSIs in a special directory. In NixOS, we use device-tree overlays for that. Note that overlay DTSs are slightly different with a regular DTS:

```dts
/dts-v1/;
/plugin/;  // Required
/ { compatible = "xlnx,zynqmp"; };  // Required
// ... Your overrides
```

```bash
nix build .#nixosConfigurations.zynqmpboard.config.system.build.sdImage -vL
zstdcat ./result/nixos-sd-image-24.05.20231222.6df37dc-aarch64-linux.img.zst | sudo dd of=/dev/mmcblk0 status=progress
```

## Deploy to running systems

When you make changes to your configuration, you don't have to rebuild and reflash the SD card image. The rootfs (including kernel, device-tree) can be updated using:

```bash
out=$(nix build --no-link --print-out-paths -vL .#nixosConfigurations.zynqmpboard.config.system.build.toplevel)
nix copy --no-check-sigs --to "ssh://root@zynqmpboard.local" "$out"
ssh root@zynqmpboard.local nix-env -p /nix/var/nix/profiles/system --set $out
ssh root@zynqmpboard.local /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

After that, you can update BOOT.BIN using

```bash
ssh zynqmpboard.local xlnx-firmware-update
```

## Known issues

### Applications that requires OpenGL not launching

The Mali GPU built in ZynqMP isn't supported by Mesa yet. You have to use the closed source Mali OpenGL ES drivers:

```nix
hardware.opengl.extraPackages = [ pkgs.libmali-xlnx.x11 ]; # Possible choices: wayland, x11, fbdev, headless
boot.extraModulePackages = [ pkgs.mali-module-xlnx ];
boot.blacklistedKernelModules = [ "lima" ];
boot.initrd.kernelModules = [ "mali" ];
```

### Xorg not launching

For some reason the Xorg modesetting driver doesn't work on ZynqMP DisplayPort subsystem. You have to use either armsoc or fbdev:

```nix
services.xserver.videoDrivers = lib.mkForce [ "armsoc" "fbdev" ];
```

<details>
<summary>
I haven't successfully launched a normal display manager on ZynqMP yet. If you also have issues with display managers, this is a working configuration:
</summary>

```nix
services.xserver.enable = true;
services.xserver.videoDrivers = lib.mkForce [ /*"armsoc"*/ "fbdev" ];
services.xserver.displayManager.sx.enable = true;
services.xserver.windowManager.i3.enable = true;
systemd.services.i3 = {
  wantedBy = [ "multi-user.target" ];
  script = ''
    . /etc/profile
    exec sx i3 -c /etc/i3/config
  '';
  # Sometimes systemd deactivate it instantly even with no error
  # Restart indefinitely
  unitConfig.StartLimitIntervalSec = 0;
  serviceConfig = {
    User = "root";
    Group = "root";
    PAMName = "login";
    WorkingDirectory = "~";
    Restart = "always";
    TTYPath = "/dev/tty1";
    TTYReset = "yes";
    TTYVHangup = "yes";
    TTYVTDisallocate = "yes";
    StandardInput = "tty-force";
    StandardOutput = "journal";
    StandardError = "journal";
  };
};
```
</details>

## Disclaimer

Zynq, ZynqMP, Zynq UltraScale+ MPSoC, Vivado, Vitis, PetaLinux are trademarks of Xilinx, Inc. This project is not endorsed by nor affiliated with Xilinx, Inc.
