# Notes on the compute image

All compute nodes (controller + workers) are spun up with an identical 
image — whether they serve as a controller or worker depends on external inputs (provision script).

This image is based on GCE image **Ubuntu 19.10 minimal**.  The following are steps to build our cluster image from this bare image. To automatically create this image, run `src/generate_base_image.sh <name of image>`, which simply runs the commands in this document.

## Steps to generate image:

0. Create dummy VM with bare image

   ```bash
   gcloud compute --project <project> instances create <instance name> --zone <zone> \
   --machine-type n1-standard-1 --image ubuntu-minimal-1910-eoan-v20191113 \
   --image-project ubuntu-os-cloud --boot-disk-size 10GB --boot-disk-type pd-standard
   ```
   
   After we've cloned an image from this machine, we can go ahead and delete it.
   
0. Authenticate on base image

   **TODO**: Is there some way to automate this with a web UI?

   ```bash
   gcloud auth login
   sudo cp -r ~/.config/gcloud /etc/gcloud
   ```
   
   Note that we copy the entire gcloud configuration to a non-user specific directory
   so that running `gcloud` as root will work seamlessly, after setting environment
   variable `CLOUDSDK_CONFIG=/etc/gcloud`.

0. Set up dev environment

   * Update apt package list
     
     ```bash
     sudo apt-get update
     ```

   * Install `build-essential` (C/C++ compilers and headers)
   
     ```bash
     sudo apt-get install build-essential
     ```
     
   * Some other necessary tools

     ```bash
     sudo apt-get install vim git python3-pip
     ```

   * The Slurm installer explicitly expects `/usr/bin/env python`
   to be defined; thus we must
   
     ```bash
     sudo ln -s /usr/bin/python3 /usr/bin/python
     ```
     
     and just to be nice to ourselves,
   
     ```bash
     sudo ln -s /usr/bin/pip3 /usr/bin/pip
     ```
     
1. Install NFS
 
   ```bash
   sudo apt-get install nfs-kernel-server nfs-common portmap
   sudo mkdir -p /mnt/nfs
   ```

   Since the master and worker nodes will have different NFS configurations (server vs.
   clients), all NFS configuration (e.g., configuring `/etc/exports`) will
   happen when the nodes are launched.
   
   Note that the mountpoint `/mnt/nfs` is common across both server and clients; obviously,
   this will correspond to a mounted disk on the server and an NFS mount on the clients.

2. Install Slurm dependencies

   * MySQL (MariaDB)
   
      ```bash
      sudo apt-get install libmariadb-dev mariadb-client mariadb-server
      ```

   * Munge
   
     ```bash
     sudo apt-get install munge libmunge-dev
     ```

   * Miscellaneous: to support cgroups and readline in the Slurm console
   
     ```bash
     sudo apt-get install libhwloc-dev cgroup-tools libreadline-dev
     ```
   
3. Install Slurm
 
   - Download
   
      ```bash
      wget https://download.schedmd.com/slurm/slurm-19.05.3-2.tar.bz2 && \
      tar xjf slurm-19.05.3-2.tar.bz2
      ```
      
      This is the latest version as of November 2019.

   * Configure
   
      ```bash
      cd slurm-19.05.3-2 && \
      ./configure --prefix=/usr/local --sysconfdir=/usr/local/etc --with-mysql_config=/usr/bin --with-hdf5=no
      ```
      
      Note that we must explictly instruct the installer to link with MySQL libraries; this
      is not automatic. If HDF5 libraries are present, a strange bug prevents installation;
      since we will not use HDF5 in our cluster, we preemptively disable linking as a
      precaution.

   * Build and install
   
      ```bash
      make && sudo make install
      ```
      
      This will install Slurm's daemons (`slurmctld`, `slurmd`, and `slurmdbd`) to
      `/usr/local/sbin`, and Slurm's client utilities (e.g., `sinfo`, `squeue`, etc.)
      to `/usr/local/bin`

4. Post-install configuration

   * Enable cgroup enforcement by adding `group_enable=memory swapaccount=1` to whatever
     already exists in `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`.
     
     To do this programatically, we will use `ssed`:
     
     ```bash
     sudo apt-get install ssed
     sudo ssed -R -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/(.*)"(.*)"(.*)/\1"\2 cgroup_enable=memory swapaccount=1"\3/' /etc/default/grub
     ```

   * Add slurm user (and give it its own gcloud credentials)
   
     ```bash
     sudo adduser --disabled-password slurm
     sudo mkdir -p ~slurm/.config
     sudo cp -r /etc/gcloud ~slurm/.config/gcloud
     sudo chown -R slurm:slurm ~slurm/.config/gcloud
     ```

   * Add Slurm logging directory
   
     ```bash
     sudo mkdir -p /var/spool/slurm
     sudo chown slurm:slurm /var/spool/slurm
     ```

   * Setup MySQL
   
     **Start service** (note we do not enable it, since only the server will need it). We 
     just do this here to add the requisite user and permissions.
   
     ```bash
     sudo systemctl start mariadb
     ```
   
     **Configure MySQL**
   
     ```bash
     sudo mysql -u root -e "create user 'slurm'@'localhost'"
     sudo mysql -u root -e "grant all on slurm_acct_db.* TO 'slurm'@'localhost';"
     ```
     
     NB: this is where the current `pipeline-base` image is.
      
   * Mirror this repo
      
     ```bash
     sudo git clone https://github.com/julianhess/cga_pipeline.git /usr/local/share/cga_pipeline
     ```
     
   * Install necessary Python packages

     ```bash
     sudo pip3 install pandas canine
     ```