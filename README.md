# nixos-xlnx

NixOS and Nix packages for Xilinx Zynq 7000 SoCs and Zynq UltraScale+ MPSoCs. It's like PetaLinux, but instead of Yocto/OpenEmbedded/BitBake, it uses NixOS/Nixpkgs/Nix. Currently it targets Vivado 2022.2 and Nixpkgs unstable.

This project isn't considered stable yet. Options may change anytime without noticing. Pin your inputs!

## Limitations

Device-tree and FSBL BSP generation from XSA is highly coupled with Vitis HSI, and I haven't figured out a trivial way to generate them with Nix. Currently you have to build FSBL and device-tree with Vitis. I wrote a simple Vitis XSCT script [`vitisgenfw.tcl`](./vitisgenfw.tcl) to make that process a bit easier.

Vivado 2023 introduces system device tree, which is a variation of device tree that can be used to generate FSBL BSP. This project currently only targets Vivado 2022.2 so I haven't tried that.

This project targets 2022.2 only because I use that version in a project. More versions are planned but I don't expect I'll be able to test them on a real board any time soon.

## Build SD card images

After finishing your hardware design in Vivado, choose File > Export > Export Hardware... Save the XSA file. Run [`vitisgenfw.tcl`](./vitisgenfw.tcl) to generate the bitstream, FSBL, PMUFW, and device-tree.

```bash
git clone https://github.com/Xilinx/device-tree-xlnx ~/.cache/device-tree-xlnx -b xilinx_v2022.2 --depth 1
source /installation/path/to/Vitis/2022.2/settings64.sh
xsct ./vitisgenfw.tcl vivado_exported.xsa ./output/directory/ -platform zynqmp  # Or "zynq" for Zynq 7000
```

Assuming you have Nix flakes enabled, configure NixOS as follows:

```nix
{
  inputs.nixos-xlnx.url = "github:chuangzhu/nixpkgs";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, nixos-xlnx }: {
    nixosConfigurations.zynqmpboard = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-xlnx.nixosModules.sd-image

        ({ pkgs, lib, config, ... }: {
          nixpkgs.hostPlatform = "aarch64-linux";  # Or "armv7l-linux" for Zynq 7000
          hardware.zynq = {
            platform = "zynqmp";  # Or "zynq" for Zynq 7000
            bitstream = ./output/directory/system.bit;
            fsbl = ./output/directory/fsbl_a53.elf;
            pmufw = ./output/directory/pmufw.elf;  # Remove for Zynq 7000
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

```c
/dts-v1/;
/plugin/;  // Required
/ { compatible = "xlnx,zynqmp"; };  // Required, or "xlnx,zynq-7000"
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
ssh root@zynqmpboard.local xlnx-firmware-update
```

## Notes on cross compilation

* For ZynqMP, Nixpkgs provides tons of prebuilt packages for aarch64-linux native/emulated builds, so you only need to build a small amount of packages.
  - For aarch64-linux, native/emulated builds have a higher [support Tier in Nixpkgs](https://github.com/NixOS/rfcs/blob/master/rfcs/0046-platform-support-tiers.md) than cross builds.
  - Even if you don't have a AArch64 builder, the build time for emulated builds is still acceptable given the small amount of packages you need to build.
* For Zynq 7000, Nixpkgs doesn't provide a binary cache for armv7l-linux.
  - For native/emulated builds, you'll need to bootstrap from stage 0. For emulated builds, this is *really* time consuming.
  - For armv7l-linux, cross builds and native/emulated have the same level of support Tier.

### Emulated builds
- For NixOS, add this to the *builder's* configuration.nix:
  ```nix
  boot.binfmt.emulatedSystems = [ "aarch64-linux" "armv7l-linux" ];
  ```
- For other systemd-based Linux distros, you need to install `qemu-user-static` (something like that), edit `/etc/binfmt.d/arm.conf` as the follows:
  ```
  :aarch64-linux:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\x00\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:PF
  :armv7l-linux:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\x00\xff\xfe\xff\xff\xff:/usr/bin/qemu-armhf-static:PF
  ```
  Restart `systemd-binfmt.service`. Add `extra-platforms = armv7l-linux` to your `/etc/nix/nix.conf`. Restart `nix-daemon.service`.

### Cross builds
Set `nixpkgs.hostPlatform` in the *target's* configuration to your *builder's* platform, for example:
```nix
nixpkgs.hostPlatform = "x86_64-linux";
```

### Native builds
Many AArch64 CPUs also supports AArch32, which provides backward compatibility with ARMv7. Such "aarch64-linux" systems can be used to build armv7l-linux natively.
  - Check whether your `lscpu` says `CPU op-mode(s): 32-bit, 64-bit`.
  - Add `extra-platforms = armv7l-linux` to your `/etc/nix/nix.conf`. Restart `nix-daemon.service`.

## Known issues

### Applications that requires OpenGL not launching

The Mali GPU built in ZynqMP isn't supported by Mesa yet. You have to use the closed source Mali OpenGL ES drivers:

```nix
hardware.opengl.extraPackages = [ pkgs.libmali-xlnx.x11 ]; # Possible choices: wayland, x11, fbdev, headless
boot.extraModulePackages = [ config.boot.kernelPackages.mali-module-xlnx ];
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

MIT license only applies to the files in this repository, not to the packages built with it. Licenses for patches in this repository are otherwise specified.
