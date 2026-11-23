#!/usr/bin/env bash
# Installs Cinc Server (the free build of Chef Infra Server) and creates:
#   - org "lab"
#   - user "admin"   -> you, from the Mac (knife, cinc push)
#   - user "jenkins" -> the CI pipelines
# Keys and the admin password land in /home/vagrant/keys (copy them to your Mac with scp).
set -euo pipefail

ORG=lab
KEYDIR=/home/vagrant/keys
mkdir -p "$KEYDIR"

if ! command -v cinc-server-ctl >/dev/null 2>&1; then
  echo ">> installing Cinc Server 15 (5-10 minutes)"
  curl -fsSL https://omnitruck.cinc.sh/install.sh | bash -s -- -P cinc-server -v 15
fi

echo ">> configuring server for ${CHEF_FQDN}"
mkdir -p /etc/cinc-project
cat > /etc/cinc-project/cinc-server.rb <<EOF
api_fqdn "${CHEF_FQDN}"
EOF
cinc-server-ctl reconfigure

# Wait until the API answers before creating users.
for i in $(seq 1 30); do
  cinc-server-ctl status >/dev/null 2>&1 && break
  sleep 10
done

create_user() { # name first last email
  local u=$1
  if cinc-server-ctl user-list | grep -qx "$u"; then
    echo ">> user $u already exists"
    return
  fi
  local pw; pw=$(openssl rand -base64 18)
  cinc-server-ctl user-create "$u" "$2" "$3" "$4" "$pw" --filename "$KEYDIR/$u.pem"
  echo "$pw" > "$KEYDIR/$u-password.txt"
  echo ">> created user $u"
}

create_user admin   Lab   Admin   admin@lab.internal
create_user jenkins Jenkins CI    jenkins@lab.internal

if ! cinc-server-ctl org-list | grep -qx "$ORG"; then
  cinc-server-ctl org-create "$ORG" "Chef Lab" --association_user admin --filename "$KEYDIR/$ORG-validator.pem"
fi
cinc-server-ctl org-user-add "$ORG" jenkins --admin || true

chown -R vagrant:vagrant "$KEYDIR"
chmod 700 "$KEYDIR"; chmod 600 "$KEYDIR"/*

echo
echo "=================================================================="
echo " Cinc Server ready: https://${CHEF_FQDN}/organizations/${ORG}"
echo " Keys + passwords are in ${KEYDIR} on this VM."
echo " From your Mac:  scp vagrant@${CHEF_FQDN}:keys/*.pem ~/chef-lab-keys/"
echo "=================================================================="
