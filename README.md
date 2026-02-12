# bbr_classic for NixOS

Maintain the aggressive throughput of **BBRv1** on Linux kernels that have been patched with **BBRv3** logic.

## The Context
While mainline Linux kernels currently use BBRv1, many high-performance kernels and patchsets—such as **Zen**, **Liquorix**, and **Xanmod**—often integrate **BBRv3** patches.

BBRv3 is designed to be "fairer" to other TCP streams and more resistant to bufferbloat. However, in real-world environments—especially on high-speed, long-haul, or slightly lossy links—this increased politeness can result in a significant drop in sustained throughput.

**bbr_classic** allows you to stay on these optimized kernels while forcing the original, more aggressive BBRv1 behavior for your network traffic.

## Performance Results
The following results were observed on a 1Gbps link with ~5% packet loss on a kernel patched with BBRv3:
- **Default BBR (v3 Patched)**: ~578 Mbits/sec
- **BBR_Classic (v1)**: **~839 Mbits/sec**



## Features
- **Smart Toolchain Detection**: Automatically inherits the kernel's build environment, supporting both Clang/LTO and standard GCC builds.
- **Dynamic API Adaptation**: At build-time, the module inspects the kernel headers. If it detects BBRv3-style API changes (such as the removal of `min_tso_segs`), it automatically patches the source to maintain compatibility.
- **Nix-Native**: Built during system evaluation; no broken states or manual DKMS management.

---

## Usage

### 1. Add to your Flake inputs
In your `flake.nix`, add this repository as an input:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  
  # Add the bbr_classic input
  bbr_classic.url = "github:cmspam/bbr_classic";
};
```

### 2. Import the Module
Include the module in your nixosSystem configuration. You should also pass the input through specialArgs so it is available to your modules:
```nix
outputs = { self, nixpkgs, bbr_classic, ... }: {
  nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    
    specialArgs = { inherit bbr_classic; }; 
    
    modules = [
      ./configuration.nix
      bbr_classic.nixosModules.default
    ];
  };
};
```

### 3. Enable in configuration.nix
Once the module is imported, you can enable it and set it as the system default:
```nix
{ config, pkgs, ... }:

{
  networking.bbr_classic = {
    enable = true;
    
    # Automatically sets the following sysctls:
    # net.ipv4.tcp_congestion_control = "bbr_classic"
    # net.core.default_qdisc = "fq"
    setAsDefault = true;
  };
}
```
## Manual Verification

After applying your configuration and switching (`nixos-rebuild switch`), you can verify that the module is correctly loaded and active.

### Check if the kernel module is loaded
Run the following command to ensure the module is currently recognized by the kernel:
```bash
lsmod | grep bbr_classic
```

### Check the active congestion control
To verify that `bbr_classic` is the algorithm currently managing your TCP traffic:
```bash
sysctl net.ipv4.tcp_congestion_control
```
*Expected output:* `net.ipv4.tcp_congestion_control = bbr_classic`

---

## Setting it manually with sysctl

If you have set `networking.bbr_classic.enable = true` but chose **not** to use `setAsDefault = true`, the module will be available in your kernel, but not active by default. You can toggle it manually at runtime for testing.

> [!IMPORTANT]
> BBR requires the **FQ (Fair Queuing)** scheduler to function correctly. Ensure your queuing discipline is set to `fq` before switching.

### 1. Set the Queuing Discipline
```bash
sudo sysctl -w net.core.default_qdisc=fq
```

### 2. Switch to BBR Classic
```bash
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr_classic
```

### 3. Verify the switch
Run the following to see the current runtime settings:
```bash
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc
```



---

## Testing Performance
To see the difference in real-time, you can use `iperf3`. If the server you are connecting to supports it, you can even specify the congestion control per-test:

**Test with default (usually BBRv3 on patched kernels):**
```bash
iperf3 -c <server_address> -C bbr
```

**Test with BBR Classic (this module):**
```bash
iperf3 -c <server_address> -C bbr_classic
```


## Technical Implementation
This flake downloads the official tcp_bbr.c source from the Linux 6.19 tree. During the buildPhase, it:

1. Renames internal symbols to bbr_classic to avoid namespace collisions with the kernel's built-in bbr module.

2. Checks for the existence of min_tso_segs in your specific kernel headers.

3. Comments out the field if BBRv3-style changes are detected to allow successful compilation on patched kernels.

## License

GPLv2 (inherited from the Linux Kernel).
