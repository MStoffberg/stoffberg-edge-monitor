# SSH and firewall rescue

If SSH is blocked after first install, use the HP t520 local console or boot the Alpine USB and mount the installed disk.

## From local console

```sh
rc-service nftables stop || true
rc-update del nftables boot || true
passwd keiki
rc-service sshd restart
ip addr
```

Then SSH from your PC:

```sh
ssh keiki@<edge-ip>
```

## Enable firewall only after SSH works

```sh
cd /root/stoffberg-edge-monitor
git pull
ENABLE_FIREWALL=true sh scripts/setup-firewall-nftables.sh
```

## From Alpine USB rescue

Boot the same Alpine USB, find the installed disk, mount it, then disable nftables in the installed system. Device names may differ.

```sh
lsblk
mount /dev/sda3 /mnt
# If /boot is separate, mount it too if needed.
chroot /mnt /bin/ash
rc-update del nftables boot || true
passwd keiki
exit
reboot
```

If `chroot` is not available in the live environment, edit the OpenRC runlevel symlink manually:

```sh
rm -f /mnt/etc/runlevels/boot/nftables /mnt/etc/runlevels/default/nftables
```
