# Charts

This directory contains the charts used to deploy various applications in the cluster.

While they are intended to be reusable, a lot of them are a work in progress and do not
expose all settings through `values.yaml` and may include hardcoded values specific to this
lab setup.

The goal is to provide a starting base/inspiration to build off of. If an application
exists under `infra/` but its chart is not present here, then it is either a `kustomize` 
application or it uses an upstream chart that I did not author.

Individual charts may have additional documentation depending on how I felt while writing
them or when there is convoluted hackery required to get them working.