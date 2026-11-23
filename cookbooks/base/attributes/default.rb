# Everything a site might want to change lives here as a *default* attribute.
# Override per policy (policyfiles/myapp.rb), per policy group, or in kitchen.yml.

default['base']['packages'] = %w(curl vim htop unattended-upgrades)

# --- SSH hardening (drop-in file, so the distro's sshd_config is untouched) ---
default['base']['ssh']['enabled']                 = true
default['base']['ssh']['permit_root_login']       = 'no'
default['base']['ssh']['password_authentication'] = 'no'
default['base']['ssh']['max_auth_tries']          = 3
default['base']['ssh']['x11_forwarding']          = 'no'

# --- Kernel network hardening ---
default['base']['sysctl']['enabled'] = true
default['base']['sysctl']['settings'] = {
  'net.ipv4.conf.all.accept_redirects' => 0,
  'net.ipv4.conf.all.send_redirects' => 0,
  'net.ipv4.conf.all.accept_source_route' => 0,
  'net.ipv4.tcp_syncookies' => 1,
  'net.ipv4.conf.all.log_martians' => 1,
}

# --- Host firewall (ufw). Other cookbooks add their own ports to this hash. ---
default['base']['firewall']['enabled'] = true
default['base']['firewall']['allow']['ssh'] = 22

# --- Deploy user: how Jenkins logs in to run Chef. Least privilege: it may only
#     run cinc-client as root, nothing else. Public keys are NOT secrets, so they
#     can live in attributes; the private key lives only in Jenkins credentials.
default['base']['deploy_user']['name'] = 'deploy'
default['base']['deploy_user']['authorized_keys'] = []
default['base']['deploy_user']['sudo_commands'] = %w(
  /usr/bin/cinc-client
  /usr/bin/chef-client
  /opt/cinc/bin/cinc-client
)

# --- Scheduled Chef runs = continuous drift correction ---
default['base']['chef_client_timer']['enabled']  = true
default['base']['chef_client_timer']['interval'] = '30min'
default['base']['chef_client_timer']['splay']    = '5min'
default['base']['chef_client_timer']['binary']   = '/opt/cinc/bin/cinc-client'

default['base']['banner'] = 'Authorised use only. Managed by Chef - manual changes will be reverted.'
