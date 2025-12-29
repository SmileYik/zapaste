# Zapaste

Zapaste is a Pastebin service built using Zig and the Zap web framework.

## **Key Features:**

- Paginated retrieval of public pastes.
- Password-protected paste access via POST.
- Support for `raw` text output via query parameters.
- random pastebin name
- RESTful API
- Self-hosted

## FAQ

+ Q: Does Zapaste work on Windows?
    - Can not directly work on Windows, but it can work on wsl2 or a docker container.
+ Q: Does support upload/download files?
    - Not now, but still woring for it.

## Build

### Manual

Make sure you are installed zig at first.

```shell
git clone https://github.com/SmileYik/zapaste.git
cd zapaste
zig build -Doptimize=ReleaseFast
```

### Github Action

You can pick one from [github action][zig action]. If file all outdate in github action, then you can clone this repository then the github action will be restart.

## Usage

### Run Service

#### Run Service by Native

You can simplify use `./zapaste` command to run service with [default configuration].

if you wanna use your custom configuration, you can use:

```shell
./zapaste /path/to/your/config.json
```

If zapaste cannot access file `/path/to/your/config.json` then it will fallback to use [default configuration].

#### Run Server By Docker

You can also pull docker image and run it.

This is a quick start example, will using default configuration to launch zapaste service.

```shell
docker pull ghcr.io/smileyik/zapaste:latest
docker run -p 3000:3000 -it --rm smileyik/zapaste:latest
```

There is another example about load your custom configuration:

```shell
docker pull ghcr.io/smileyik/zapaste:latest
docker run -it --rm \
    -p 3000:3000 \
    -v $(pwd)/config.json:/app/config.json \
    smileyik/zapaste:latest
```

If you wanna mount data folder to your local machine, then you can modify your `config.json`:

```shell
{
    "work_dir": "/data/",
}
```

then launch docker container:

```shell
docker pull ghcr.io/smileyik/zapaste:latest
docker run -it --rm \
    -p 3000:3000 \
    -v $(pwd)/config.json:/app/config.json \
    -v $(pwd)/data:/data \
    smileyik/zapaste:latest
```

### HTTP API

You can find [swagger configuration] in `resources` folder.

## Configuration

Example configuration file: [default configuration]

### All Configuration

+ **`dao_type`**: currently only support `Sqlite`.

+ **`sqlite_options`**: only enabled when `dao_type` is `Sqlite`

    + **`memory_mode`**: enable memory mode, the all data will store in memory, and will lose after shutdown service. default: `false`

    + **`pool_size`**: sqlite pool size, if you are using `memory_mode`, it must be `1`. default `2`

    + **`shared_cache`**: share cache, default `false`,

    + **`pragma`**: a key-value map, as same as run sql when sqlite connection be created: `SET PRAGMA KEY = VALUE`, default is `null`

+ **`swagger`**: swagger config

    + **`enable`**: enable swagger or not, if you turn it on, you can access `http://yourhostname:port/swagger` to access swagger page, default `false`.

    + **`swagger_config_path`**: swagger config file path (Relative path, relative to `work_dir`, if you set `/openapi.yml`, then will access file `${work_dir}/openapi.yml`), if file is not found then will return embed api config, default `/openapi.yml`.

    + **`swagger_index_path`**: swagger html file path, like `swagger_config_path`, default `null`

+ **`web`**: static web config

    + **`enable`**: enable static web server, default `false`
    
    + **`default_file`**: lookup default file when access folder url(like `/` or `/admin/`) , default `index.html`

    + **`prefix`**: static web request path prefix, default `/`

    + **`static_path`**: static resources path (Relative path, relative to `work_dir`, if you set `static`, then will access direcory `${work_dir}/static`; if you set `web/static` then `${work_dir}/web/static`). default `static`

+ **`work_dir`**: the directory data stored. default `./`.

+ **`bind_port`**: bind service port, default `3000`

+ **`max_clients`**: max clients, default `1000000`,

+ **`enable_log`**: enable log, default `true`,

+ **`threads`**: how many threads handle http request. default `2`,

+ **`workers`**: how many workers, cannot share memory between workers. default `1`

+ **`custom_headers`**: a key-value map, it's will set custom headers for every http request. default `null`

+ **`cors_headers`**: a key-value map. it's will set headers for every `OPTIONS` http requset, default `null`

### Configuration Example

#### Enable Swagger

you can simply turn it on. then you can access `http://your-host-name:your-port/swagger/`.

```json
{
    "swagger": {
        "enable": true
    }
}
```

By the way, the [swagger configuration], you can find it in `resources` folder.

#### Enable Embed Web Server

Assume your current directory is as follows:

```shell
tree .
.
├── config.json
├── static
│   ├── hello.txt
│   └── index.html
└── zapaste

1 directory, 4 files
```

+ `./config.json` content

```json
{
    "work_dir": "./",
    "web": {
        "enable": true,
        "default_file": "index.html",
        "prefix": "/",
        "static_path": "static"
    }
}
```

+ `./static/hello.txt` and `./static/index.html` has same content

```text
Hello Zapaste!
```

after that, you can simple run `./zapaste config.json` in current directory, then you can access and see `Hello Zapaste!`:

+ `http://your-host-name:your-port/`
+ `http://your-host-name:your-port/`
+ `http://your-host-name:your-port/hello.txt`

#### Allow CORS Request

You need add CROS headers to your http response, to achieve this, you can configure `custom_headers` and `cors_headers`.

For example, you can allow all CROS OPTIONS request by below configuration:

```json
{
    "custom_headers": {
        "Access-Control-Allow-Origin": "*"
    },
    "cors_headers": {
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization"
    }
}
```

[default configuration]: ./resources/config.json
[swagger configuration]: ./resources/swagger/openapi.yml
[zig action]: https://github.com/SmileYik/zapaste/actions/workflows/zig.yml
