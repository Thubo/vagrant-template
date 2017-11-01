class Hosts
  def Hosts.configure(config, settings)
    # Configure scripts path variable
    scriptsPath = File.dirname(__FILE__) + '/scripts'

    # Prevent TTY errors
    config.ssh.shell = "bash -c 'BASH_ENV=/etc/profile exec bash'"
    config.ssh.forward_agent = true

    # Limit port range
    config.vm.usable_port_range = (10200..10500)

    # Set VirtualBox as provider
    config.vm.provider 'virtualbox'

    settings['hosts'].each_with_index do |host, index|
      autostart = host.has_key?('autostart') && host['autostart']

      config.vm.define "#{host['name']}", autostart: autostart do |server|
        server.vm.box = host['box'] || 'laravel/homestead'

        if settings.has_key?('boxes')
          boxes = settings['boxes']

          if boxes.has_key?(server.vm.box)
            server.vm.box_url = settings['boxes'][server.vm.box]
          end
        end

        server.vm.hostname = host['identifier']

        if host['ip'].kind_of?(Array)
          host['ip'].each do |ip|
            server.vm.network 'private_network', ip: ip
          end
        else
          server.vm.network 'private_network', ip: host['ip'] ||= '192.168.10.10#{index}'
        end


        # VirtulBox machine configuration
        server.vm.provider :virtualbox do |vb|
          vb.name = host['identifier']
          vb.customize ['modifyvm', :id, '--memory', '2048']
          vb.customize ['modifyvm', :id, '--cpus', '1']
          vb.customize ['modifyvm', :id, '--cpuexecutioncap', '30']
          vb.customize ['modifyvm', :id, '--natdnsproxy1', 'on']
          vb.customize ['modifyvm', :id, '--natdnshostresolver1', 'on']
          vb.customize ['modifyvm', :id, '--ostype', 'Ubuntu_64']

          if host.has_key?('provider')
            host['provider'].each do |param|
              vb.customize ['modifyvm', :id, "--#{param['directive']}", param['value']]
            end
          end
        end

        # Standardize Ports Naming Schema
        if (host.has_key?('ports'))
          host['ports'].each do |port|
            port['guest'] ||= port['to']
            port['host'] ||= port['map']
            port['protocol'] ||= 'tcp'
          end
        else
          host['ports'] = []
        end

        # Custom ports forwarding
        if host.has_key?('ports')
          host['ports'].each do |port|
            server.vm.network 'forwarded_port', guest: port['guest'], host: port['host'], protocol: port['protocol'], auto_correct: true
          end
        end

        # Public Key For SSH Access
        if host.has_key?('authorize')
          host['authorize'].each do |auth|
            server.vm.provision 'shell' do |s|
              s.privileged = false
              s.inline = 'echo $1 | grep -xq "$1" ~/.ssh/authorized_keys || echo $1 | tee -a ~/.ssh/authorized_keys'
              s.args = [File.read(File.expand_path(auth))]
            end
            server.vm.provision 'shell' do |s|
              s.inline = 'echo $1 | grep -xq "$1" ~/.ssh/authorized_keys || echo $1 | tee -a ~/.ssh/authorized_keys'
              s.args = [File.read(File.expand_path(auth))]
            end
          end
        end

        # Register SSH private keys
        if host.has_key?('keys')
          host['keys'].each do |key|
            server.vm.provision 'shell' do |s|
              s.privileged = false
              s.inline = 'echo "$1" > ~/.ssh/$2 && chmod 600 ~/.ssh/$2'
              s.args = [File.read(File.expand_path(key)), key.split('/').last]
            end
          end
        end

        # Register shared folders
        if host.has_key?('folders')
          host['folders'].each do |folder|
            server.vm.synced_folder folder['map'], folder ['to'], type: "virtualbox"
          end
        end

        # Configure environment variables
        if host.has_key?('variables')
          host['variables'].each do |var|
            server.vm.provision 'shell' do |s|
              s.inline = 'echo "\n#Set environment variable\nexport $1=$2" >> ~/.profile'
              s.args = [var['key'], var['value']]
            end
          end
        end

        # Run custom provisioners
        if host.has_key?('provision')
          host['provision'].each do |file|
            server.vm.provision 'shell', path: file
          end
        end

      end
    end
  end
end
