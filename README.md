# Running Spark on Kubernetes @ DigitalOcean

In this journey, we are going to tackle the 2021 DigitalOcean Kubernetes Challenge, specifically spinning up a Spark cluster on Kubernetes on DigitalOcean infrastructure to tackle big data. We will be deploying an example Python application.

## Install doctl and register API Key

This will allow us to interact with DigitalOcean via the command line. 

[Install and configure doctl, the official DigitalOcean command-line client (CLI).](https://docs.digitalocean.com/reference/doctl/how-to/install/)

## Deploy Droplet for Management

Now we will create a droplet to utilize for building code and managing the various components such as the Kubernetes cluster. 

This page details DigitalOcean slugs (droplet sizes, Linux images, etc.) - we will use these in the commands below.

[DigitalOcean API Slugs](https://slugs.do-api.dev/)

First, let's get a list of SSH key fingerprints, we will need this in the droplet create command. Pick the fingerprint from the key you want to utilize to log into the system.

    doctl compute ssh-key list

If you have no key, you will need to create and add a ssh key to the list of Digital Ocean keys. The `-C` argument in `ssh-keygen` is for a comment - substitute your e-mail or any unique identifier for reference. It will also prompt you for a password, this is optional however is good practice.

    ssh-keygen -o -a 100 -t ed25519 -f ~/.ssh/do-key -C "john@example.com"
    doctl compute ssh-key create do-key --public-key "`cat ~/.ssh/do-key.pub`"

Now let's create the droplet. First we need to copy the SSH key fingerprint from the key we just created.

    doctl compute droplet create spark-mgmt \
       --region sfo3 \
       --size s-2vcpu-4gb-intel \
       --enable-private-networking \
       --image ubuntu-20-04-x64 \
       --ssh-keys <insert do-key fingerprint from ssh-key list command above>

## Spin Up Kubernetes Cluster

It will take a few minutes to provision your cluster. Grab a cup of cofee, wait back and emjoy a melody!

    doctl k8s cluster create spark-cluster \
       --region sfo3 \
       --node-pool="name=spark-pool;size=s-2vcpu-4gb-intel;count=3"

## Download Kubernetes YAML Configuration

First download the configuration using doctl.

    doctl k8s cluster kubeconfig show spark-cluster > spark-cluster.yaml

## Configure Management Node

### SSH Into Management Node

First, find the IPV4 address for the spark-mgmt node. We will use this in subsequent commands. Lets first get a list of our nondes. 

    doctl compute droplet list

Find the ip of the management node that we created above. Then, copy the Kubernetes configuration file over to the management node.

    ssh -i ~/.ssh/do-key root@<ip-address> "mkdir .kube && chmod 700 .kube"
    scp -i ~/.ssh/do-key spark-cluster.yaml root@<ip-address>:.kube/config
    ssh -i ~/.ssh/do-key root@<ip-address> "chmod 600 .kube/config"

And finally log into the management node so that we can install some required packages below.

    ssh -i ~/.ssh/do-key root@<ip address>

### Update Packages on Management Node

    apt-get update
    apt dist-upgrade -y
    reeboot

### Install Kubernetes Binaries

Run these commands from the newly created spark-mgmt node. 

    sudo apt -y install curl apt-transport-https wget
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt update
    sudo apt -y install vim git curl wget kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl

Following these commands along with copying over the Kubernetes configuration above, you should be able to connect to the kubernetes cluster. Let's list the nodes to test connectivity to Kubernetes.

    root@spark-mgmt:~# kubectl get nodes -o wide

### Install Spark

Download the spark tarball from Apache and untar it to the local directory.

    wget https://dlcdn.apache.org/spark/spark-3.2.0/spark-3.2.0-bin-hadoop3.2.tgz
    mkdir $HOME/apps
    tar -zxvf spark-3.2.0-bin-hadoop3.2.tgz -C $HOME/apps

### Install Docker for Ubuntu 20.04

[Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)

### Setup Environment Variables

Set Spark home directories. These can be added to the $HOME/.bashrc files to persist through a reboot.

    export SPARK_HOME=/root/apps/spark-3.2.0-bin-hadoop3.2
    export PATH=$SPARK_HOME/bin:$PATH

## Create Container Registry on DigitalOcean

### Create the Registry

[DigitalOcean Container Registry Quickstart](https://docs.digitalocean.com/products/container-registry/quickstart/)

### Build and Tag Images and Push Docker Images to DO Registry

On the management node, it is time to build the Docker images that will be utilized by the Python application deployed to Kubernetes. Use the registry name in the tag definition (i.e. replace `<registry_name>` in the commands below with your registry name).

    $SPARK_HOME/bin/docker-image-tool.sh -r registry.digitalocean.com/<registry_name> -t v3.0.2 -p $SPARK_HOME/kubernetes/dockerfiles/spark/bindings/python/Dockerfile -b java_image_tag=14-slim build

Now push the images to DigitalOcean.

    doctl registry login
    docker push registry.digitalocean.com/<registry_name>/spark-py:v3.0.2
    docker push registry.digitalocean.com/<registry_name>/spark:v3.0.2

Next, we need to integrate our registry with our Kubernetes cluster. This is most easily done via the GUI. Click on Registry -> Settings -> DigitalOcean Kubernetes integration and make sure your cluster is selected.

![](__GHOST_URL__/content/images/2021/12/Screen-Shot-2021-12-26-at-12.19.19-PM.png)

## Deploy App to Kubernetes

### Prepare the image containing the example Python application.

First, clone the repository.

    git clone https://github.com/kyletravis/do_k8s_2021.git
    cd do_k8s_2021

Next, build the docker image that will house the sample Python application. Edit Dockerfile and build.sh to include the registry name you created in a previous step using your favorite text editor. Replace `<registry_name>` with your registry name.
    
Finally build and push the new image which contains the sample Python application.

    ./build.sh

### Configure Default Access Control

Allow service account access to namespace default. This ensures that Spark Executors can be successfully spun up.

    kubectl create clusterrolebinding default --clusterrole=edit --serviceaccount=default:default --namespace=default

### Deploy App to Kubernetes

Edit run.k8s.sh: 

    1) replace `<do_kubernetes_cluster>` with the name of your cluster when running `kubectl cluster-info`
    2) replace `<registry_name>` with your registry name. Then execute the script

    ./run.k8s.sh

### Watch the Driver and Executor Pods Deploy Kubernetes

    kubectl get pods -w
    (control+C to exit this screen)

### Look at Logs to View Sample App Output

Once the drivers and executors have completed, record the driver pod name from the previous command. Then run the following to view the output of your program (replace `<driver_name>` with the name of the driver pod from the previous command).

    kubectl logs <dirver_name>

If all works, you'll see the output from the Python script.

## Cleanup

    doctl k8s cluster delete spark-cluster
    doctl compute droplet delete spark-mgmt
