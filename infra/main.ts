import { Construct } from "constructs";
import { App, TerraformStack } from "cdktf";

import { AzurermProvider } from "@cdktf/provider-azurerm/lib/provider";
import { VirtualNetwork } from "@cdktf/provider-azurerm/lib/virtual-network"
import { Subnet } from "@cdktf/provider-azurerm/lib/subnet";import { PublicIp } from "@cdktf/provider-azurerm/lib/public-ip";
import { NetworkSecurityGroup } from "@cdktf/provider-azurerm/lib/network-security-group";
import { NetworkInterface } from "@cdktf/provider-azurerm/lib/network-interface";
import { NetworkInterfaceSecurityGroupAssociation } from "@cdktf/provider-azurerm/lib/network-interface-security-group-association";
import { LinuxVirtualMachine } from "@cdktf/provider-azurerm/lib/linux-virtual-machine";

let SUB_ID = process.env.ARM_SUBSCRIPTION_ID;
let LOCATION = "eastus";
let RESOURCE_GROUP = process.env.RG || "matchbox";

class MyStack extends TerraformStack {
  constructor(scope: Construct, id: string) {
    super(scope, id);

    new AzurermProvider(this, "segv",  {
      subscriptionId: SUB_ID,
      features: {},
    })

    // TODO: Pull into a class.
    var vnet = new VirtualNetwork(this,
      "vm-vnet", {
        name: "matchbox-vnet",
        resourceGroupName: RESOURCE_GROUP,
        addressSpace: ["10.44.0.0/16"],
        location: LOCATION,
      });

    let subnet = new Subnet(this, "vm-subnet", {
      name: "matchbox-subnet",
      resourceGroupName: RESOURCE_GROUP,
      virtualNetworkName: vnet.name,
      addressPrefixes: ["10.44.1.0/24"],
    });

    // Public IP
    let ip = new PublicIp(this, "vm-ip", {
      name: "matchbox-ip",
      location: LOCATION,
      resourceGroupName: RESOURCE_GROUP,
      allocationMethod: "Dynamic", // TODO: Static?
    });

    // Network Security Group
    var nsgName = "matchbox-nsg";
    let nsg = new NetworkSecurityGroup(this, "vm-nsg", {
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
    let nic = new NetworkInterface(this, "vm-iface", {
      name: "matchbox-nic",
      location: LOCATION,
      resourceGroupName: RESOURCE_GROUP,
      ipConfiguration: [ 
        {
          name: "vm-ip-cfg",
          subnetId: subnet.id,
          privateIpAddressAllocation: "Dynamic",
          publicIpAddressId: ip.id,
        }
      ]
    });

    // NSG - Network Association
    new NetworkInterfaceSecurityGroupAssociation(this, "vm-nsg-net", {
      networkInterfaceId: nic.id,
      networkSecurityGroupId: nsg.id,
    });

    new LinuxVirtualMachine(this, "vm", {
      name: "matchbox-vm",
      adminUsername: "core",
      adminSshKey:  [{
        publicKey: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDjpmczEfZhGWR+7wej+x+BpacXQwzrJt5HmxVL7ZqFPl9ML2X1lGJxpTlkss19y9gF+bjbkDSbX4q9MFMwGvyJNVvxKp0mRnzeDTdvfy1IXyiPEOJX/o4gvP/e3uP9WSJvq/hJ/8S42w+4KZ5giU89UQhyTb0bhrPL2C1bIV8HKIfMqKcPlBCauXmzmeZvHh3SywntjaqzdXp8OdeuiHLhlW+lJKUq+ajrvKOZZA2F2IE7Biy3QQtNDf1VwgAQK2p40PbQONR1eMMDKVXsNQtGuVMm4CPwbryqyAmJcigRyb9SrluQ1mW8cQW6b4SI8l1Qxt1oDKCvxCD3NA0G+QT7",
        username: "core"
      }],
      location: LOCATION,
      resourceGroupName: RESOURCE_GROUP,
      networkInterfaceIds: [nic.id],
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

const app = new App();
new MyStack(app, "src");
app.synth();
