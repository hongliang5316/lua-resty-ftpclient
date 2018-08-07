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
local co_yield  = coroutine.yield
local co_create = coroutine.create
local co_resume = coroutine.resume
local co_status = coroutine.status

local TIMEOUT = 5000

local _M = {
    _VERSION = '0.1'
}

local commands = {
    "dele", "mkd", "rmd", "cwd", "size", "retr"
}

local mt = { __index = _M }


-- Reimplemented coroutine.wrap, returning "nil, err" if the coroutine cannot
-- be resumed.
local co_wrap = function(func)
    local co = co_create(func)
    if not co then
        return nil, "could not create coroutine"
    else
        return function(...)
            if co_status(co) == "suspended" then
                return select(2, co_resume(co, ...))
            else
                return nil, "can't resume a " .. co_status(co) .. " coroutine"
            end
        end
    end
end


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


local function _con_data_sock(line, data_sock)
    local m, err = ngx.re.match(line, [[(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)]],
                                "jo")
    if not m then
        return nil, "pasv: can't parse ip and port from peer"
    end

    local data_port = tonumber(m[5] * 256) + tonumber(m[6])

    local ip = { m[1], ".", m[2], ".", m[3], ".", m[4] }

    local ok, err = data_sock:connect(concat(ip), data_port)
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

    local _1 = sub(line, 1, 1)
    if tonumber(_1) == 4 or tonumber(_1) == 5 then
        return nil, line
    end

    return line
end


local function greet(sock)
    local line, err = sock:receive()
    if not line then
        return nil, err
    end

    local m = ngx.re.match(line, [[^(\d\d\d)(.?)]], "jo")
    if not m then
        return nil, "non-ftp protocol"
    end

    local code, sep = m[1], m[2]
    local current = code
    local greet = line

    if sep == "-" then --reply is multiline
        repeat
            line, err = sock:receive()
            if not line then
                return nil, err
            end

            local m = ngx.re.match(line, [[^(\d\d\d)(.?)]], "jo")
            if not m then
                return nil, "non-ftp protocol"
            end

            code, sep = m[1], m[2]
            greet = concat({ greet, "\n", line })
        until code == current and sep == " "
    end

    if sep == " " then
        return code, greet
    end
end


function _M.connect(self, opts)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local host = opts.host or "127.0.0.1"
    local port = opts.port or 21
    local user = opts.user
    local pass = opts.password

    local ok, err = sock:connect(host, port)
    if not ok then
        return nil, "failed to connect: " .. err
    end

    local code, greet = greet(sock)
    if not code then
        return nil, greet
    end

    if not ngx.re.find(code, "^(?:1|2)", "jo") then
        return nil, greet
    end

    local cmd = { "user ", user, "\r\n" }
    local bytes, err = sock:send(concat(cmd))
    if not bytes then
        return nil, err
    end

    local line, err = _read_reply(sock)
    if not line then
        return nil, err
    end

    local cmd = { "pass ", pass, "\r\n" }
    local bytes, err = sock:send(concat(cmd))
    if not bytes then
        return nil, err
    end

    return _read_reply(sock)
end


local function _do_cmd(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local args = { ... }
    local cmd = { args[1], " ", args[2], "\r\n" }
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


local function get_data_sock(sock)
    local bytes, err = sock:send("pasv\r\n")
    if not bytes then
        return nil, err
    end

    local line, err = _read_reply(sock)
    if not line then
        return nil, err
    end

    local data_sock, err = ngx.socket.tcp()
    if not data_sock then
        return nil, "data_sock nil, err: " .. err
    end

    data_sock:settimeout(TIMEOUT)

    local res, err = _con_data_sock(line, data_sock)
    if not res then
        return nil, err
    end

    return data_sock
end


function _M.get(self, filename)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local data_sock, err = get_data_sock(sock)
    if not data_sock then
        return nil, err
    end

    local line, err = _M.size(self, filename)
    if not line then
        return nil, err
    end

    local size = tonumber(sub(line, 5, -1))

    local line = _M.retr(self, filename)
    if not line then
        return nil, err
    end

    local data, err = data_sock:receive(size)
    if not data then
        return nil, err
    end

    data_sock:close()

    local line, err = _read_reply(sock)
    if not line then
        return nil, err
    end

    return data
end


function _M.put(self, filename, hex)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local data_sock, err = get_data_sock(sock)
    if not data_sock then
        return nil, err
    end

    local cmd = { "stor ", filename, "\r\n" }
    local bytes, err = sock:send(concat(cmd))
    if not bytes then
        return nil, err
    end

    local line, err = _read_reply(sock)
    if not line then
        return nil,err
    end

    local bytes, err = data_sock:send(hex)
    if not bytes then
        return nil,err
    end

    data_sock:close()

    return _read_reply(sock)
end


local function stream_reader(sock, data_sock, size, default_chunk_size)
    return co_wrap(function(max_chunk_size)
        max_chunk_size = max_chunk_size or default_chunk_size
        local received = 0
        repeat
            local length = max_chunk_size
            if received + length > size then
                length = size - received
            end

            if length > 0 then
                local str, err = data_sock:receive(length)
                if not str then
                    data_sock:close()
                    co_yield(nil, err)
                end
                received = received + length

                max_chunk_size = tonumber(co_yield(str) or default_chunk_size)
                if max_chunk_size and max_chunk_size < 0 then
                    max_chunk_size = nil
                end

                if not max_chunk_size then
                    ngx.log(ngx.ERR, "Buffer size not specified, bailing")
                    break
                end
            end
        until length == 0

        data_sock:close()

        -- read from sock
        local line, err = _read_reply(sock)
        if not line then
            co_yield(nil, err)
        end
    end)
end


function _M.get_by_stream(self, filename, chunk_size)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local data_sock, err = get_data_sock(sock)
    if not data_sock then
        return nil, err
    end

    local line, err = _M.size(self, filename)
    if not line then
        return nil, err
    end

    local size = tonumber(sub(line, 5, -1))

    local line = _M.retr(self, filename)
    if not line then
        return nil, err
    end

    -- return function
    return stream_reader(sock, data_sock, size, chunk_size)
end


return _M
