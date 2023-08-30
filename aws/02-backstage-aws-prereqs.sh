#!/bin/bash

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
AWS_REGION=$(aws configure get region)

backstage_cl=backstage
# 1. CREATE CLUSTERS
echo
echo "<<< CREATING CLUSTERS >>>"
echo

sleep 5

# NOTE: CHANGE the RoalArn, NodeGroupname, NodeRole, EKS Version, etc.
cat <<EOF | tee 
Description: "Custom VPC for Backstage OSS installation"
Parameters:
  VpcId:
    Type: String
  SubnetId1:
    Type: String
  SubnetId2:
    Type: String
  SubnetId3:
    Type: String
  SubnetId4:
    Type: String
  SecurityGroupId:
    Type: String
Resources:
  EKSClusterBackstage:
    Type: AWS::EKS::Cluster
    Properties:
      Name: backstage
      Version: "1.25"
      RoleArn: "arn:aws:iam::${AWS_ACCOUNT_ID}:role/vmware-eks-role"
      ResourcesVpcConfig:
        SecurityGroupIds:
          - !Ref SecurityGroupId
        SubnetIds:
          - !Ref SubnetId1
          - !Ref SubnetId2
          - !Ref SubnetId3
          - !Ref SubnetId4
  EKSNodeGroupBackstage:
    Type: 'AWS::EKS::Nodegroup'
    DependsOn: EKSClusterBackstage
    Properties:
      NodegroupName: backstage-node-group
      ClusterName: backstage
      NodeRole: 'arn:aws:iam::${AWS_ACCOUNT_ID}:role/vmware-nodegroup-role'
      InstanceTypes: 
        - t3.2xlarge
      DiskSize: 80
      ScalingConfig:
        MinSize: 2
        DesiredSize: 3
        MaxSize: 5
      Subnets:
        - !Ref SubnetId1
        - !Ref SubnetId2
        - !Ref SubnetId3
        - !Ref SubnetId4
EOF

aws cloudformation create-stack --stack-name backstage-stack --region $AWS_REGION \
    --parameters file://backstage-vpc-params.json --template-body file://backstage-stack-${AWS_REGION}.yaml
aws cloudformation wait stack-create-complete --stack-name backstage-stack --region $AWS_REGION

arn=arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster

aws eks update-kubeconfig --name $backstage_cl --region $AWS_REGION

kubectl config rename-context ${arn}/$backstage_cl $backstage_cl

#CONFIGURE CLUSTERS
cluster=$backstage_cl
# clusters=( $backstage_cl )

# for cluster in "${clusters[@]}" ; do

    kubectl config use-context $cluster

    eksctl utils associate-iam-oidc-provider --cluster $cluster --approve

    # 2. INSTALL CSI PLUGIN (REQUIRED FOR K8S 1.23+)
    echo
    echo "<<< INSTALLING CSI PLUGIN ($cluster) >>>"
    echo

    sleep 5

    rolename=${cluster}-csi-driver-role-${AWS_REGION}

    aws eks create-addon \
      --cluster-name $cluster \
      --addon-name aws-ebs-csi-driver \
      --service-account-role-arn "arn:aws:iam::$AWS_ACCOUNT_ID:role/$rolename" \
      --no-cli-pager

    # #https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html
    # aws eks describe-cluster --name $cluster --query "cluster.identity.oidc.issuer" --output text

    #https://docs.aws.amazon.com/eks/latest/userguide/csi-iam-role.html
    oidc_id=$(aws eks describe-cluster --name $cluster --query "cluster.identity.oidc.issuer" --output text | awk -F '/' '{print $5}')
    echo "OIDC Id: $oidc_id"

    # Check if a IAM OIDC provider exists for the cluster
    # https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html
    if [[ -z $(aws iam list-open-id-connect-providers | grep $oidc_id) ]]; then
      echo "Creating IAM OIDC provider"
      if ! [ -x "$(command -v eksctl)" ]; then
        echo "Error `eksctl` CLI is required, https://eksctl.io/introduction/#installation" >&2
        exit 1
      fi

      eksctl utils associate-iam-oidc-provider --cluster $cluster --approve
    fi

cat <<EOF | tee aws-ebs-csi-driver-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/oidc.eks.$AWS_REGION.amazonaws.com/id/$oidc_id"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.$AWS_REGION.amazonaws.com/id/$oidc_id:aud": "sts.amazonaws.com",
          "oidc.eks.$AWS_REGION.amazonaws.com/id/$oidc_id:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

    aws iam create-role \
      --role-name $rolename \
      --assume-role-policy-document file://"aws-ebs-csi-driver-trust-policy.json" \
      --no-cli-pager
      
    aws iam attach-role-policy \
      --role-name $rolename \
      --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
      --no-cli-pager
      
    kubectl annotate serviceaccount ebs-csi-controller-sa \
        eks.amazonaws.com/role-arn=arn:aws:iam::$AWS_ACCOUNT_ID:role/$rolename \
        -n kube-system --overwrite

    rm aws-ebs-csi-driver-trust-policy.json
    
    echo
done