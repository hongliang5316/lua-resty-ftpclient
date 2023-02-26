# lua-resty-ftpclient

lua-resty-ftpclient - Lua ftp client driver for the ngx_lua based on the cosocket API

## Status

This library is still under early development and is still experimental.

## Simple Usage

```lua

local ftpclient = require "resty.ftpclient"
local cjson = require "cjson"

local ftp = ftpclient:new()
ftp:set_timeout(3000)
local res, err = ftp:connect({
    host = "127.0.0.1",
    port = 21,
    user = "ftpuser",
    password = "123456"
})
if not res then
    ngx.say("failed to connect: ", err)
    return
end

local file = io.open("/tmp/a.txt")
local str = file:read("*a")
file:close()

local res, err = ftp:put("a.txt", str)
if not res then
    ngx.say("failed to put: ", err)
    return
end

ftp:close()
```

## Methods

### new

`syntax: c = client:new()`

### set_timeout

`syntax: c:set_timeout(time)`

Sets the timeout (in ms) protection for subsequent operations, including the connect method.

### set_keepalive

`syntax: ok, err = c:set_keepalive(max_idle_timeout, pool_size)`

Puts the current ftp connection immediately into the ngx_lua cosocket connection pool.

You can specify the max idle timeout (in ms) when the connection is in the pool and the maximal size of the pool every nginx worker process.

In case of success, returns 1. In case of errors, returns nil with a string describing the error.

Only call this method in the place you would have called the close method instead. Calling this method will immediately turn the current ftp object into the closed state. Any subsequent operations other than connect() on the current object will return the closed error.

### get_reused_times

`syntax: times, err = c:get_reused_times()`

This method returns the (successfully) reused times for the current connection. In case of error, it returns nil and a string describing the error.

If the current connection does not come from the built-in connection pool, then this method always returns 0, that is, the connection has never been reused (yet). If the connection comes from the connection pool, then the return value is always non-zero. So this method can also be used to determine if the current connection comes from the pool.

### close

`syntax: ok, err = c:close()`

Closes the current ftp connection and returns the status.

In case of success, returns 1. In case of errors, returns nil with a string describing the error.
