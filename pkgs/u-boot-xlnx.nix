{ lib
, fetchFromGitHub
, buildUBoot
, stdenv
, platform ? "zynqmp"
}:

buildUBoot {
  version = "2025.01-xilinx-v2025.1";

  src = fetchFromGitHub {
    owner = "Xilinx";
    repo = "u-boot-xlnx";
    rev = "xlnx_rebase_v2025.01_2025.1_update1";
    hash = "sha256-maFS/4seulVVKTDn15tnx6VEOBtrAxia6woFHYeeOmI=";
  };

  defconfig = "xilinx_${platform}_virt_defconfig";
  extraMeta.platforms = if platform == "zynq" then [ "armv7l-linux" ] else [ "aarch64-linux" ];

  filesToInstall = [ "u-boot.elf" ];
}
