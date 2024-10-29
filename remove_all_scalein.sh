#!/bin/bash
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[*].[AutoScalingGroupName]" \
  --output text \
| while read -r group_name; do
    echo "Scaling Group: $group_name"
    aws autoscaling update-auto-scaling-group \
      --auto-scaling-group-name $group_name \
      --no-new-instances-protected-from-scale-in
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
done
