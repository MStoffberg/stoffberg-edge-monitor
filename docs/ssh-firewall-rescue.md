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

## OpenRC `network-online.target` error

If you see:

```text
/usr/libexec/rc/sh/gendepends.sh: line 12: network-online.target: not found
```

that is a systemd dependency name leaking into Alpine/OpenRC service dependency generation. Update the repo and reinstall the OpenRC-native AdGuard service:

```sh
cd /root/stoffberg-edge-monitor
git pull
rc-service AdGuardHome stop || true
rm -f /etc/init.d/AdGuardHome
sh scripts/install-adguardhome.sh
rc-service AdGuardHome status
```

## Recover Tiny Edge DNS sync controller

Tiny may become the designated `adguardhome-sync` controller only after a verified one-shot fan-out. If it was disabled during rescue, do not restart recurring synchronization directly. First confirm every configured source/replica is reachable, the YAML contains no placeholders, and the old controller has been stopped. Then run:

```sh
adguardhome-sync run --config /etc/adguardhome-sync/adguardhome-sync.yaml --cron "" --api-port 0
printf '%s\n' 'ADGUARD_SYNC_CUTOVER_APPROVED=true' > /etc/adguardhome-sync/recurring-sync-cutover-approved
chmod 600 /etc/adguardhome-sync/recurring-sync-cutover-approved
rc-update add adguardhome-sync default
rc-service adguardhome-sync start
rc-service adguardhome-sync status
tail -n 100 /var/log/adguardhome-sync.log
```

pve02 CT201 remains the configuration source. Disable its old recurring controller only immediately before Tiny's successful one-shot/recurring cutover; never leave both schedulers active.
