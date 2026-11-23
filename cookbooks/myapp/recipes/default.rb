#
# Cookbook:: myapp
# Recipe:: default
#
# Run list for an application server: hardened baseline, then the app.
include_recipe 'base::default'
include_recipe 'myapp::java'
include_recipe 'myapp::deploy'
