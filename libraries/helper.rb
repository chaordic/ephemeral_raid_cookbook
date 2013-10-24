#
# Cookbook Name:: ephemeral-raid
# Library:: helper
#
# Copyright (C) 2013 Medidata Worldwide
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 
# Notes:
#
# This helper started life as work by RightScale, also under Apache 2.0 License
# https://github.com/rightscale-cookbooks/ephemeral_lvm/tree/white_13_05_acu114901_implement_ephemeral_library_cookbook
#

module EphemeralDevices
  module Helper
    # Identifies the ephemeral devices available on a cloud server based on cloud-specific Ohai data and returns
    # them as an array. This method also does the mapping required for Xen hypervisors (/dev/sdX -> /dev/xvdX).
    #
    # @param cloud [String] the name of cloud
    # @param node [Chef::Node] the Chef node
    #
    # @return [Array<String>] list of ephemeral available ephemeral devices.
    #
    def self.get_ephemeral_devices(cloud, node)
      ephemeral_devices = []
      # Detects the ephemeral devices available on the instance.
      #
      # If the cloud plugin supports block device mapping on the node, obtain the
      # information from the node for setting up block device
      #
      if node[cloud].keys.any? { |key| key.match(/^block_device_mapping_ephemeral\d+$/) }
        ephemeral_devices = node[cloud].map do |key, device|
          if key.match(/^block_device_mapping_ephemeral\d+$/)
            device.match(/\/dev\//) ? device : "/dev/#{device}"
          end
        end

        # Removes nil elements from the ephemeral_devices array if any.
        ephemeral_devices.compact!

        # Servers running on Xen hypervisor require the block device to be in /dev/xvdX instead of /dev/sdX
        if node.attribute?('virtualization') && node['virtualization']['system'] == "xen"
          puts "Mapping for Ephemeral Devices: #{ephemeral_devices.inspect}"
          ephemeral_devices = EphemeralDevices::Helper.fix_device_mapping(
            ephemeral_devices,
            node['block_device'].keys
          )
          Chef::Log.info "Ephemeral devices found for cloud '#{cloud}': #{ephemeral_devices.inspect}"
        end
      else
        # Cloud specific ephemeral detection logic if the cloud doesn't support block_device_mapping
        #
        case cloud
        when 'gce'
          # According to the GCE documentation, the instances have links for ephemeral disks as
          # /dev/disk/by-id/google-ephemeral-disk-*. Refer to
          # https://developers.google.com/compute/docs/disks#scratchdisks for more information.
          #
          ephemeral_devices = node[cloud]['attached_disks']['disks'].map do |device|
            if device['type'] == "EPHEMERAL" && device['deviceName'].match(/^ephemeral-disk-\d+$/)
              "/dev/disk/by-id/google-#{device["deviceName"]}"
            end
          end
          # Removes nil elements from the ephemeral_devices array if any.
          ephemeral_devices.compact!
        else
          Chef::Log.info "Cloud '#{cloud}' is not supported by this cookbook."
        end
      end
      ephemeral_devices
    end

    # Fixes the device mapping on Xen hypervisors. When using Xen hypervisors, the devices are mapped from /dev/sdX to
    # /dev/xvdX. This method will identify if mapping is required (by checking the existence of unmapped device) and
    # map the devices accordingly.
    #
    # @param devices [Array<String>] list of devices to fix the mapping
    # @param node_block_devices [Array<String>] list of block devices currently attached to the server
    #
    # @return [Array<String>] list of devices with fixed mapping
    #
    def self.fix_device_mapping(devices, node_block_devices)
      devices.map! do |device|
        if node_block_devices.include?(device.match(/\/dev\/([a-z]+)$/)[1])
          device
        else
          fixed_device = device.sub("/sd", "/xvd")
          if node_block_devices.include?(fixed_device.match(/\/dev\/([a-z]+)$/)[1])
            fixed_device
          else
            Chef::Log.warn "could not find ephemeral device: #{device}"
          end
        end
      end
      devices.compact
    end
  end
end
