#
# Cookbook:: base
# Recipe:: packages
#
apt_update 'daily' do
  frequency 86_400
  action :periodic
end

package 'baseline packages' do
  package_name node['base']['packages'] # one apt call for the whole list
end

# Security updates install themselves.
file '/etc/apt/apt.conf.d/20auto-upgrades' do
  content <<~CONF
    APT::Periodic::Update-Package-Lists "1";
    APT::Periodic::Unattended-Upgrade "1";
  CONF
  mode '0644'
end

# Login banner (shown before and after SSH login).
%w(/etc/issue.net /etc/motd).each do |path|
  template path do
    source 'banner.erb'
    variables(banner: node['base']['banner'])
    mode '0644'
  end
end
