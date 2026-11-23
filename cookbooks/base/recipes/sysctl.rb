#
# Cookbook:: base
# Recipe:: sysctl
#
node['base']['sysctl']['settings'].each do |key, value|
  sysctl key do
    value value
  end
end
