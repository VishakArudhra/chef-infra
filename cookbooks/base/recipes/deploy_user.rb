#
# Cookbook:: base
# Recipe:: deploy_user
#
cfg  = node['base']['deploy_user']
name = cfg['name']

user name do
  comment 'CI deploy account (Jenkins)'
  manage_home true
  shell '/bin/bash'
end

directory "/home/#{name}/.ssh" do
  owner name
  group name
  mode '0700'
end

file "/home/#{name}/.ssh/authorized_keys" do
  content cfg['authorized_keys'].map { |k| "#{k}\n" }.join
  owner name
  group name
  mode '0600'
end

# Built-in `sudo` resource writes /etc/sudoers.d/<name> and validates it with visudo.
sudo name do
  user name
  runas 'root'
  commands cfg['sudo_commands']
  nopasswd true
end
