# Build ethtool on the target

## Install required packages

```bash
sudo apt update
sudo apt install -y autoconf automake libtool pkg-config bison flex make gcc g++ git wget
```

## Go to the ethtool build directory

```bash
cd ~/be-iis-installer/tools/ethtool
```

## Build ethtool locally on the target

```bash
make
```

This step:
- downloads `libmnl`
- clones the `ethtool` sources
- builds `libmnl` into a local prefix
- runs `autogen.sh`
- configures and builds `ethtool`

## Install ethtool into the system

```bash
sudo make install
```

## Verify the installation

```bash
ethtool --version
which ethtool
```

## Typical error

If you see:

```bash
./autogen.sh: 8: aclocal: not found
```

install the missing autotools packages:

```bash
sudo apt install -y autoconf automake libtool pkg-config
```

## Notes

- `make` builds only locally.
- `sudo make install` installs the binary into `/usr/sbin`.
- A plain `make install` without `sudo` will fail with permission errors.
