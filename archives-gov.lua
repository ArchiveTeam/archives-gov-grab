dofile("urlcode.lua")
dofile("table_show.lua")

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local items = {}

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

start, end_ = string.match(item_value, "([0-9]+)-([0-9]+)")
for i = start, end_ do
  items[i] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
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
  if string.match(url, "'+")
     or string.match(url, "[<>\\]")
     or string.match(url, "//$") then
    return false
  end

  if string.match(url, "/id/[0-9]+$") then
    if items[tonumber(string.match(url, "/id/([0-9]+)$"))] ~= true then
      return false
    end
  end

  if parenturl ~= nil then
    local num = string.match(parenturl, "^https?://catalog%.archives%.gov/OpaAPI/iapi/v1/id/([0-9]+)$")
    if num ~= nil then
      if items[tonumber(num)] == true then
        return true
      end
    end
  end

  if string.match(url, "_files/[0-9]+/[0-9]+_[0-9]+%.[^%.%?=]+$")
      or string.match(url, "%?download=[a-z]+$")
      or string.match(url, "%.dzi$") then
    return true
  end

  for s in string.gmatch(url, "([0-9]+)") do
    if items[tonumber(s)] == true then
      return true
    end
  end

  return false
end

sorted = function(t)
  local t_sorted = {}
  for n in pairs(t) do
    table.insert(t_sorted, n)
  end
  table.sort(t_sorted)
  return t_sorted
end

merge_query_strings = function(newurl, t)
  for _, arg in ipairs(sorted(t)) do
    newurl = newurl .. arg .. "=" .. t[arg] .. "&"
  end
  if string.match(newurl, "^.+&$") then
    newurl = string.match(newurl, "^(.+)&$")
  end
  return newurl
end

