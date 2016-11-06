-- Copyright (C) hongliang5316.

local sub = string.sub
local tcp = ngx.socket.tcp
local concat = table.concat
local len = string.len
local null = ngx.null
local pairs = pairs
local unpack = unpack
local setmetatable = setmetatable
local tonumber = tonumber
local error = error
local find = string.find

local TIMEOUT = 1000

local _M = {
    _VERSION = '0.1'
}

local commands = {
    "dele", "mkd", "rmd", "cwd", "size", "retr"
}


local mt = { __index = _M }


function _M.new(self)
    local sock, err = tcp()
    if not sock then
        return nil, err
    end
    return setmetatable({ sock = sock }, mt)
end


function _M.set_timeout(self, timeout)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:settimeout(timeout)
end


function _M.set_keepalive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:setkeepalive(...)
end


function _M.get_reused_times(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:getreusedtimes()
end


function _M.close(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:close()
end


local function StringSplit(string,split)
    local list = {}
    local pos = 1
    if string.find("", split, 1) then -- this would result in endless loops
      return nil,"split matches empty string!"
    end
    while 1 do
      local first, last = string.find(string, split, pos)
      if first then -- found?
        table.insert(list, string.sub(string, pos, first-1))
        pos = last+1
      else
        table.insert(list, string.sub(string, pos))
        break
      end
    end
    return list
end


local function _con_data_sock(line,data_sock)

    local _,_,req_data = find(line,"%((.+)%)")
    if not req_data then
        return nil,"line err"
    end

    local rt = StringSplit(req_data,",")
    local data_port = rt[5]*256+rt[6]   ---获取数据端口

    local ip = {}
    ip[1] = rt[1]
    ip[2] = "."
    ip[3] = rt[2]
    ip[4] = "."
    ip[5] = rt[3]
    ip[6] = "."
    ip[7] = rt[4]

    local ok,err =  data_sock:connect(concat(ip),data_port)
    if not ok then
      return nil,err
    end

    return "data_sock connect ok"
end


local function _read_reply(sock)
    local line, err = sock:receive()
    if not line then
        return nil, err
    end

    local _1 = sub(line,1,1)
    if tonumber(_1) == 4 or tonumber(_1) == 5 then    ---异常状态
        return nil,line                             ---将异常状态与描述信息变成err
    end

    return line
end


function _M.connect(self, opts)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local host = opts.host
    local port = opts.port or 21
    local user = opts.user
    local pass = opts.password

    local ok,err = sock:connect(host,port)
    if not ok then
        return nil, "failed to connect: " .. err
    end

    ---receive until nil
    while true do
        local line,err = sock:receive()
        if not line then
            break
        end
    end

    local cmd = {}
    cmd[1] = "user "
    cmd[2] = user
    cmd[3] = "\r\n"

    local bytes,err = sock:send(concat(cmd))
    if not bytes then
        return nil,err
    end
    local line,err = _read_reply(sock)
    if not line then
        return nil,err
    end

    local cmd = {}
    cmd[1] = "pass "
    cmd[2] = pass
    cmd[3] = "\r\n"

    local bytes,err = sock:send(concat(cmd))
    if not bytes then
        return nil,err
    end

    return _read_reply(sock)
end


local function _do_cmd(self, ...)

    local args = {...}
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local cmd = {}
    cmd[1] = args[1]
    cmd[2] = " "
    cmd[3] = args[2]
    cmd[4] = "\r\n"

    local bytes, err = sock:send(concat(cmd))
    if not bytes then
        return nil, err
    end

    return _read_reply(sock)
end



for i = 1, #commands do
    local cmd = commands[i]

    _M[cmd] =
        function (self, ...)
            return _do_cmd(self, cmd, ...)
        end
end


function _M.get(self,filename)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local bytes,err = sock:send("pasv\r\n")
    if not bytes then
        return nil,err
    end
    local line,err = _read_reply(sock)
    if not line then
        return nil,err
    end

    local data_sock,err =  ngx.socket.tcp()         ---新建一个数据sock连接
    if not data_sock then
        return nil,"data_sock nil,err:"..err
    end
    data_sock:settimeout(TIMEOUT)
    local res,err = _con_data_sock(line,data_sock)
    if not res then
        return nil,err
    end

    local line, err = _M.size(self, filename)
    if not line then
        return nil, err
    end
    local size = sub(line, 5, -1)     ---获取文件大小

    local line = _M.retr(self, filename)    --发送下载命令
    if not line then
        return nil,err
    end

    local data,err = data_sock:receive(size)
    if not data then
        return nil,err
    end

    data_sock:close()                                   ---关闭数据端口

    local line,err = _read_reply(sock)
    if not line then
        return nil,err
    end

    return data
end


function _M.put(self,filename,hex)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local bytes,err = sock:send("pasv\r\n")     ---进入被动模式
    if not bytes then
        return nil,err
    end
     local line,err = _read_reply(sock)
    if not line then
        return nil,err
    end

    local data_sock,err =  ngx.socket.tcp()         ---新建一个数据sock
    if not data_sock then
        return nil,err
    end
    data_sock:settimeout(TIMEOUT)
    local res,err = _con_data_sock(line,data_sock)
    if not res then
        return nil,err
    end

    local cmd = {}
    cmd[1] = "STOR "
    cmd[2] = filename
    cmd[3] = "\r\n"
    local bytes, err = sock:send(concat(cmd))     ---发送上传命令
    if not bytes then
        return nil,err
    end
     local line,err = _read_reply(sock)
    if not line then
        return nil,err
    end

    local bytes, err = data_sock:send(hex)     ---发送流
    if not bytes then
        return nil,err
    end

    data_sock:close()       ---关闭数据端口

    return _read_reply(sock)
end


return _M
