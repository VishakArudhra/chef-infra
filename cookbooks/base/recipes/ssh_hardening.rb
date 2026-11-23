#
# Cookbook:: base
# Recipe:: ssh_hardening
#
# Ubuntu reads /etc/ssh/sshd_config.d/*.conf first and the FIRST value wins,
# so a "10-" file beats the cloud image's "50-cloud-init.conf".

package 'openssh-server'

service 'ssh' do
  action :nothing
end

template '/etc/ssh/sshd_config.d/10-hardening.conf' do
  source 'sshd-hardening.conf.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(node['base']['ssh'].to_h.transform_keys(&:to_sym))
  notifies :restart, 'service[ssh]', :delayed
end
