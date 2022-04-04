# kong-plugin-request-firewall

A Versatile Request Parameter Validator for Kong API Gateway

[![Build Status](https://app.travis-ci.com/samngms/kong-plugin-request-firewall.svg?branch=master)](https://app.travis-ci.com/samngms/kong-plugin-request-firewall) &nbsp; [![LuaRocks](https://img.shields.io/badge/-LuaRocks-blue)](https://luarocks.org/modules/samngms/kong-plugin-request-firewall)

Tested Kong Version: 1.3, 1.4, 1.5, 2.0

# Validations

There are two global config parameters

| Parameter | Parameter Type | Description |
|-----------|:---------------|:------------|
| `debug` | `boolean` | if true, will return rejection reason in HTTP response body |
| `err_code` | `number` | if set, rejected requests will be in this code, otherwise, rejected requets will be HTTP 400 |
| `exact_match` | map, key=url, value=config | if a matching url config is found, will then check against the config, the system will check `exact_match` before `pattern_match` |
| `pattern_match` | map, key=url, value=config | while `exact_match` is performed by exact string matching, `pattern_match` allows using lua pattern matching in the url |

Per each url path, the HTTP request method should be defined

Per each HTTP request method in the url path, you can specify the content_type 

| Criterion | Criterion's type | Description |
|-----------|:-----------------|:------------|
| `content_type` | `string` | e.g. `application/x-www-url-form-encoded`, will be called as `string.find(request.get_header("Content-Type"), <this_value>, 1, true)` |
| `query` | a map, key=parameter_name, value=config (see below) | the allowed parameters in query string, if not specify, no parameter is allowed in the query string | 
| `allow_unknown_query` | `boolean` | whether the plugin should reject the request when an unknown (or unspecified) query parameter is found, default is false | 
| `body` | a map, key=parameter_name, value=config (see below) | the allowed parameters in request body, if not specify, no parameter is allowed in the request body | 
| `allow_unknown_body` | `boolean` | whether the plugin should reject the request when an unknown (or unspecified) request body parameter is found, default is false | 
| `path` | a map, key=parameter_name, value=config (see below) | the allowed parameters in "path", this is the RESTful API parameters in URL (but not as query string), only valid for `pattern_match`|

*Note:* there is no `allow_unknown_path` because you have to specify the variable in the path, it is impossible to have unknown path variables. But if you don't specify path validations, the implicit pattern is `([^%/]+)`, which means anything but `/`

Per each parameter, you can specify a set of validation criteria

| Criterion | Criterion's type | Description |
|-----------|:-----------------|:------------|
`type` | `string` | it is usually `string\|number\|boolean\|file`, but it can also be a custom type
`allow_null` | `boolean` | if this criteria is true and value is null, all other checks will be skipped 
`is_array` | `number` | `0` means not an array, `1` means must be an array, `2` means _can_ be an array
`required` | `boolean` | whether the parameter is required, otherwise, it is optional
`precision` | `number` | only applicable when `type=number`, the number of decimal number place.
`positive` | `boolean` | only applicable when `type=number`, if ture, the number has to be larger than zero (cannot be zero)
`min` | `number` | `type=number` this is the minimum value (inclusive), `type=string` this is the minimum string length (inclusive), `type=file` this is the minimum file size
`max` | `number` | `type=number` this is the maximum value (inclusive), `type=string` this is the maximum string length (inclusive), `type=file` this is the max file size
`match` | `string` | only applicable when `type=string|file`, the parameter is only valid if it matches this pattern. Note this is Lua pattern matching, not a regex pattern matching. For `type=file` this is matched against `filename`.
`not_match` | `string` | only applicable when `type=string|file`, the parameter is *not* valid if it matches this pattern. Note this is Lua pattern matching, not a regex pattern matching. For `type=file` this is matched against `filename`.
`enum` | `string[]` | only application when `type=string|number`, enumeration type such as `["Monday", "Tuesday", "Wednesday"]` etc

\#1 note for `allow_null`: this is for `null` and empty string for data type `string` and `number`. Moreover, while it is easy and explicit to set a value as `null`, there is not that straight forward to set a value to `null` in `x-www-url-form-encoded`. In Kong, the `x-www-url-form-encoded` will convert `a=1&b&c=3` into `{[a]=1, [b]=true, [c]=3}`. Therefore, in this plugin, if `allow_null` is true, and the value itself is `true`, then the validation will return true.

\#2 note for `is_array`: there is no way to specify an array with 1 element in `application/x-www-form-urlencoded`, therefore you should not use `is_array=1` in query string parameters or body with `x-www-form-urlencoded`

\#3 note for `precision`: for JSON data type, such as `{age: 12.345678}`, the age value is automatically converted into a Lua number, which is a double. Since the precision is not accurate in this caes, it will be disabled. However, if the JSON data is `{age: "12.345678"}`, the string to number conversion is done by the plugin and the precision check will be applied accordingly.

\#4 note for `positive`: for `type=number`, and `min` is not defined, `positived=true` if not defined. 

\#5 note for `match` and `not_match`: these are [Lua pattern](https://www.lua.org/pil/20.2.html) matching, not regular expression pattern matching (which is much more powerful). Please also note these sub-string match, not full string matching. To do full string matching, prefix and suffix with `"^foobar$"`

\#6 note for `enum`: since the `enum` is specified as `string[]`, for `type=number`, the input parameter will be converted into `string` before matching.

# Specifying Path Variables

```js
    pattern_match: {
        // user is %a+
        "/get_balance/${user:%a+}" {
            "GET": {
                path: {
                    user:  {
                        // this is yet another pattern match, this time with a different pattern
                        match: "user%-%d+",
                        min: 10,
                        max: 15
                    }
                }
            }
        },
        "/create/order/${user}/${id:%d+}" {
            "POST": {
                path: {
                    user: {
                        match: "%a+",
                        max: 10
                    },
                    id: {
                        type: "number",
                        min: 10,
                        max: 10000,
                    }
                },
                body: {
                    item_name: {
                        match: "%a+",
                        max: 20
                    },
                    quantity: {
                        type: "number",
                        max: 100
                    }
                }
            }
        }
    }
```

# Custom Type

Let's say we want to validate the following JSON

```js
{
    user: {
        uid: 123,
        roles: ["manager", "finance_dept"]
    },
    transaction: {
        to: "Mary",
        amount: 12.34
    }
}
```
The above data schema can be simulated by the following (let's call it a UserTx class)

```js
UserClass: {
    uid: {type: "number", max: 1000000},
    roles: {type: "string", is_array: 1, min: 1, max: 32}
},
Transaction: {
    to: {type: "string", min: 1, max: 100},
    amount: {type: "number", max: 1000000}
},
UserTx: {
    user: {type: "UserClass"},
    transaction: {type: "Transaction"}
}
```

# Configuration

There are two types of paths in the config, `exact_match` and `pattern_match`

```js
{
    config: {
        exact_match: {
            "/foo/bar1": {
                // configuration for /foo/bar, see below
            },
            "/foo/bar2": {
                // configuration for /foo/bar2, see below
            }
        },
        pattern_match: {
            "/get_balance/${user}": {
                // configuration for "/get_balance/${user}
            },
            "/create/order/${user}/${id}": {
                // configration for "/create/order/${user}/${id}
            }
        }
    }
}
```
And for each path, the HTTP request method should be defined as the key of object.

HTTP request method "*" is for applying the rules for any HTTP request methods in that path.

This case will be illustrated at following example  

For each HTTP request method in the path, the configuration contains the following sections
1. query
2. body
3. custom_classes

Take the above `UserTx` as an example, the config will be

```js
{
    "debug": true,
    "err_code": 499,
    "exact_match:": {
        // 'foobar' is the path, we are inside "exact_match", so this is the exact path, without query string
        // put it inside pattern_match if you want to use wildcard in the pattern (but not implemented yet)
        "/foo/bar": { 
            // can be GET/POST/etc.. use '*' to specify anything
            // if the allowed method is not found, the request will be rejected
            "POST": {
                // the expact content-type, optional, a sub-string match will return true
                "content_type": "application/x-www-url-form-encoded",
                // this is allowed parameters in query string
                "query":{
                    "search": {"type": "string"},
                    "page": {"type": "number", "max": 100}
                },
                // this is allowed parameters in post body
                "body": {
                    "usertx": {"type": "UserTx"},
                    "timestamp": {"type": "number"}
                },
                // any custom classes use in body (or query)
                "custom_classes": {
                    "UserClass": {
                        "uid": {"type": "number", "max": 1000000},
                        "roles": {"type": "string", "is_array": 1, "min": 1, "max": 32}
                    },
                    "Transaction": {
                        "to": {"type": "string", "min": 1, "max": 100},
                        "amount": {"type": "number", "max": 1000000}
                    },
                    "UserTx": {
                        "user": {"type": "UserClass"},
                        "transaction": {"type": "Transaction"}
                    }
                }   
            } 
        }
    }
}
```

Therefore, when setting the plugin via Kong Admin RESTful API

```sh
$ curl -X POST http://localhost:8001/routes/[route_id]/plugins \
-H "Content-Type: application/json" \
-d '{"name": "request-firewall", "config": { whole_config_data_here }}'
```


# Testing the plugin

The easiest way to test Kong plugin is by using [kong-pongo](https://github.com/Kong/kong-pongo)

```sh
$ git clone https://github.com/Kong/kong-pongo ../kong-pongo
$ KONG_VERSION=1.4.x ../kong-pongo/pongo.sh run -v -o gtest ./spec
```

All the Kong server logs can be found in `./servroot/logs`

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



