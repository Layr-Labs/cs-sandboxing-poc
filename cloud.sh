#!/bin/bash

set -e

INSTANCE_NAME="gs-machine"
MACHINE_TYPE="c3-standard-8"
IMAGE_FAMILY="confidential-space-debug"
ZONE="us-central1-a"
PROJECT="data-axiom-440223-j1"
IMAGE_REF="docker.io/saucelord/cs-sandbox:latest"
WORKLOAD_IMAGE="docker.io/saucelord/sandbox-tester:latest"

build() {
    if [ -n "$2" ]; then
        IMAGE_REF="$2"
    fi
    echo "Building Docker image $IMAGE_REF..."
    docker build --platform linux/amd64 -t $IMAGE_REF .

    echo ""
    echo "Pushing container"
    docker push $IMAGE_REF
}

delete() {
    # if $2 exists, use it as the instance name
    if [ -n "$2" ]; then
        INSTANCE_NAME="$2"
    fi
    gcloud compute instances delete $INSTANCE_NAME --zone=$ZONE --project=$PROJECT --quiet
    echo "Instance deleted."
}

create() {
    if [ -n "$2" ]; then
        IMAGE_REF="$2"
    fi
    if [ -n "$3" ]; then
        WORKLOAD_IMAGE="$3"
    fi

    echo "Creating instance with:"
    echo "  Instance name: $INSTANCE_NAME"
    echo "  Container image: $IMAGE_REF"
    echo "  Workload image: $WORKLOAD_IMAGE"
    echo ""

    gcloud compute instances create $INSTANCE_NAME \
        --confidential-compute-type=TDX \
        --machine-type=$MACHINE_TYPE \
        --maintenance-policy=TERMINATE \
        --shielded-secure-boot \
        --image-project=confidential-space-images \
        --image-family=$IMAGE_FAMILY \
        --metadata="^~^tee-image-reference=$IMAGE_REF~tee-container-log-redirect=true~tee-env-IMAGE=$WORKLOAD_IMAGE~tee-cgroup-ns=true~tee-added-capabilities=[\"CAP_SYS_ADMIN\",\"CAP_SYS_RESOURCE\"]" \
        --service-account=workload-sa@data-axiom-440223-j1.iam.gserviceaccount.com \
        --scopes=cloud-platform \
        --boot-disk-size=30G \
        --zone=$ZONE \
        --project=$PROJECT

    echo ""
    echo "Instance created."
    echo "The workload will run: $WORKLOAD_IMAGE"
}

describe() {
    gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --project=$PROJECT
}

logs() {
    if [ -n "$2" ]; then
        INSTANCE_NAME="$2"
    fi

    # Create logs directory if it doesn't exist
    mkdir -p logs

    # Generate timestamp for log file
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    LOG_FILE="logs/log_${TIMESTAMP}.txt"

    echo "Logging to: $LOG_FILE"

    while true; do
        gcloud compute instances get-serial-port-output $INSTANCE_NAME | tee -a "$LOG_FILE"
        sleep 1
    done
}

case "$1" in
    build)
        build "$@"
        ;;
    delete)
        delete "$@"
        ;;
    create)
        create "$@"
        ;;
    describe)
        describe "$@"
        ;;
    logs)
        logs "$@" 
        ;;
    *)
        echo "Usage: $0 {build|delete|create|logs}"
        echo ""
        echo "Examples:"
        echo "  $0 build                                       # Build and push container"
        echo "  $0 create                                      # Create with default nginx:alpine workload"
        echo "  $0 create my-instance                          # Custom instance name"
        echo "  $0 create my-instance my-image:tag             # Custom container image"
        echo "  $0 create my-instance my-image:tag alpine:latest  # Custom workload image"
        echo "  $0 logs                                        # View logs"
        echo "  $0 logs my-instance                            # View logs for specific instance"
        echo "  $0 delete                                      # Delete instance"
        exit 1
        ;;
esac
