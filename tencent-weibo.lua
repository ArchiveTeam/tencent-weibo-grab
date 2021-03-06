dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()
local urlparse = require("socket.url")
local http = require("socket.http")

local item_value = os.getenv('item_value')
local item_type = os.getenv('item_type')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local item_value_lower = string.lower(item_value)

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local discovered = {}
discovered[item_value] = true

local current_response_url = nil
local current_response_body = nil
local current_response_retry = true
local current_response_retry_reason = nil

local post_ids = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

for ignore in io.open("ignore-user-list", "r"):lines() do
  discovered[ignore] = true
end

reset_current_response = function()
  current_response_url = nil
  current_response_body = nil
  current_response_retry = true
  current_response_retry_reason = nil
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

discover_user = function(user, tries)
  if tries == nil then
    tries = 0
  end
  if discovered[user] then
    return true
  end
  io.stdout:write("Discovered user " .. user .. ".\n")
  io.stdout:flush()
  local body, code, headers, status = http.request(
    "http://blackbird-amqp.meo.ws:23038/tencentweibo-dlrw6xmf4iwbu7qxoekm/",
    "user:" .. user
  )
  if code == 200 or code == 409 then
    discovered[user] = true
    return true
  elseif code == 404 then
    io.stdout:write("Project key not found.\n")
    io.stdout:flush()
  elseif code == 400 then
    io.stdout:write("Bad format.\n")
    io.stdout:flush()
  else
    io.stdout:write("Could not queue discovered user. Retrying...\n")
    io.stdout:flush()
    if tries == 10 then
      io.stdout:write("Maximum retries reached for sending discovered user.\n")
      io.stdout:flush()
      return false
    end
    os.execute("sleep " .. math.pow(2, tries))
    return discover_user(user, tries + 1)
  end
  return false
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(urlparse.unescape(url), "[<>\\%*%$;%^%[%],%(%){}]")
    or string.match(url, "[%?&]lang=[a-z][a-z]_[A-Z][A-Z]")
    or string.match(url, "[%?&]pagesetHome")
    or string.match(url, "^https?://t%.qq%.com/guest/")
    or string.match(url, "^https?://t%.qq%.com/login%.php")
    or string.match(url, "^https?://t%.qq%.com/old/message%.php%?id=[0-9]+$")
    or string.match(url, "^https?://t%.qq%.com/[a-zA-Z0-9%-_]+/?%?preview$")
    or string.match(url, "^https?://t%.qq%.com/[a-zA-Z0-9%-_]+/?%?mode=[01]$")
    or string.match(url, "^https?://t%.qq%.com/[a-zA-Z0-9%-_]+/following$")
    or string.match(url, "^https?://t%.qq%.com/[a-zA-Z0-9%-_]+/follower$")
    or string.match(url, "^https?://t%.qq%.com/[a-zA-Z0-9%-_]+/following%?t=[12]$")
    or string.match(url, "^https?://t%.qq%.com/app/qzphoto/")
    or string.match(url, "^https?://t%.qq%.com/messages/sendbox")
    or string.match(url, "^https?://t%.qq%.com/p/t/[0-9]+%?filter=1&select=9")
    or string.match(url, "^https?://t%.qq%.com/p/t/[0-9]+%?filter=5&select=2")
    or string.match(url, "^https?://t%.qq%.com/p/t/[0-9]+%?filter=6&select=3")
    or string.match(url, "^https?://t%.qq%.com/p/t/[0-9]+%?filter=9&select=10")
    or string.match(url, "^https?://p%.t%.qq%.com/m/home_userinfo%.php")
    or string.match(url, "^https?://p%.t%.qq%.com/levelDetail%.php")
    or string.match(url, "^https?://api%.t%.qq%.com/old/message%.php%?id=[0-9]+&format=1$") then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

