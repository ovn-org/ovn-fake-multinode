# ovn-fake-multinode

Step 1: Build the container images.
By default docker is used. Later we will switch to podman

To build run
#OVN_SRC_PATH=<path_t_ovn_src_folder> OVS_SRC_PATH=<path_to_ovs_src_folder> ./ovn_cluster.sh build

This will build 2 docker images 
   * ovn/cinc
   * ovn/ovn-multi-node

Step 2: Start openvswitch in your host.

Step 3: Start the ovn-fake-multinode
#./ovn_cluster.sh start

Note: Right now we need to run as root. We will fix it to run as non-root later.

