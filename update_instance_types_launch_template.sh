#!/bin/bash

Update_Template() {
aws ec2 create-launch-template-version \
  --launch-template-id $1 \
  --source-version $2 \
  --launch-template-data "InstanceType=$3" \
  --version-description $3 \
  | jq -r '.LaunchTemplateVersion.VersionNumber'
}

# Cluster name required
if [ "$#" -lt 2 ]; then
  printf "Missing required argument.\n\
Usage: update_instance_type.sh <CLUSTER_NAME> <INSTANCE_TYPE>\n"
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

  # Gather LaunchTemplateId
    lt_id=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-name "$group_name" \
      --query "AutoScalingGroups[0].LaunchTemplate.LaunchTemplateId" \
      --output text)
    echo "Launch Template ID: $lt_id"

  # Gather Current LaunchTemplateVersion
    source_ver=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-name "$group_name" \
      --query "AutoScalingGroups[*].Instances[0].LaunchTemplate.Version" \
      --output text)
    echo "Current Launch Template Version: $source_ver"

  # Update ASG to use default Launch Template
    echo "Updating AutoScalingGroup to use Default Launch Template"
    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name "$group_name" \
        --launch-template LaunchTemplateId="$lt_id",Version='$Default'

  # Gather Instance ID
    instance_id=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-name "$group_name" \
      --query "AutoScalingGroups[*].Instances[0].InstanceId" \
      --output text )

  # Create new template version
    new_version=$(Update_Template "$lt_id" "$source_ver" "$new_instance_type")
    echo "New template version: $new_version"

  # Update Launch Template Default Version
    aws ec2 modify-launch-template \
      --launch-template-id $lt_id \
      --default-version $new_version

  # Remove Scale-in Protection for Instance Refresh
    aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-name "$group_name" \
      --query "AutoScalingGroups[*].Instances[0].InstanceId" \
      --output text \
      | while read -r instances;do
        echo "Removing Scale in Protection for: $instances"
        aws autoscaling set-instance-protection \
          --instance-ids $instances \
          --auto-scaling-group-name $group_name \
          --no-protected-from-scale-in
    done

  # Refresh the instance for changes to take affect, Prioritizing availability
    aws autoscaling start-instance-refresh \
      --auto-scaling-group-name ${group_name} \
      --preferences '{"InstanceWarmup": 15, "MinHealthyPercentage": 100, "MaxHealthyPercentage": 110}'

  # Echo out the status of the instance refresh for manual validation
    aws autoscaling describe-instance-refreshes \
    --auto-scaling-group-name ${group_name} \
    --query InstanceRefreshes[0]
done