extract_query_string = function(newurl)
  local query_strings = {}
  for query_string in string.gmatch(string.match(newurl, "%?(.+)$"), "([^&]+)") do
    local key, val = string.match(query_string, "^(.+)=(.+)$")
    query_strings[key] = val
  end
  return query_strings
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

  local function basic_search(surl)
    local query_strings = {}

    query_strings["action"] = "search"
    query_strings["facet"] = "true"
    query_strings["facet.fields"] = "tabType"
    query_strings["noSpinner"] = "true"
    query_strings["offset"] = "0"
    query_strings["rows"] = "0"
    query_strings["tabType"] = "all"

    for k, v in pairs(extract_query_string(surl)) do
      if k ~= "offset" and k ~= "tabType" then
        query_strings[k] = v
      end
    end

    check(merge_query_strings("https://catalog.archives.gov/OpaAPI/iapi/v1?", query_strings))
  end

  local function specific_search(surl)
    local query_strings = {}

    query_strings["action"] = "search"
    query_strings["facet"] = "true"
    query_strings["facet.fields"] = "oldScope,level,materialsType,fileFormat,locationIds,dateRangeFacet"
    query_strings["highlight"] = "true"
    query_strings["rows"] = "20"
    if not string.match(surl, "offset=[0-9]+") then
      query_strings["offset"] = "0"
    end
    if not string.match(surl, "tabType=[a-z]+") then
      query_strings["tabType"] = "all"
    end

    for k, v in pairs(extract_query_string(surl)) do
      query_strings[k] = v
    end

    check(merge_query_strings("https://catalog.archives.gov/OpaAPI/iapi/v1?", query_strings))

    if not (string.match(surl, "offset=[0-9]+") or string.match(surl, "tabType=[a-z]+")) then
      check(surl .. "&tabType=all")
      check(surl .. "&tabType=online")
      check(surl .. "&tabType=web")
      check(surl .. "&tabType=document")
      check(surl .. "&tabType=image")
      check(surl .. "&tabType=video")
      check(surl .. "&offset=0")
      check(surl .. "&offset=0&tabType=all")
      check(surl .. "&offset=0&tabType=online")
      check(surl .. "&offset=0&tabType=web")
      check(surl .. "&offset=0&tabType=document")
      check(surl .. "&offset=0&tabType=image")
      check(surl .. "&offset=0&tabType=video")
    end
  end
  
  function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(string.gsub(url, "&amp;", "&"), " ", "+")

    if string.match(url_, "^https?://catalog%.archives%.gov/search%?") then
      abortgrab = true
      print('Not sure what to do with this yet. aborting for now...')
      --basic_search(url_)
      --specific_search(url_)
    end

    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
       and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
       or string.match(newurl, "^[/\\]")
       or string.match(newurl, "^[jJ]ava[sS]cript:")
       or string.match(newurl, "^[mM]ail[tT]o:")
       or string.match(newurl, "^vine:")
       or string.match(newurl, "^android%-app:")
       or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end

  if string.match(url, "^https?://catalog%.archives%.gov/OpaAPI/media/[0-9]+/")
      and status_code ~= 404 and not string.match(url, "download=")
      and not string.match(url, "_files/[0-9]+/[0-9]+_[0-9]+%.[^%.%?=]+$") then
    check(url .. "?download=true")
    check(url .. "?download=false")
  end

  --if string.match(url, "%.dzi$") then
  --  html = read_file(file)
  --  local tilesize = string.match(html, 'TileSize="([0-9]+)"')
  --  local height_full = tonumber(string.match(html, 'Height="([0-9]+)"'))
  --  local width_full = tonumber(string.match(html, 'Width="([0-9]+)"'))
  --  local format = string.match(html, 'Format="([^"]+)"')
  --  local prefix = string.match(url, "^(.+)%.dzi$") .. "_files/"
  --  local max_dimension = math.max(height_full, width_full)
  --  for level=0,math.ceil(math.log(max_dimension)/math.log(2)) do
  --    local size = math.pow(2, level)
  --    for x=0,math.ceil(size/tilesize) do
  --      for y=0,math.ceil(size/tilesize) do
  --        print(prefix .. level .. "/" .. x .. "_" .. y .. "." .. format)
  --        check(prefix .. level .. "/" .. x .. "_" .. y .. "." .. format)
  --      end
  --    end
  --  end
  --end

  if string.match(url, "%.dzi$") and status_code ~= 404 then
    html = read_file(file)
    local format = string.match(html, 'Format="([^"]+)"')
    if format == nil then
      abortgrab = true
    else
      check(string.match(url, "^(.+)%.dzi$") .. "_files/0/0_0." .. format)
    end
  end

  if string.match(url, "_files/[0-9]+/[0-9]+_[0-9]+%.[^%.%?=]+$") then
    local base, level, x, y, format = string.match(url, "^(.+_files/)([0-9]+)/([0-9]+)_([0-9]+)%.([^%.]+)$")
    level = tonumber(level)
    x = tonumber(x)
    y = tonumber(y)
    if status_code == 404 then
      if y ~= 0 then
        check(base .. level .. "/" .. x+1 .. "_0." .. format)
      elseif x ~= 0 then
        check(base .. level+1 .. "/0_0." .. format)
      end
    else
      check(base .. level .. "/" .. x .. "_" .. y+1 ..  "." .. format)
    end
  end
  
  if allowed(url, nil) and not string.match(url, "/OpaAPI/media/")
      and not string.match(url, "^https?://[^/]+%.cloudfront%.net/")
      and not string.match(url, "^https?://s3%.amazonaws%.com") then
    html = read_file(file)

    if string.match(url, "^https?://catalog%.archives%.gov/[^/]*/?iapi/v1.+$") then
      local start, end_ = string.match(url, "^(https?://catalog%.archives%.gov/)[^/]*/?(iapi/v1.+)$")
      check(start .. end_)
      check(start .. "OpaAPI/" .. end_)
    end

    if string.match(url, "^https?://catalog%.archives%.gov/[^/]*/?iapi/v1/id/[0-9]+$") then
      local itemid = string.match(url, "/id/([0-9]+)$")
      for path in string.gmatch(html, '"@path"%s*:%s*"([^"]+)"') do
        if string.match(path, "^\\?/") then
          checknewurl(path)
        else
          checknewurl("https:\\/\\/catalog.archives.gov\\/OpaAPI\\/media\\/" .. itemid .. "\\/" .. path)
          --checknewurl("https:\\/\\/catalog.archives.gov\\/OpaAPI\\/media\\/" .. itemid .. "\\/" .. path .. "?download=true")
          --checknewurl("https:\\/\\/catalog.archives.gov\\/OpaAPI\\/media\\/" .. itemid .. "\\/" .. path .. "?download=false")
        end
      end
    end

    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
       checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      check(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]

  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404) or
    status_code == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 1")
    tries = tries + 1
    if tries >= 5 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
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

