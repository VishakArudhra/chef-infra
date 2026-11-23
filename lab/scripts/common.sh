#!/usr/bin/env bash
# Runs on every VM: hosts file, SSH keys from your Mac, swap, basic tools.
set -euo pipefail

echo ">> /etc/hosts: lab entries"
sed -i '/# BEGIN chef-lab/,/# END chef-lab/d' /etc/hosts
{
  echo "# BEGIN chef-lab"
  echo "${LAB_HOSTS}"
  echo "# END chef-lab"
} >> /etc/hosts

echo ">> authorised SSH keys for user vagrant"
if [ -n "${LAB_PUBKEYS:-}" ]; then
  AK=/home/vagrant/.ssh/authorized_keys
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    grep -qxF "$key" "$AK" || echo "$key" >> "$AK"
  done <<< "${LAB_PUBKEYS}"
  chown vagrant:vagrant "$AK"; chmod 600 "$AK"
else
  echo "   WARNING: lab/keys/*.pub is empty - you won't be able to SSH in from your Mac."
fi

echo ">> swap (${SWAP_MB} MB) - small VMs, so give the kernel some headroom"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l "${SWAP_MB}M" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo ">> timezone + base tools"
timedatectl set-timezone Australia/Sydney || true
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates gnupg >/dev/null
echo ">> common provisioning done on $(hostname -f)"
