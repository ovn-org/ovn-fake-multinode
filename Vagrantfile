# coding: utf-8
# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"
Vagrant.require_version ">=1.7.0"

$bootstrap_centos = <<SCRIPT
#dnf -y update ||:  ; # save your time. "vagrant box update" is your friend
dnf -y install git time python3
SCRIPT

$build_images = <<SCRIPT
cd /vagrant && \
OVN_SRC_PATH=./ovn OVS_SRC_PATH=./ovs time ./ovn_cluster.sh build
SCRIPT

$start_ovn_cluster = <<SCRIPT
cd /vagrant && ./ovn_cluster.sh start
SCRIPT

Vagrant.configure(2) do |config|

    vm_memory = ENV['VM_MEMORY'] || '4096'
    vm_cpus = ENV['VM_CPUS'] || '4'

    config.vm.hostname = "ovnhostvm"
    config.vm.box = "generic/rocky8"
    config.vm.box_check_update = false

    # config.vm.synced_folder "#{ENV['PWD']}", "/vagrant", sshfs_opts_append: "-o nonempty", disabled: false, type: "sshfs"
    # Optional: Uncomment line above and comment out the line below if you have
    # the vagrant sshfs plugin and would like to mount the directory using sshfs.
    if ENV['VM_MOUNT_NFS']
      # Mount ovs-multinode base directory trough NFS if requested. We decided
      # not to use sshfs as the installation on Centos8 goes not smoothly.
      config.vm.synced_folder "#{ENV['PWD']}", "/vagrant", type: "nfs",
                              nfs_udp: false,
                              :linux__nfs_options => ['rw','no_subtree_check','no_root_squash']
    else
      config.vm.synced_folder ".", "/vagrant", type: "rsync"
    end

    if ENV['OVS_DIR']
        config.vm.synced_folder ENV['OVS_DIR'], '/vagrant/ovs', type: 'rsync'
    end
    if ENV['OVN_DIR']
        config.vm.synced_folder ENV['OVN_DIR'], '/vagrant/ovn', type: 'rsync'
    end
    config.vm.provision "bootstrap_centos", type: "shell", inline: $bootstrap_centos
    config.vm.provision :shell do |shell|
        shell.privileged = false
        shell.path = 'provisioning/grab_ovn_src.sh'
    end

    config.vm.provision :shell do |shell|
        shell.path = 'provisioning/enable_nesting.sh'
    end

    config.vm.provision :shell do |shell|
        shell.path = 'provisioning/install_docker.sh'
    end

    config.vm.provision "build_images", type: "shell", inline: $build_images, privileged: true

    # Install and start ovs used to interconnect the docker
    # containers that are used to emulate the ovn chassis (below). This does not need
    # to run ovn, since it is purely used as an underlay network.
    config.vm.provision :shell do |shell|
         shell.path = 'provisioning/install_ovs_in_underlay.sh'
    end

    # At last, start the OVN cluster! Comment this out if you are interested in
    # changing how many 'OVN chassis' or 'vms' inside these
    # chassis.
    config.vm.provision "start_ovn_cluster", type: "shell", inline: $start_ovn_cluster, privileged: true

    config.vm.provider 'libvirt' do |lb|
        lb.nested = true
        lb.memory = vm_memory
        lb.cpus = vm_cpus
        lb.suspend_mode = 'managedsave'
    end
    config.vm.provider "virtualbox" do |vb|
       vb.memory = vm_memory
       vb.cpus = vm_cpus
       vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
       vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
       vb.customize [
           "guestproperty", "set", :id,
           "/VirtualBox/GuestAdd/VBoxService/--timesync-set-threshold", 10000
          ]
    end
end
