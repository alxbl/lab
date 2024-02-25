import { Construct } from "constructs";
// import { AzurermProvider } from "@cdktf/provider-azurerm/lib/provider";

import { VirtualNetwork } from "@cdktf/provider-azurerm/lib/virtual-network"
import { Subnet } from "@cdktf/provider-azurerm/lib/subnet";import { PublicIp } from "@cdktf/provider-azurerm/lib/public-ip";
import { NetworkSecurityGroup } from "@cdktf/provider-azurerm/lib/network-security-group";
import { NetworkInterface } from "@cdktf/provider-azurerm/lib/network-interface";
import { NetworkInterfaceSecurityGroupAssociation } from "@cdktf/provider-azurerm/lib/network-interface-security-group-association";
import { LinuxVirtualMachine } from "@cdktf/provider-azurerm/lib/linux-virtual-machine";

let LOCATION = "eastus";
let RESOURCE_GROUP = process.env.RG || "matchbox";

export class AzureVm {
    vnet: VirtualNetwork;
    subnet: Subnet;
    ip: PublicIp;
    nsg: NetworkSecurityGroup;
    nic: NetworkInterface;
    vm: LinuxVirtualMachine;

    constructor(scope: Construct) {
        this.vnet = new VirtualNetwork(scope,
            "vm-vnet", {
              name: "matchbox-vnet",
              resourceGroupName: RESOURCE_GROUP,
              addressSpace: ["10.44.0.0/16"],
              location: LOCATION,
            });
      
          this.subnet = new Subnet(scope, "vm-subnet", {
            name: "matchbox-subnet",
            resourceGroupName: RESOURCE_GROUP,
            virtualNetworkName: this.vnet.name,
            addressPrefixes: ["10.44.1.0/24"],
          });
      
          // Public IP
          this.ip = new PublicIp(scope, "vm-ip", {
            name: "matchbox-ip",
            location: LOCATION,
            resourceGroupName: RESOURCE_GROUP,
            allocationMethod: "Dynamic", // TODO: Static?
          });
      
          // Network Security Group
          var nsgName = "matchbox-nsg";
          this.nsg = new NetworkSecurityGroup(scope, "vm-nsg", {
            name: nsgName,
            location: LOCATION,
            resourceGroupName: RESOURCE_GROUP,
            securityRule: [
              // Allow SSH and HTTPS
              {
                name: "SSH",
                priority: 1000,
                direction: "Inbound",
                access: "Allow",
                protocol: "Tcp",
                sourcePortRange: "*",
                destinationPortRange: "22",
                sourceAddressPrefix: "*",
                destinationAddressPrefix: "*"
              },
              {  name: "HTTPS",
                priority: 1010,
                direction: "Inbound",
                access: "Allow",
                protocol: "Tcp",
                sourcePortRange: "*",
                destinationPortRange: "443",
                sourceAddressPrefix: "*",
                destinationAddressPrefix: "*"
              },
            ]
          });
      
          // Network Interface
          this.nic = new NetworkInterface(scope, "vm-iface", {
            name: "matchbox-nic",
            location: LOCATION,
            resourceGroupName: RESOURCE_GROUP,
            ipConfiguration: [
              {
                name: "vm-ip-cfg",
                subnetId: this.subnet.id,
                privateIpAddressAllocation: "Dynamic",
                publicIpAddressId: this.ip.id,
              }
            ]
          });
      
          // NSG - Network Association
          new NetworkInterfaceSecurityGroupAssociation(scope, "vm-nsg-net", {
            networkInterfaceId: this.nic.id,
            networkSecurityGroupId: this.nsg.id,
          });
      
          this.vm = new LinuxVirtualMachine(scope, "vm", {
            name: "matchbox-vm",
            adminUsername: "core",
            adminSshKey:  [{
              publicKey: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDjpmczEfZhGWR+7wej+x+BpacXQwzrJt5HmxVL7ZqFPl9ML2X1lGJxpTlkss19y9gF+bjbkDSbX4q9MFMwGvyJNVvxKp0mRnzeDTdvfy1IXyiPEOJX/o4gvP/e3uP9WSJvq/hJ/8S42w+4KZ5giU89UQhyTb0bhrPL2C1bIV8HKIfMqKcPlBCauXmzmeZvHh3SywntjaqzdXp8OdeuiHLhlW+lJKUq+ajrvKOZZA2F2IE7Biy3QQtNDf1VwgAQK2p40PbQONR1eMMDKVXsNQtGuVMm4CPwbryqyAmJcigRyb9SrluQ1mW8cQW6b4SI8l1Qxt1oDKCvxCD3NA0G+QT7",
              username: "core"
            }],
            location: LOCATION,
            resourceGroupName: RESOURCE_GROUP,
            networkInterfaceIds: [this.nic.id],
            size: "Standard_B1s",
      
            osDisk: {
              name: "matchbox-os-disk",
              caching: "ReadWrite",
              storageAccountType: "Premium_LRS"
            },
      
            sourceImageReference: {
              publisher: "Canonical",
              offer: "0001-com-ubuntu-server-jammy",
              sku: "22_04-lts",
              version: "latest",
            },
          });
        
    }
}