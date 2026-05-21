# setup-pi-ssh-key.sh

Create an SSH key on a Raspberry Pi and prepare SSH key login to the host machine.

The script is intended to be executed on the Raspberry Pi while connected via SSH.

# Purpose

This script:

- creates an SSH key on the Raspberry Pi
- prints the public key
- detects the SSH client IP address
- shows the ssh-copy-id command for the host machine
- helps prepare passwordless SSH login from the Pi to the host

# Usage

Make the script executable:

    chmod +x setup-pi-ssh-key.sh

Run:

    ./setup-pi-ssh-key.sh

Optional custom key name:

    ./setup-pi-ssh-key.sh id_ed25519_be_iis_pi

# What the Script Creates

Default key path:

    ~/.ssh/id_ed25519_be_iis_pi

Public key:

    ~/.ssh/id_ed25519_be_iis_pi.pub

# Host Detection

The script uses:

    $SSH_CONNECTION

to detect the IP address of the machine that opened the SSH session.

Example:

    192.168.1.100 53422 192.168.1.50 22

The first address is the SSH client host.

# Copy Key to Host

If the host machine accepts SSH connections, run the shown command from the Pi:

    ssh-copy-id -i ~/.ssh/id_ed25519_be_iis_pi.pub USER@HOST_IP

Example:

    ssh-copy-id -i ~/.ssh/id_ed25519_be_iis_pi.pub philipp@192.168.1.100

# Test Login

Test SSH login from the Pi to the host:

    ssh -i ~/.ssh/id_ed25519_be_iis_pi USER@HOST_IP

Example:

    ssh -i ~/.ssh/id_ed25519_be_iis_pi philipp@192.168.1.100

# Notes

- The script must run on the Raspberry Pi
- The Pi must be accessed via SSH for automatic host IP detection
- The host machine must run an SSH server
- Automatic key installation only works if the host accepts SSH connections
- If SSH to the host is not available, copy the printed public key manually to:

    ~/.ssh/authorized_keys

on the host machine.

# Security

The private key stays on the Raspberry Pi.

Do not copy or publish this file:

    ~/.ssh/id_ed25519_be_iis_pi

Only the .pub file is meant to be copied.
