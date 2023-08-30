read -p "AWS Region Code (us-east-1): " aws_region_code

if [[ -z $aws_region_code ]]
then
	aws_region_code=us-east-1
fi

if [[ $aws_region_code = "us-east-1" ]]
then
    echo "SSH to us-east-1 jb"
    ssh ubuntu@ec2-18-209-24-88.compute-1.amazonaws.com -i jb-keypair-${aws_region_code}.pem
    #  -L 8080:localhost:8080
elif [[ $aws_region_code = "us-east-2" ]]
then
    echo "SSH to us-east-2 jb"
elif [[ $aws_region_code = "us-west-1" ]]
then
    echo "SSH to us-west-1 jb"
elif [[ $aws_region_code = "us-west-2" ]]
then
    echo "SSH to us-west-2 jb"
fi
