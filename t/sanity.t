
local ftpclient = require "resty.ftpclient"

local ftp = ftpclient:new()
ftp:set_timeout(1000)
local res,err = ftp:connect({
                  host = "192.168.1.152",
                  port = 21,
                  user = "ftpuser",
                  password = "123456"
              })
if not res then
    ngx.say("failed to connect: ", err)
    return
end

local res,err = ftp:mkd("data")
if not res then
    ngx.say("failed to mkd: ", err)
    return
end

local res,err = ftp:cwd("data")
if not res then
    ngx.say("failed to cwd: ", err)
    return
end

--put
local file = io.open("/tmp/a.txt")
local str = file:read("*all")
file:close()
local res,err = ftp:put("a.txt", str)
if not res then
    ngx.say("failed to put: ", err)
    return
end

--get
local res_str,err = ftp:get("a.txt")
if not res_str then
    ngx.say("failed to get: ", err)
    return
end

local file = io.open("/tmp/a2.txt", "w")
file:write(res_str)
file:close()

--delete
local res,err = ftp:dele("a.txt")
if not res then
    ngx.say("failed to dele: ", err)
    return
end

--close
ftp:set_keepalive(0,10)
