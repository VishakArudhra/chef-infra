require 'spec_helper'

describe 'myapp::default' do
  let(:runner) do
    ChefSpec::SoloRunner.new do |node|
      node.normal['base']['firewall']['enabled'] = false # covered by base's own specs
    end
  end
  let(:chef_run) { runner.converge(described_recipe) }

  before do
    stub_data_bag_item('secrets', 'myapp').and_return('id' => 'myapp', 'api_key' => 'unit-test-key')
  end

  context 'before Jenkins has published a release' do
    before do
      stub_data_bag_item('releases', 'myapp_local').and_raise(Chef::Exceptions::InvalidDataBagPath)
    end

    it 'prepares the server: java, service user, directories, config, unit' do
      expect(chef_run).to install_package('openjdk-21-jre-headless')
      expect(chef_run).to create_user('myapp').with(shell: '/usr/sbin/nologin')
      expect(chef_run).to create_directory('/opt/myapp/shared')
      expect(chef_run).to create_template('/opt/myapp/shared/application.properties').with(mode: '0640')
      expect(chef_run).to create_systemd_unit('myapp.service')
    end

    it 'does not download or start anything' do
      expect(chef_run).not_to create_remote_file('/opt/myapp/releases/myapp-1.0.7.jar')
      expect(chef_run).not_to start_service('myapp start')
    end
  end

  context 'when releases/myapp_local says 1.0.7' do
    before do
      stub_data_bag_item('releases', 'myapp_local').and_return(
        'id' => 'myapp_local', 'version' => '1.0.7', 'sha256' => 'abc123'
      )
    end

    it 'downloads that exact jar from the artifact repo, verifying its checksum' do
      expect(chef_run).to create_remote_file('/opt/myapp/releases/myapp-1.0.7.jar').with(
        source: ['http://jenkins.lab.internal:8081/myapp/myapp-1.0.7.jar'],
        checksum: 'abc123'
      )
    end

    it 'points current.jar at it and restarts the app (delayed, once)' do
      link = chef_run.link('/opt/myapp/current.jar')
      expect(link).to notify('service[myapp]').to(:restart).delayed
    end

    it 'renders config from attributes + the encrypted secret' do
      expect(chef_run).to render_file('/opt/myapp/shared/application.properties')
        .with_content('server.port=8080')
        .with_content('app.deployed-version=1.0.7')
        .with_content('app.api-key=unit-test-key')
    end

    it 'restarts the app when the config changes' do
      tpl = chef_run.template('/opt/myapp/shared/application.properties')
      expect(tpl).to notify('service[myapp]').to(:restart).delayed
    end
  end
end
