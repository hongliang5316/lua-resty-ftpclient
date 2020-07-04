# vim:set ft=nginx ts=4 sw=4 et:

use Test::Nginx::Socket::Lua no_plan;
use Cwd qw(cwd);

repeat_each(2);
no_shuffle();

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_package_cpath "/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;";
    lua_socket_log_errors off;
};

$ENV{TEST_NGINX_FTP_PORT} ||= 21;
$ENV{TEST_NGINX_FTP_DIR} ||= cwd();
$ENV{TEST_NGINX_FTP_USER} ||= "ftpuser";
$ENV{TEST_NGINX_FTP_PASSWORD} ||= "123456";

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: mkdir and rmdir
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ftpclient = require "resty.ftpclient"

            local ftp = ftpclient:new()
            ftp:set_timeout(3000)
            local res, err = ftp:connect({
                host = "127.0.0.1",
                port = $TEST_NGINX_FTP_PORT,
                user = "$TEST_NGINX_FTP_USER",
                password = "$TEST_NGINX_FTP_PASSWORD"
            })
            if not res then
                ngx.say("failed to connect: ", err)
                return
            end

            local res, err = ftp:mkd("data")
            if not res then
                ngx.say("failed to mkd ", err)
                return
            end
            ngx.say(res)

            local res, err = ftp:rmd("data")
            if not res then
                ngx.say("failed to rmd ", err)
                return
            end
            ngx.say(res)

            ftp:close()
        ';
    }
--- request
GET /t
--- response_body
257 "/home/ftpuser/data" created
250 Remove directory operation successful.
--- no_error_log
[error]



=== TEST 2: put, get and dele
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ftpclient = require "resty.ftpclient"
            local cjson = require "cjson"

            local ftp = ftpclient:new()
            ftp:set_timeout(3000)
            local res, err = ftp:connect({
                host = "127.0.0.1",
                port = $TEST_NGINX_FTP_PORT,
                user = "$TEST_NGINX_FTP_USER",
                password = "$TEST_NGINX_FTP_PASSWORD"
            })
            if not res then
                ngx.say("failed to connect: ", err)
                return
            end

            local file = io.open("$TEST_NGINX_FTP_DIR/tmp/a.txt")
            local str = file:read("*a")
            file:close()
            ngx.say(ngx.md5(str))

            local res, err = ftp:put("a.txt", str)
            if not res then
                ngx.say("failed to put: ", err)
                return
            end

            --get
            local str, err = ftp:get("a.txt")
            if not str then
                ngx.say("failed to get: ", err)
                return
            end
            ngx.say(ngx.md5(str))

            local res, err = ftp:dele("a.txt")
            if not res then
                ngx.say("failed to dele: ", err)
                return
            end
            ngx.say(res)

            ftp:close()
        ';
    }
--- request
GET /t
--- response_body
ba1f2511fc30423bdbb183fe33f3dd0f
ba1f2511fc30423bdbb183fe33f3dd0f
250 Delete operation successful.
--- no_error_log
[error]



=== TEST 3: get_by_stream
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ftpclient = require "resty.ftpclient"
            local cjson = require "cjson"

            local ftp = ftpclient:new()
            ftp:set_timeout(3000)
            local res, err = ftp:connect({
                host = "127.0.0.1",
                port = $TEST_NGINX_FTP_PORT,
                user = "$TEST_NGINX_FTP_USER",
                password = "$TEST_NGINX_FTP_PASSWORD"
            })
            if not res then
                ngx.say("failed to connect: ", err)
                return
            end

            local file = io.open("$TEST_NGINX_FTP_DIR/tmp/a.txt")
            local str = file:read("*a")
            file:close()

            local res, err = ftp:put("a.txt", str)
            if not res then
                ngx.say("failed to put: ", err)
                return
            end

            -- get_by_stream
            -- 1 byte
            local stream_reader, err = ftp:get_by_stream("a.txt", 1)
            if not stream_reader then
                ngx.say("failed to get_by_stream: ", err)
                return
            end

            repeat
                local chunk, err = stream_reader()
                if err then
                    ngx.log(ngx.ERR, err)
                    return
                end

                if chunk then
                    ngx.say(chunk)
                end
            until not chunk

            local res, err = ftp:dele("a.txt")
            if not res then
                ngx.say("failed to dele: ", err)
                return
            end
            ngx.say(res)

            ftp:close()

        ';
    }
