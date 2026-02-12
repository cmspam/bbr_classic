{
  description = "bbr_classic: Backport the original BBRv1 to kernels patched with BBRv3 logic";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosModules.default = { config, pkgs, lib, ... }: 
    let
      cfg = config.networking.bbr_classic;
      kernel = config.boot.kernelPackages.kernel;
      isClang = kernel.stdenv.cc.isClang or false;

      tcp-bbr-classic = kernel.stdenv.mkDerivation {
        pname = "tcp-bbr-classic";
        version = "1.0";

        src = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/torvalds/linux/v6.19/net/ipv4/tcp_bbr.c";
          sha256 = "sha256-XkaGklAiUa2iM84knrXJixVYRpAyadBOBQVQDu/S6Z8=";
        };

        nativeBuildInputs = kernel.moduleBuildDependencies;
        unpackPhase = ":";

        buildPhase = ''
          cp $src tcp_bbr_classic.c

          # 1. Rename to avoid namespace collision with built-in bbr module
          sed -i 's/"bbr"/"bbr_classic"/g' tcp_bbr_classic.c
          sed -i 's/struct bbr/struct bbr_classic/g' tcp_bbr_classic.c

          # 2. DYNAMIC FEATURE DETECTION
          # Checks for BBRv3 patches (common in Zen, Liquorix, Xanmod) which remove 'min_tso_segs'.
          TCP_H="${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include/net/tcp.h"
          if ! grep -q "min_tso_segs" "$TCP_H"; then
            echo "BBRv3 API detected in patched kernel headers. Applying compatibility patch..."
            sed -i 's/\.min_tso_segs/\/\/ .min_tso_segs/g' tcp_bbr_classic.c
          else
            echo "Standard API detected. Leaving min_tso_segs intact."
          fi

          # 3. Build Logic
          echo "obj-m += tcp_bbr_classic.o" > Makefile

          # Inherit toolchain flags (Handles Clang/LTO and GCC kernels)
          make_flags=""
          if [ "${if isClang then "1" else "0"}" = "1" ]; then
            make_flags="LLVM=1 CC=clang"
          fi

          make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
            M=$(pwd) \
            $make_flags \
            modules
        '';

        installPhase = ''
          mkdir -p $out/lib/modules/${kernel.modDirVersion}/extra
          cp tcp_bbr_classic.ko $out/lib/modules/${kernel.modDirVersion}/extra/
        '';
      };
    in {
      options.networking.bbr_classic = {
        enable = lib.mkEnableOption "BBRv1 (Classic) TCP congestion control module";
        setAsDefault = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to set bbr_classic as default and configure FQ pacing.";
        };
      };

      config = lib.mkIf cfg.enable {
        boot.extraModulePackages = [ tcp-bbr-classic ];
        boot.kernelModules = [ "tcp_bbr_classic" ];
        
        boot.kernel.sysctl = lib.mkIf cfg.setAsDefault {
          "net.core.default_qdisc" = "fq";
          "net.ipv4.tcp_congestion_control" = "bbr_classic";
          "net.ipv4.tcp_window_scaling" = 1;
        };
      };
    };
  };
}
