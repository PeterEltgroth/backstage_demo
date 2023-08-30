#!/bin/bash

read -p "Stack Name (jb-stack): " stack_name
read -p "Operator Name (jumpbox): " operator_name
read -p "AWS Region Code (us-east-1): " aws_region_code


if [[ -z $stack_name ]]
then
    stack_name=jumpbox-stack
fi

if [[ -z $operator_name ]]
then
    operator_name=jumpbox
fi

if [[ -z $aws_region_code ]]
then
    aws_region_code=us-east-1
fi

# TODO: <aws cmd to get it>
vpcId=

cat <<EOF | tee ${stack_name}-${aws_region_code}.yaml
Description: "Creates a Linux operator machine."
Mappings:
  Images:
    us-east-1:
      Id: "ami-04505e74c0741db8d"
    us-east-2:
      Id: "ami-0fb653ca2d3203ac1"
    us-west-1:
      Id: "ami-01f87c43e618bf8f0"
    us-west-2:
      Id: "ami-017fecd1353bcc96e"
Parameters:
  OperatorName:
    Type: String
    Default: $operator_name
    # AllowedValues:
    #   - jumpbox
    #   - jumpbox-1
Resources:
  OperatorKeyPair:
    Type: 'AWS::EC2::KeyPair'
    Properties:
      KeyName: jb-keypair
  OperatorSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      VpcId: $vpcId
      GroupDescription: Security Group for AMIs
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 22
          ToPort: 22
          CidrIp: 0.0.0.0/0
      SecurityGroupEgress:
        - IpProtocol: -1
          CidrIp: 0.0.0.0/0
  OperatorInstance:
    Type: "AWS::EC2::Instance"
    Properties:
      ImageId: !FindInMap
        - Images
        - !Ref AWS::Region
        - Id
      InstanceType: "t3.large"
      KeyName: !Ref OperatorKeyPair
      BlockDeviceMappings:
        - DeviceName: /dev/sda1
          Ebs:
            VolumeSize: 50
            DeleteOnTermination: true
      SecurityGroupIds:
        - !Ref OperatorSecurityGroup
      Tags:
        - Key: "Name"
          Value: !Ref OperatorName
Outputs:
  InstanceId:
    Value: !Ref OperatorInstance
  PublicDnsName:
    Value: !GetAtt OperatorInstance.PublicDnsName
EOF

aws cloudformation create-stack \
    --stack-name ${stack_name} \
    --region ${aws_region_code} \
    --parameters ParameterKey=OperatorName,ParameterValue=${operator_name} \
    --template-body file://${stack_name}-${aws_region_code}.yaml

aws cloudformation wait stack-create-complete --stack-name ${stack_name} --region ${aws_region_code}

aws ec2 describe-key-pairs --filters Name=key-name,Values=jb-keypair --query KeyPairs[*].KeyPairId --output text --region ${aws_region_code}
key_id=$(aws ec2 describe-key-pairs --filters Name=key-name,Values=jb-keypair --query KeyPairs[*].KeyPairId --output text --region ${aws_region_code})

#rm operator/keys/aria-operator-keypair-${aws_region_code}.pem

aws ssm get-parameter --name " /ec2/keypair/${key_id}" --with-decryption \
    --query Parameter.Value --region ${aws_region_code} \
    --output text > operator/keys/jb-keypair-${aws_region_code}.pem

echo

aws cloudformation describe-stacks \
    --stack-name ${stack_name} \
    --region ${aws_region_code} \
    --query "Stacks[0].Outputs[?OutputKey=='PublicDnsName'].OutputValue" --output text
