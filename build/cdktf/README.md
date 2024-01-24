# cdktf.Dockerfile

Dockerfile which creates a container that has all the dependencies required to 
run cdktf and perform deployments.

**Size:** Approximately 1.5GB

## Usage

This behaves exactly like [CDKTF](https://developer.hashicorp.com/terraform/cdktf/cli-reference/commands), 
but it is running in a docker container, so use it like so:

```sh
docker run --rm -v$(pwd):/src \
    -e ENVVAR_NAME=$ENVVAR_VALUE \
-it cdktf <command line arguments>
```

Where `$PWD` should be the directory where your CDKTF definitions are located.

> **NOTE**: You can also drop into a shell by calling `docker run --rm -v$(pwd):/src --entrypoint sh -it cdktf`

You also do not need to remove the container after invoking it, if you prefer reusing the same instance.

## Limitations

- To keep the size down, this image **only supports the TypeScript language** for projects. If you want to use 
python or golang, you will need to install the required
packages in the Docker image.

- Because cdktf is running in a container, it currently cannot use Terraform docker providers without extra work.

