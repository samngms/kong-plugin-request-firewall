# Testing the plugin

The plugin can only be tested in [Kong Vagrant](https://github.com/Kong/kong-vagrant) environment. 

In `Kong Vagrant` README file, they mention

```sh
$ git clone https://github.com/Kong/kong-plugin
..
$ export KONG_PLUGINS=bundled,myplugin
```

Change that line to 
```sh
$ git clone https://github.com/samngms/kong-plugin-request-firewall kong-plugin
..
$ export KONG_PLUGINS=bundled,kong-plugin-request-firewall
```

This is needed because the Vagrant script hardcoded the path `kong-plugin`

Once everything is ready, you can run the following command
```sh
$ vagrant ssh
... inside vagrant ...
$ cd /kong
$ bin/busted -v -o gtest /kong-plugin/spec
```

# About luarocks

If you use `brew install kong`, it actually install both `kong` and `openresty`, with `luarocks` installed under `openresty`

Therefore, when you run `luarocks`, you can see there are two trees
- `<your_home>/.luarocks`
- `<path_to_openresty>/luarocks`

However, the rock should be installed inside `kong`, not inside `openresty`

# Installation

To install the plugin into `kong`

```shell script
# luarocks --tree=<path_to_kong> install
```

For example, `path_to_kong` on my machine is `/usr/local/Cellar/kong/1.2.2/`

# Uninstall

```shell script
# luarocks --tree=<path_to_kong> remove kong-plugin-request-firewall
```

# Configuration

Kong Plugin Admin API can be in Json

```http request
POST /routes/c63128b9-7e71-47ff-80e7-dbea406d06fc/plugins HTTP/1.1
Host: localhost:8001
User-Agent: burp/1.0
Accept: */*
Content-Type: application/json
Content-Length: 377

{"name":"reqvalidatorce","config":{"query":[{"name": "fullname", "type":"string", "required":false, "validation":"abc"},{"name": "age", "type":"number", "required":false, "validation":"01"}],"body":[{"name":"manager","type":"string"},{"name":"salary","type":"number"}],"class_ref":{"name":"helloclass","fields":[{"name":"id","type":"number"},{"name":"date","type":"string"}]}}}
```



