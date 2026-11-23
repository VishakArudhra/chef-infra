# knife / cinc configuration, shared by your Mac and Jenkins.
# Values come from environment variables when set (Jenkins), otherwise the
# defaults below (your Mac). Keys (*.pem) and the data bag secret sit next to this
# file and are git-ignored - never commit them.
current_dir = File.dirname(__FILE__)

chef_server_url   ENV.fetch('CHEF_SERVER_URL', 'https://chef-server.lab.internal/organizations/lab')
node_name         ENV.fetch('CHEF_USER', 'admin')
client_key        ENV.fetch('CHEF_CLIENT_KEY', File.join(current_dir, 'admin.pem'))
trusted_certs_dir File.join(current_dir, 'trusted_certs') # filled by `knife ssl fetch`
cookbook_path     [File.join(current_dir, '..', 'cookbooks')]

# Used by `knife data bag ... --encrypt` and `knife bootstrap --secret-file`.
knife[:secret_file] = ENV.fetch('CHEF_SECRET_FILE', File.join(current_dir, 'encrypted_data_bag_secret'))
