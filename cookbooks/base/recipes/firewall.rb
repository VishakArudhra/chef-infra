#
# Cookbook:: base
# Recipe:: firewall
#
# ufw has no built-in Chef resource, so this uses `execute` with guards.
# The guards (not_if) are what make it idempotent: run it twice, nothing changes.

package 'ufw'

# Allow rules first, so enabling the firewall can never lock out SSH.
node['base']['firewall']['allow'].each do |name, port|
  execute "ufw allow #{name} (#{port}/tcp)" do
    command "ufw allow #{port}/tcp"
    not_if "ufw show added | grep -qx 'ufw allow #{port}/tcp'"
  end
end

execute 'ufw enable' do
  command 'ufw --force enable'
  not_if "ufw status | grep -q 'Status: active'"
end
