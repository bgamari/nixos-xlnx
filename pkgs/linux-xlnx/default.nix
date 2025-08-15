{ lib
, buildLinux
, fetchFromGitHub
, stdenv
, defconfig ? "xilinx_defconfig"
, kernelPatches ? [ ]
, version ? "6.12.10-xilinx-v2025.1"
, ...
} @ args:

buildLinux (args // {
  inherit version;
  modDirVersion = if defconfig == "xilinx_zynq_defconfig" then "6.12.10-xilinx" else "6.12.10";

  src = fetchFromGitHub {
    owner = "Xilinx";
    repo = "linux-xlnx";
    rev = "bf1529197724f8f20f83f756a76db0c009e7dac0";
    hash = "sha256-fzbqMQ/V46L4JtaFfU1taiVG1iDtGMypH9d9mEsWnBs=";
  };

  structuredExtraConfig = with lib.kernel; {
    DEBUG_INFO_BTF = lib.mkForce no;
    CRYPTO_DEV_XILINX_ECDSA = no;  # Error: modpost: "ecdsasignature_decoder" undefined!
  } // lib.optionalAttrs (defconfig == "xilinx_zynq_defconfig") {
    DRM_XLNX_BRIDGE = yes;  # DRM_XLNX uses xlnx_bridge_helper_init
    USB_XHCI_PLATFORM = no;  # USB_XHCI_PLATFORM uses dwc3_host_wakeup_capable
    USB_XHCI_HCD = no;
    USB_DWC3 = no;
    USB_CDNS_SUPPORT = no;
  } // lib.optionalAttrs stdenv.is32bit {
    # Disable HDCP on Zynq7 to avoid hard-to-fix compilation errors
    # These are only relevant to XC7Z045 and XC7Z100 anyway
    # For other Zynq7 devices, use https://digilent.com/reference/programmable-logic/zybo-z7/demos/hdmi instead
    # If you are using XC7Z045 or XC7Z100 and do want to use these features, please open an issue
    VIDEO_XILINX_HDMI21RXSS = no;  # FIXME: div64
    VIDEO_XILINX_DPRXSS = no;
    VIDEO_XILINX_HDCP1X_RX = no;
    VIDEO_XILINX_HDCP2X_RX = no;
    DRM_XLNX_HDCP = no;
    DRM_XLNX_DPTX = no;
    DRM_XLNX_HDMITX = no;
    DRM_XLNX_MIXER = no;
  };

  inherit kernelPatches;

  extraMeta.platforms = [ "aarch64-linux" "armv7l-linux" ];
} // (args.argsOverride or { }))
