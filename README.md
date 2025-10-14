```sh
./build-basic-test.sh # build the workload that will run in the sandbox
./cloud.sh build # build the sandbox container
./cloud.sh create # create an instance running the sandbox container with the workload to be pulled and run
./cloud.sh logs

# when u want to delete the instance
./clous.sh delete
```