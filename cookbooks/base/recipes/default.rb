#
# Cookbook:: base
# Recipe:: default
#
# The baseline every server gets. Each concern is its own recipe so you can
# read, test and switch them on/off separately.

include_recipe 'base::packages'
include_recipe 'base::ssh_hardening' if node['base']['ssh']['enabled']
include_recipe 'base::sysctl'        if node['base']['sysctl']['enabled']
include_recipe 'base::firewall'      if node['base']['firewall']['enabled']
include_recipe 'base::deploy_user'
include_recipe 'base::chef_client'   if node['base']['chef_client_timer']['enabled']