--[[  if string.match(url, "^https?://t%.qq%.com/p/t/[0-9]+$")
    and parenturl
    and not string.match(parenturl, "^https?://t%.qq%.com/p/t/[0-9]+") then
    post_ids[string.match(url, "([0-9]+)$")] = true
  end]]

  if string.match(url, "^https?://t%.qq%.com/[^%?]+%?.+&pi=[0-9]+")
    and parenturl
    and string.match(parenturl, "^https?://t%.qq%.com/[^%?]+") then
    current = tonumber(string.match(parenturl, "&pi=([0-9]+)"))
    if not current then
      current = 1
    end
    new = tonumber(string.match(url, "&pi=([0-9]+)"))
    if current + 1 ~= new then
      return false
    end
  end

  if string.match(url, "^https?://[^/]*qlogo%.cn/.")
    or string.match(url, "^https?://[^/]*qpic%.cn/.") then
    return true
  end

  for s in string.gmatch(url, "([a-zA-Z0-9%-_]+)") do
    if string.lower(s) == item_value_lower then
      return true
    end
  end

  local match = string.match(url, "^https?://t%.qq%.com/([a-zA-Z0-9%-_]+)")
  if match and not discover_user(match) then
    io.stdout:write("Error queuing user.\n")
    io.stdout:flush()
    abortgrab = true
  end

  for s in string.gmatch(url, "([0-9]+)") do
    if post_ids[s] then
      return true
    end
  end

  if string.match(url, "^https?://[^/]*url%.cn/[a-zA-Z0-9]+") then
    return true
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
    and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.match(url, "^(.-)%.?$")
    url_ = string.gsub(url_, "&amp;", "&")
    url_ = string.match(url_, "^(.-)%s*$")
    url_ = string.match(url_, "^(.-)%??$")
    url_ = string.match(url_, "^(.-)&?$")
    if string.match(url_, "^https://[^/]*t%.qq%.com/") then
      url_ = string.gsub(url_, "^https://", "http://")
    elseif string.match(url_, "^https?://api%.t%.qq%.com/")
      and not string.match(url_, "g_tk=")
      and allowed(url_, origurl) then
      url_ = url_ .. "&g_tk="
    end
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
      and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      if file ~= nil then
        addedtolist[url_] = true
        addedtolist[url] = true
      end
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/") then
      checknewurl(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^/") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^%.%./") then
      if string.match(url, "^https?://[^/]+/[^/]+/") then
        check(urlparse.absolute(url, newurl))
      else
        checknewurl(string.match(newurl, "^%.%.(/.+)$"))
      end
    elseif string.match(newurl, "^%./") then
      check(urlparse.absolute(url, newurl))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(urlparse.absolute(url, newurl))
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
        or string.match(newurl, "^[/\\]")
        or string.match(newurl, "^%./")
        or string.match(newurl, "^[jJ]ava[sS]cript:")
        or string.match(newurl, "^[mM]ail[tT]o:")
        or string.match(newurl, "^vine:")
        or string.match(newurl, "^android%-app:")
        or string.match(newurl, "^ios%-app:")
        or string.match(newurl, "^%${")) then
      check(urlparse.absolute(url, newurl))
    end
  end

  if allowed(url, nil)
    and not string.match(url, "^https?://[^/]*qlogo%.cn/")
    and not string.match(url, "^https?://[^/]*qpic%.cn/") then
    if current_response_url == url and current_response_body ~= nil then
      html = current_response_body
    else
      html = read_file(file)
    end
    if string.match(url, "^https://[^/]*t%.qq%.com/") then
      check(string.gsub(url, "^https://", "http://"))
    end
    local match1, match2 = string.match(url, "^https?://t%.qq%.com/p/t/([0-9]+)%?(.*&mid=[0-9]+.*)$")
    if match1 and match2 then
      check("http://api.t.qq.com/old/message.php?id=" .. match1 .. "&" .. match2)
    end
    if string.match(url, "^https?://api%.t%.qq%.com/")
      and string.match(html, '^{"') then
      local data = load_json_file(html)
      if data["info"] then
        html = data["info"]
      end
    end
    for url, params in string.gmatch(html, "url%s*:%s*'(http://api%.t%.qq%.com/old/message.php[^']+)'%s*,%s*auto%s*:%s*'([^']+)'") do
      check(url .. "&" .. params .. "&g_tk=")
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  if file ~= nil then
    reset_current_response()
  end

  return urls
end

