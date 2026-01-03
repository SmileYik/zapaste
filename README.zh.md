# Zapaste

Zapaste 是由 Zig 编程语言和 Zap 网页框架制作的一个类 pastebin 的在线剪切板服务.

[English](./README.md) | [中文](#zapaste)

## Content

- [Zapaste](#zapaste)
  - [Content](#content)
  - [主要功能](#主要功能)
  - [FAQ](#faq)
  - [构建](#构建)
    - [手动构建](#手动构建)
    - [Github Action](#github-action)
  - [如何使用](#如何使用)
    - [如何启动 Zapaste 服务](#如何启动-zapaste-服务)
      - [在本机中运行](#在本机中运行)
      - [在 Docker 中运行](#在-docker-中运行)
    - [HTTP API](#http-api)
  - [配置项](#配置项)
    - [所有可配置项](#所有可配置项)
    - [配置样例](#配置样例)
      - [启用 Swagger](#启用-swagger)
      - [启动内置网页服务器](#启动内置网页服务器)
      - [允许跨域请求](#允许跨域请求)
  - [全局访问控制](#全局访问控制)
    - [Basic 验证器](#basic-验证器)

## 主要功能

- 分页检索公共内容。
- 通过 POST 请求访问受密码保护的内容。
- 支持通过查询参数输出原始文本。
- 随机生成剪切板名称。
- 文件上传和下载。
- 同一文件仅存储一次。
- 可使用 CURL 直接下载文件。
- 自动清理过期粘贴内容。
- 自动清理无用文件。
- RESTful API 接口。
- 可自行部署。

## FAQ

- Q: Zapaste 能在 Windows 上运行吗?
  - 它并不能直接在 Windows 上运行, 但是能够通过 wsl2 或者是 docker 容器运行.
- Q: Zapaste 是否支持文件上传与下载?
  - 对, 它现在基本支持文件的上传与下载, 你可以查看它的Swagger API文档.

## 构建

### 手动构建

在手动构建之前, 需要确保你已经在你的机器上安装了 Zig.

```shell
git clone https://github.com/SmileYik/zapaste.git
cd zapaste
zig build -Doptimize=ReleaseFast
```

### Github Action

你可以在 [github action][zig action] 同挑选一个符合你系统的构建版本进行运行. 如果提示文件已经过期, 那么你可以自行克隆本仓库, 然后你克隆的仓库能够自动重新执行一边构建流程, 之后可以在你自己的仓库的 github action 页面中找到构建好的 zapaste.

## 如何使用

### 如何启动 Zapaste 服务

#### 在本机中运行

Zapaste 是一个单文件应用, 你可以简单的使用 `./zapaste` 指令去运行服务, 在不传入配置文件情况下, 它会自动使用[内置的默认配置文件][default configuration]进行启动.

如果你需要使用自己的客制化配置, 那么你可以使用以下指令去加载你自己的配置文件:

```shell
./zapaste /path/to/your/config.json
```

如果 zapaste 不能访问你所指定的 `/path/to/your/config.json` 配置文件, 那么它会回退到[内置的默认配置文件][default configuration]进行启动.

#### 在 Docker 中运行

你可以直接拉取 Docker 镜像, 然后直接运行它.

这里是一个快速启动样例, 它将使用默认的配置文件去启动 zapaste 服务.

```shell
docker pull ghcr.io/smileyik/zapaste:latest
docker run -p 3000:3000 -it --rm ghcr.io/smileyik/zapaste:latest
```

这里是另一个启动样例, 它能够让你指定你自己的配置文件:

```shell
docker pull ghcr.io/smileyik/zapaste:latest
docker run -it --rm \
    -p 3000:3000 \
    -v $(pwd)/config.json:/app/config.json \
    ghcr.io/smileyik/zapaste:latest
```

如果你想将数据文件映射到本机中, 你需要先修改你的 `config.json` 文件, 找到 `work_dir` 配置项, 将其改为以下内容:

```shell
{
    "work_dir": "/data/",
}
```

之后使用下面的指令去启动容器就可以了:

```shell
docker pull ghcr.io/smileyik/zapaste:latest
docker run -it --rm \
    -p 3000:3000 \
    -v $(pwd)/config.json:/app/config.json \
    -v $(pwd)/data:/data \
    ghcr.io/smileyik/zapaste:latest
```

### HTTP API

你可以在 `resources` 文件夹中找到[Swagger 配置文件][swagger configuration].  
或者直接访问[在线的 Swagger API 文档][online swagger editor]!

## 配置项

示例配置文件可以见[默认配置文件][default configuration].

Zapaste 每一个配置项都含有默认值, 你可以单独修改你想要的配置项, 而不用全部修改!

### 所有可配置项

- **`dao_type`**: 当前只支持 `Sqlite`.

- **`sqlite_options`**: 只有当 `dao_type` 设置为 `Sqlite` 时, 才会加载这个配置项下的内容

  - **`memory_mode`**: 是否启用内存模式, 如果启用了内存模式, 你的所有数据都将会在服务关闭时丢失. 默认值: `false`

  - **`pool_size`**: sqlite 池的大小, 如果你正在使用内存模式 `memory_mode`, 那么这个值只能设定为 `1`. 默认值: `2`

  - **`shared_cache`**: 缓存共享, 默认 `false`,

  - **`pragma`**: 这是一个键值对, 用于在连接池的连接在刚连接时运行类似于后面的这串SQL语句: `SET PRAGMA KEY = VALUE`, 默认为 `null`

- **`swagger`**: swagger 配置

  - **`enable`**: 是否启用 swagger 页面, 如果你启用了swagger, 那么你可以访问 `http://yourhostname:port/swagger` 链接, 去打开 swagger 页面, 默认值为 `false`.

  - **`swagger_config_path`**: swagger 配置文件路径(yml配置文件路径)(这是一个相对路径, 相对于 `work_dir` 而言的, 如果你设置它的值为 `/openapi.yml`, 那么它实际寻找的路径为 `${work_dir}/openapi.yml`), 当你没有为其配置值, 或者配置的配置文件路径不存在, 找不到时, 会自动启用 zapaste 内置的 swagger 配置文件, 默认为 `/openapi.yml`.

  - **`swagger_index_path`**: swagger 的 html 页面的路径, 和 `swagger_config_path` 配置一样, 当不存在时也会自动使用 zapaste 内置的页面, 默认为 `null`

- **`web`**: 静态网页服务器设置

  - **`enable`**: 是否启用静态网页访问, 默认为 `false`

  - **`default_file`**: 默认入口文件, 设置后, 当用户访问一个目录路径时, 会尝试搜索这个目录下是否有入口文件, 若有入口文件则会返回入口文件内容. 例如当设置值为 `index.html` 时, 当用户访问路径 `/admin/` 时, 会自动跳转到 `/admin/index.html`, 默认值为 `index.html`

  - **`prefix`**: 静态网页请求路径前缀, 默认为 `/`

  - **`static_path`**: 静态资源目录路径 (这是相对位置, 相对于 `work_dir` 目录, 如果你设置的值为 `static`, 那么实际访问的目录路径为 `${work_dir}/static`; 如果你设置的值为 `web/static`, 那么实际将访问 `${work_dir}/web/static`). 默认值为 `static`

- **`auth`**: 全局登陆验证配置

  - **`auth_type`**: 验证类型, 当前只有两种验证类型: `None` 和 `Basic`. `None` 意味着不启用全局验证; `Basic` 将提供基本的账号密码访问控制. 默认为 `None`

  - **`skip_auth_path`**: 这是一个键值对配置项, 去控制哪些url能够不登陆即可访问, 也就是设置哪些url能够匿名访问. 键(Key)代表着URL路径, 例如 `/paste`, `/admin`. 它能够使用分号开头的文本代表所有内容, 例如, `/api/paste/:name` 能够代表 `/api/paste/abc` 或者 `/api/paste/def`, 但是不能代表 `/api/paste/abc/delete`; 值(Value)为这个URL路径允许通过哪些HTTP请求方法进行匿名访问, 你能够使用`,`分隔符去制定多个HTTP请求方法. 例如一个完整的键值对如下: `"/api/paste/:name": "GET,POST"`, 这个配置就代表你能够允许路径 `/api/paste/xxxxx` 下的所有的 `GET` 请求和 `POST` 请求, 默认值为 `null`

  - **`basic`**: `Basic` 基础验证方式的配置项

    - **`users`**: 一个键值对, 用于代表可以访问的用户的用户名和密码, Key为用户名, Value为密码, 默认为 `null`

- **`work_dir`**: 工作路径, 默认为 `./`.

- **`upload_dir`**: 文件上传保存的目录路径, 也是相对位置, 相对于 `work_dir`, 如果你设置为 `uploads`, 那么实际上的路径为 `${work_dir}/uploads`). 默认为 `uploads`

- **`bind_port`**: 服务绑定的端口, 默认为 `3000`

- **`max_clients`**: 最大允许服务的客户端数量, 默认为 `1000000`,

- **`enable_log`**: 是否启用日志, 默认为 `true`,

- **`threads`**: 服务的线程数量. 默认为 `2`,

- **`workers`**: 服务的进程数量, 进程之间不共享数据. 默认为 `1`

- **`paste_clean_frequency`**: 清理过期剪切板的频率 (例如阅读数量达到销毁数量或者有效期已过), 时间单位为毫秒, 默认为 `3600000` (每1小时清理一次)

- **`file_clean_frequency`**: 清理无用的上传文件 (没有被剪切板所引用的文件), 时间单位为毫秒, default `3600000` (每1小时清理一次)

- **`custom_headers`**: 这是一个键值对, 用于为所有请求设置响应头. 默认为 `null`

- **`cors_headers`**: 这是一个键值对, 用于为所有 `OPTIONS` 请求设置响应头, 默认为 `null`

### 配置样例

#### 启用 Swagger

你可以简单的按照如下配置. 之后你可以直接访问 `http://your-host-name:your-port/swagger/`.

```json
{
    "swagger": {
        "enable": true
    }
}
```

另外, 你可以在 `resources` 文件夹中找到 [Swagger 配置文件][swagger configuration].

#### 启动内置网页服务器

假设你当前的目录结构如下.

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

- `./config.json` 的内容为

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

- `./static/hello.txt` 以及 `./static/index.html` 这两个文件都含有相同的内容, 都为: 

```text
Hello Zapaste!
```

之后, 你可以简单的在当前文件夹中, 用指令 `./zapaste config.json` 去运行 zapaste, 然后你可以访问以下url, 访问完成后将会在网页中见到 `Hello Zapaste!`:

- `http://your-host-name:your-port/`
- `http://your-host-name:your-port/`
- `http://your-host-name:your-port/hello.txt`

#### 允许跨域请求

当你需要配置跨域请求信息时, 你可以设置自定义请求头 `custom_headers` 以及 `cors_headers`.

例如以下例子, 你能够允许所有的跨域请求:

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

## 全局访问控制

你可以编辑 `config.json` 中的 `auth` 字段去启用全局访问控制, 使得仅有通过登录验证的用户去获得 Zapaste 服务的所有功能体验.

在目前, 仅有 `Basic` 验证器可供使用.

### Basic 验证器

Basic 验证器是一个非常简单的验证器, 它将去校验所有 http 请求的 `authorization` 请求头, 从 `authorization` 请求头中获取请求用户的用户名和密码信息, 之后去你所设置的允许访问的用户名单中比对账户和密码信息是否匹配, 若匹配成功, 则将会进行这个请求的下一步操作, 反之则将会立即阻止访问.

`authorization` 请求头是一个用 base64 编码的字符串, 这个字符串格式为: `$username:$password`. 例如用户名为 `abc`, 密码为 `123456` 的用户想要访问, 那么 `authorization` 请求头的内容应该为 `Basic YWJjOjEyMzQ1Ng==`.

你可以编辑配置文件来添加用户。这里有一个 config.json 示例，在这个示例中，我们使用 `Basic` 身份验证器，并添加了两个用户：`abc` 和 `tom`。用户 `abc` 的密码是 `123456`；`tom` 的密码是 `password`.
此外还配置了 `skip_auth_path`，以便所有人都可以访问 Swagger、查看公共剪切板列表、查看现有剪切板（包括已锁定和未锁定的）以及下载文件（与剪切板一样，也包括已锁定和未锁定的文件）。

```json
"auth": {
    "auth_type": "Basic",
    "basic": {
        "users": {
            "abc": "123456",
            "tom": "password"
        }
    },
    "skip_auth_path": {
        "/swagger": "GET",
        "/swagger/:any": "GET",
        "/api/paste": "GET",
        "/api/paste/:name": "GET,POST",
        "/api/paste/:name/file/name/:filename": "GET,POST"
    }
}
```

[default configuration]: ./resources/config.json
[swagger configuration]: ./resources/swagger/openapi.yml
[zig action]: https://github.com/SmileYik/zapaste/actions/workflows/zig.yml
[online swagger editor]: https://editor.swagger.io/?url=https://raw.githubusercontent.com/SmileYik/zapaste/refs/heads/master/resources/swagger/openapi.zh.yml