--- request
GET /t
--- response_body
1
2
3


250 Delete operation successful.
--- no_error_log
[error]


=== TEST 4: get_by_stream set large chunk_size
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ftpclient = require "resty.ftpclient"
            local cjson = require "cjson"

            local ftp = ftpclient:new()
            ftp:set_timeout(3000)
            local res, err = ftp:connect({
                host = "127.0.0.1",
                port = $TEST_NGINX_FTP_PORT,
                user = "$TEST_NGINX_FTP_USER",
                password = "$TEST_NGINX_FTP_PASSWORD"
            })
            if not res then
                ngx.say("failed to connect: ", err)
                return
            end

            local file = io.open("$TEST_NGINX_FTP_DIR/tmp/a.txt")
            local str = file:read("*a")
            file:close()
            ngx.say(ngx.md5(str))

            local res, err = ftp:put("a.txt", str)
            if not res then
                ngx.say("failed to put: ", err)
                return
            end

            -- get_by_stream
            -- 1 byte
            local stream_reader, err = ftp:get_by_stream("a.txt", 4096)
            if not stream_reader then
                ngx.say("failed to get_by_stream: ", err)
                return
            end

            local str = ""

            repeat
                local chunk, err = stream_reader()
                if err then
                    ngx.log(ngx.ERR, err)
                    return
                end

                if chunk then
                    str = str .. chunk
                end
            until not chunk

            ngx.say(ngx.md5(str))

            local res, err = ftp:dele("a.txt")
            if not res then
                ngx.say("failed to dele: ", err)
                return
            end
            ngx.say(res)

            ftp:close()

        ';
    }
--- request
GET /t
--- response_body
ba1f2511fc30423bdbb183fe33f3dd0f
ba1f2511fc30423bdbb183fe33f3dd0f
250 Delete operation successful.
--- no_error_log
[error]



=== TEST 4: get_by_stream change chunk_size
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local ftpclient = require "resty.ftpclient"
            local cjson = require "cjson"

            local ftp = ftpclient:new()
            ftp:set_timeout(3000)
            local res, err = ftp:connect({
                host = "127.0.0.1",
                port = $TEST_NGINX_FTP_PORT,
                user = "$TEST_NGINX_FTP_USER",
                password = "$TEST_NGINX_FTP_PASSWORD"
            })
            if not res then
                ngx.say("failed to connect: ", err)
                return
            end

            local file = io.open("$TEST_NGINX_FTP_DIR/tmp/a.txt")
            local str = file:read("*a")
            file:close()

            local res, err = ftp:put("a.txt", str)
            if not res then
                ngx.say("failed to put: ", err)
                return
            end

            -- get_by_stream
            -- 1 byte
            local stream_reader, err = ftp:get_by_stream("a.txt", 1)
            if not stream_reader then
                ngx.say("failed to get_by_stream: ", err)
                return
            end

            repeat
                local chunk, err = stream_reader(2)
                if err then
                    ngx.log(ngx.ERR, err)
                    return
                end

                if chunk then
                    ngx.say(chunk)
                end
            until not chunk

            local res, err = ftp:dele("a.txt")
            if not res then
                ngx.say("failed to dele: ", err)
                return
            end
            ngx.say(res)

            ftp:close()

        ';
    }
--- request
GET /t
--- response_body
12
3

250 Delete operation successful.
--- no_error_log
[error]
