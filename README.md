# rpi-kernel-builder
Build script for the raspberrypi kernel. Builds either mainline or raspberry pi kernel.

This script is meant to be run a Debian system dedicated(can be a VM as well) to kernel compiling and not on the Pi itself. The script pulls in all dependencies to compile the kernel. It uses the default kernel configurations for each pi varient.

It results in a compressed tar file that needs to be transferred to the pi, extracted and deployed manually.
