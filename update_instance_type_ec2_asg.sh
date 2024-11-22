#!/bin/bash

# Cluster name and instance type required
if [ "$#" -lt 2 ]; then
  printf "Missing required argument.\n\
Usage: update_instance_type.sh <CLUSTER_NAME> <INSTANCE_TYPE>\n\
Example: update_instance_type.sh quality-assurace-cluster r6i.2xlarge\n"
  exit 1
fi

###############
#Set variables#
###############
cluster_name=$1
new_instance_type=$2

# Gather AutoScalingGroups
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?Tags[?Key=='kubernetes.io/cluster/${cluster_name}']].[AutoScalingGroupName]" \
  --output text \
  | while read -r group_name; do
    echo "Scaling Group: $group_name"
    aws autoscaling update-auto-scaling-group \
      --auto-scaling-group-name $group_name \
      --mixed-instances-policy '{"LaunchTemplate": {"Overrides": [{"InstanceType": "'$2'"}]}}'

  # Refresh the instance for changes to take affect, Prioritizing availability
    aws autoscaling start-instance-refresh \
      --auto-scaling-group-name ${group_name} \
      --preferences '{"InstanceWarmup": 15, "MinHealthyPercentage": 100, "MaxHealthyPercentage": 110}'

  # Echo out the status of the instance refresh for manual validation
    aws autoscaling describe-instance-refreshes \
    --auto-scaling-group-name ${group_name} \
    --query InstanceRefreshes[0]
    done 
