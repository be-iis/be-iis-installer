# set_mac.sh -- Random MAC Assignment for T1L Interfaces

## Description

This script assigns a **random locally administered MAC address** to all
available BE-IIS T1L interfaces.

It checks for the presence of:

-   beiis-t1l1
-   beiis-t1l2
-   beiis-t1l3

If one or more interfaces exist, a unique MAC address is generated and
applied.

------------------------------------------------------------------------

## Why this is required

Some drivers or early setups may assign identical default MAC addresses
(e.g. 02:00:00:00:00:XX) to multiple interfaces.

This leads to: - ARP conflicts - unstable communication - packet loss -
incorrect switch behavior

Each interface must have a unique MAC address for correct Layer 2
operation.

------------------------------------------------------------------------

## Behavior

-   Detects existing T1L interfaces automatically
-   Generates a random MAC address per interface
-   Uses locally administered MACs (02:xx:xx:xx:xx:xx)
-   Applies MAC safely (interface down → set → up)

------------------------------------------------------------------------

## Usage

``` bash
chmod +x set_mac.sh
./set_mac.sh
```

------------------------------------------------------------------------

## Verification

``` bash
ip link show beiis-t1l1
```

Expected:

    link/ether 02:xx:xx:xx:xx:xx

------------------------------------------------------------------------

## Notes

-   Requires sudo privileges (used internally)
-   Safe to run multiple times (new MAC each run)
-   Does not affect other interfaces (e.g. LAN, Wi-Fi)

------------------------------------------------------------------------

## BE-IIS Context

This script ensures stable operation in: - point-to-point T1L links -
multi-interface setups - bridged environments

It is recommended to run this script before executing network tests.
