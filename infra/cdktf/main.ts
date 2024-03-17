// import { Construct } from "constructs";
// import { App, TerraformStack } from "cdktf";
// import { readFileSync } from 'node:fs';

// import * as nodes from './nodes.json';

// import { MatchboxProvider } from "./.gen/providers/matchbox/provider";
// import { Typhoon } from "./.gen/modules/typhoon";

// let PKI_ROOT = process.env.EASYRSA_PKI || '../pki';
// console.log(process.env.PWD);

// function readPemCert(path: string): string {
//   let f = readFileSync(path).toString();
//   return f;
// }

// function getLanAddress(): string
// {
//   // HACK: Because Ubiquiti is set to use `.lan` as a domain, it will
//   //       resolve `$HOST.lan` as the device's IP. This should remove the need
//   //       for a self-hosted DNS and tinkering with the network DNS
//   let hostname = readFileSync("/etc/hostname").toString().replace('\n', '');
//   return `${hostname}.lan`;
// }

// class LabStack extends TerraformStack {
//   constructor(scope: Construct, id: string) {
//     super(scope, id);

//     new MatchboxProvider(this, "matchbox", {
//       ca: readPemCert(PKI_ROOT + '/ca.crt'),
//       clientCert: readPemCert(PKI_ROOT + '/client.crt'),
//       clientKey: readPemCert(PKI_ROOT + "/client.key"),
//       endpoint: '127.0.0.1:8081' // bootstrap is local.
//     });

//     new Typhoon(this, "typhoon-module", <any>{ // FIXME: strong typing?
//       clusterName: "h0me",
//       k8SDomainName: "lab.segfault.me", // FIXME: How will this work?
//       cachedInstall: true,
//       matchboxHttpEndpoint: `http://${getLanAddress()}:8080`,
//       osVersion: "39.20240112.3.0",
//       osStream: "stable",  
//       arch: "x86_64", // controllers  
//       ...nodes
//     });
//   }
// }

// const app = new App();
// new LabStack(app, "segv-lab");
// app.synth();