wget.callbacks.write_to_warc = function(url, http_stat)
  reset_current_response()
  if http_stat["statcode"] == 200
    and string.match(url["url"], "^https?://t%.qq%.com/")
    and allowed(url["url"], nil)
    and not string.match(url["url"], "^https?://t%.qq%.com/p/t/") then
    current_response_retry_reason = "200"
    current_response_retry = true
    return false
  end
  if allowed(url["url"], nil)
    and not string.match(url["url"], "^https?://[^/]*qlogo%.cn/")
    and not string.match(url["url"], "^https?://[^/]*qpic%.cn/") then
    current_response_url = url["url"]
    current_response_body = read_file(http_stat["local_file"])
    wget.callbacks.get_urls(nil, url["url"], nil, nil)
    if (
        string.match(url["url"], "^https?://api%.t%.qq%.com/")
        or string.match(url["url"], "^https?://t%.qq%.com/p/t/[0-9]+%?.*&mid=[0-9]+")
      )
      and string.match(current_response_body, '^{"') then
      local data = load_json_file(current_response_body)
      if data["info"] then
        data = data["info"]
      else
        current_response_retry_reason = "incomplete"
        current_response_retry = true
        return false
      end
      local real_count = string.match(data, '<li class="select">[^%(<]+%(?([^<%)]*)%)?</li>')
      real_count = tonumber(real_count)
      if real_count == nil then
        real_count = 0
      end
      local _, received_count = string.gsub(data, '<div class="msgBox">', "")
      if real_count > received_count
        and not string.match(data, 'href="[^"]*p=[0-9]+[^"]*mid=[^"]*"') then
        current_response_retry_reason = "incomplete"
        current_response_retry = true
        return false
      end
    end
    if string.match(current_response_body, "系统繁忙,请稍后再试")
      or string.match(current_response_body, "想了解TA的近况吗")
      or string.match(current_response_body, "TA还没有上传头像")
      or string.match(current_response_body, '<div%s+class="guide') then
      current_response_retry_reason = "busy"
      current_response_retry = true
      return false
    end
    if string.match(url["url"], "^https?://t%.qq%.com/")
      and string.len(current_response_body) < 20000
      and http_stat["statcode"] ~= 404
      and not string.match(url["url"], "^https?://t%.qq%.com/p/t/[0-9]+%?.*&mid=[0-9]+") then
      current_response_retry_reason = "size"
      current_response_retry = true
      return false
    end
  end
  current_response_retry = false
  return true
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if status_code >= 300 and status_code <= 399
    and not current_response_retry then
    local newloc = urlparse.absolute(url["url"], http_stat["newloc"])
    if downloaded[newloc] == true or addedtolist[newloc] == true
      or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end
  
  if status_code >= 200 and status_code <= 399 then
    downloaded[url["url"]] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    io.stdout:flush()
    return wget.actions.ABORT
  end

  if current_response_retry_reason ~= nil then
    if current_response_retry_reason == "busy" then
      io.stdout:write("Site is busy.\n")
    elseif current_response_retry_reason == "200" then
      io.stdout:write("Should not get 200 on this URL.\n")
    elseif current_response_retry_reason == "incomplete" then
      io.stdout:write("Got incomplete copy of webpage.\n")
    elseif current_response_retry_reason == "size" then
      io.stdout:write("Webpage too small in size.\n")
    end
    io.stdout:flush()
  end

  response_retry = current_response_retry
  response_retry_reason = current_response_retry_reason

  reset_current_response()

  if status_code >= 500
    or (
      status_code >= 400
      and status_code ~= 404
      and status_code ~= 406
      and status_code ~= 451
    )
    or status_code == 0
    or response_retry then
    io.stdout:write("Server returned " .. http_stat.statcode .. " (" .. err .. "). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 12
    if not allowed(url["url"], nil)
      or (
        status_code == 400
        and string.match(url["url"], "^https?://[^/]*qpic%.cn/")
      ) then
      maxtries = 3
    elseif response_retry_reason == "incomplete" then
      maxtries = 2
    end
    if tries >= maxtries then
      io.stdout:write("I give up...\n")
      io.stdout:flush()
      tries = 0
      if maxtries == 3 or response_retry_reason == "incomplete" then
        return wget.actions.EXIT
      else
        return wget.actions.ABORT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end

