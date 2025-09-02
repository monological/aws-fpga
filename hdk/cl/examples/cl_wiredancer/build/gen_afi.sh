#!/bin/bash

pwd=$(pwd)

export DCP_BUCKET_NAME='abklabs-fpga'
export DCP_FOLDER_NAME='dcp'
export REGION='us-west-2'
export DCP_TARBALL_TO_INGEST="$pwd/checkpoints/$2"
export LOGS_BUCKET_NAME="${DCP_BUCKET_NAME}"
export LOGS_FOLDER_NAME='logs'
export DCP_TARBALL_NAME=$(basename ${DCP_TARBALL_TO_INGEST})
export CL_DESIGN_NAME="$1"
export CL_DESIGN_DESCRIPTION="$1"

echo $DCP_TARBALL_TO_INGEST

aws s3 cp ${DCP_TARBALL_TO_INGEST} s3://${DCP_BUCKET_NAME}/${DCP_FOLDER_NAME}/

aws ec2 create-fpga-image --name ${CL_DESIGN_NAME} --description "${CL_DESIGN_DESCRIPTION}" --input-storage-location Bucket=${DCP_BUCKET_NAME},Key=${DCP_FOLDER_NAME}/${DCP_TARBALL_NAME} --logs-storage-location Bucket=${LOGS_BUCKET_NAME},Key=${LOGS_FOLDER_NAME}/ --region ${REGION}


