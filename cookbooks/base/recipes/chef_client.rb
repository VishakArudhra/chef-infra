#
# Cookbook:: base
# Recipe:: chef_client
#
# Run cinc-client every 30 minutes (+ random splay so all servers don't hit the
# Chef Server at once). If someone hand-edits a managed file on a server, the
# next run puts it back: this is "continuous drift correction".
cfg = node['base']['chef_client_timer']

chef_client_systemd_timer 'cinc-client' do
  job_name 'cinc-client'
  interval cfg['interval']
  splay cfg['splay']
  chef_binary_path cfg['binary']
end
